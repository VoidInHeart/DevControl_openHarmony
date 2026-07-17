#include "protocol_core.h"

#include <CryptoArchitectureKit/crypto_common.h>
#include <CryptoArchitectureKit/crypto_rand.h>
#include <CryptoArchitectureKit/crypto_sym_cipher.h>
#include <CryptoArchitectureKit/crypto_sym_key.h>

#include <algorithm>
#include <regex>
#include <stdexcept>

namespace {
constexpr char BASE64_URL[] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

int Base64Value(char value)
{
    if (value >= 'A' && value <= 'Z') {
        return value - 'A';
    }
    if (value >= 'a' && value <= 'z') {
        return value - 'a' + 26;
    }
    if (value >= '0' && value <= '9') {
        return value - '0' + 52;
    }
    if (value == '-') {
        return 62;
    }
    if (value == '_') {
        return 63;
    }
    return -1;
}
}

std::vector<uint8_t> ProtocolCore::RandomBytes(size_t length)
{
    OH_CryptoRand *random = nullptr;
    if (OH_CryptoRand_Create(&random) != CRYPTO_SUCCESS || random == nullptr) {
        throw std::runtime_error("secure random initialization failed");
    }
    Crypto_DataBlob output{nullptr, 0};
    OH_Crypto_ErrCode code =
        OH_CryptoRand_GenerateRandom(random, static_cast<int>(length), &output);
    OH_CryptoRand_Destroy(random);
    if (code != CRYPTO_SUCCESS || output.data == nullptr || output.len != length) {
        if (output.data != nullptr) {
            OH_Crypto_FreeDataBlob(&output);
        }
        throw std::runtime_error("secure random generation failed");
    }
    std::vector<uint8_t> bytes(output.data, output.data + output.len);
    OH_Crypto_FreeDataBlob(&output);
    return bytes;
}

std::string ProtocolCore::GenerateMessageId()
{
    return Base64UrlEncode(RandomBytes(16));
}

std::string ProtocolCore::GenerateNonce()
{
    return Base64UrlEncode(RandomBytes(12));
}

std::string ProtocolCore::Base64UrlEncode(const std::vector<uint8_t> &bytes)
{
    std::string result;
    result.reserve((bytes.size() * 4 + 2) / 3);
    size_t index = 0;
    while (index + 3 <= bytes.size()) {
        uint32_t block = (static_cast<uint32_t>(bytes[index]) << 16) |
                         (static_cast<uint32_t>(bytes[index + 1]) << 8) |
                         static_cast<uint32_t>(bytes[index + 2]);
        result.push_back(BASE64_URL[(block >> 18) & 0x3F]);
        result.push_back(BASE64_URL[(block >> 12) & 0x3F]);
        result.push_back(BASE64_URL[(block >> 6) & 0x3F]);
        result.push_back(BASE64_URL[block & 0x3F]);
        index += 3;
    }
    size_t remaining = bytes.size() - index;
    if (remaining == 1) {
        uint32_t block = static_cast<uint32_t>(bytes[index]) << 16;
        result.push_back(BASE64_URL[(block >> 18) & 0x3F]);
        result.push_back(BASE64_URL[(block >> 12) & 0x3F]);
    } else if (remaining == 2) {
        uint32_t block = (static_cast<uint32_t>(bytes[index]) << 16) |
                         (static_cast<uint32_t>(bytes[index + 1]) << 8);
        result.push_back(BASE64_URL[(block >> 18) & 0x3F]);
        result.push_back(BASE64_URL[(block >> 12) & 0x3F]);
        result.push_back(BASE64_URL[(block >> 6) & 0x3F]);
    }
    return result;
}

std::vector<uint8_t> ProtocolCore::Base64UrlDecode(const std::string &value)
{
    std::vector<uint8_t> result;
    uint32_t buffer = 0;
    int bits = 0;
    for (char character : value) {
        int decoded = Base64Value(character);
        if (decoded < 0) {
            throw std::invalid_argument("invalid base64url");
        }
        buffer = (buffer << 6) | static_cast<uint32_t>(decoded);
        bits += 6;
        if (bits >= 8) {
            bits -= 8;
            result.push_back(static_cast<uint8_t>((buffer >> bits) & 0xFF));
        }
    }
    return result;
}

bool ProtocolCore::Crypt(bool encrypt, const std::vector<uint8_t> &key,
                         const std::vector<uint8_t> &nonce,
                         const std::vector<uint8_t> &aad,
                         const std::vector<uint8_t> &input,
                         std::vector<uint8_t> &output,
                         std::vector<uint8_t> &tag)
{
    if (key.size() != 32 || nonce.size() != 12 || (!encrypt && tag.size() != 16)) {
        return false;
    }

    OH_CryptoSymKeyGenerator *generator = nullptr;
    OH_CryptoSymKey *keyContext = nullptr;
    OH_CryptoSymCipherParams *params = nullptr;
    OH_CryptoSymCipher *cipher = nullptr;
    Crypto_DataBlob updateOutput{nullptr, 0};
    Crypto_DataBlob finalOutput{nullptr, 0};

    auto cleanup = [&]() {
        if (updateOutput.data != nullptr) {
            OH_Crypto_FreeDataBlob(&updateOutput);
            updateOutput = {nullptr, 0};
        }
        if (finalOutput.data != nullptr) {
            OH_Crypto_FreeDataBlob(&finalOutput);
            finalOutput = {nullptr, 0};
        }
        if (cipher != nullptr) {
            OH_CryptoSymCipher_Destroy(cipher);
        }
        if (params != nullptr) {
            OH_CryptoSymCipherParams_Destroy(params);
        }
        if (keyContext != nullptr) {
            OH_CryptoSymKey_Destroy(keyContext);
        }
        if (generator != nullptr) {
            OH_CryptoSymKeyGenerator_Destroy(generator);
        }
    };

    if (OH_CryptoSymKeyGenerator_Create("AES256", &generator) != CRYPTO_SUCCESS) {
        cleanup();
        return false;
    }
    Crypto_DataBlob keyBlob{const_cast<uint8_t *>(key.data()), key.size()};
    if (OH_CryptoSymKeyGenerator_Convert(generator, &keyBlob, &keyContext) !=
        CRYPTO_SUCCESS) {
        cleanup();
        return false;
    }
    if (OH_CryptoSymCipherParams_Create(&params) != CRYPTO_SUCCESS) {
        cleanup();
        return false;
    }
    Crypto_DataBlob ivBlob{const_cast<uint8_t *>(nonce.data()), nonce.size()};
    Crypto_DataBlob aadBlob{const_cast<uint8_t *>(aad.data()), aad.size()};
    if (OH_CryptoSymCipherParams_SetParam(params, CRYPTO_IV_DATABLOB, &ivBlob) !=
            CRYPTO_SUCCESS ||
        OH_CryptoSymCipherParams_SetParam(params, CRYPTO_AAD_DATABLOB, &aadBlob) !=
            CRYPTO_SUCCESS) {
        cleanup();
        return false;
    }

    if (encrypt) {
        tag.assign(16, 0);
    }
    Crypto_DataBlob tagBlob{tag.data(), tag.size()};
    if (OH_CryptoSymCipherParams_SetParam(params, CRYPTO_TAG_DATABLOB, &tagBlob) !=
        CRYPTO_SUCCESS) {
        cleanup();
        return false;
    }

    if (OH_CryptoSymCipher_Create("AES256|GCM|NoPadding", &cipher) !=
        CRYPTO_SUCCESS) {
        cleanup();
        return false;
    }
    Crypto_CipherMode mode = encrypt ? CRYPTO_ENCRYPT_MODE : CRYPTO_DECRYPT_MODE;
    if (OH_CryptoSymCipher_Init(cipher, mode, keyContext, params) !=
        CRYPTO_SUCCESS) {
        cleanup();
        return false;
    }
    Crypto_DataBlob inputBlob{const_cast<uint8_t *>(input.data()), input.size()};
    if (OH_CryptoSymCipher_Update(cipher, &inputBlob, &updateOutput) !=
        CRYPTO_SUCCESS) {
        cleanup();
        return false;
    }
    if (OH_CryptoSymCipher_Final(cipher, nullptr, &finalOutput) !=
        CRYPTO_SUCCESS) {
        cleanup();
        return false;
    }
    if (encrypt) {
        if (finalOutput.data == nullptr || finalOutput.len != 16) {
            cleanup();
            return false;
        }
        tag.assign(finalOutput.data, finalOutput.data + finalOutput.len);
    }
    output.clear();
    if (updateOutput.data != nullptr && updateOutput.len > 0) {
        output.assign(updateOutput.data, updateOutput.data + updateOutput.len);
    }
    if (!encrypt && finalOutput.data != nullptr && finalOutput.len > 0) {
        output.insert(output.end(), finalOutput.data, finalOutput.data + finalOutput.len);
    }
    cleanup();
    return true;
}

SealedPayload ProtocolCore::SealCommand(const std::string &keyBase64Url,
                                        const std::string &payloadJson,
                                        const std::string &aadJson)
{
    std::vector<uint8_t> key = Base64UrlDecode(keyBase64Url);
    std::vector<uint8_t> nonce = RandomBytes(12);
    std::vector<uint8_t> plaintext(payloadJson.begin(), payloadJson.end());
    std::vector<uint8_t> aad(aadJson.begin(), aadJson.end());
    std::vector<uint8_t> ciphertext;
    std::vector<uint8_t> tag;
    if (!Crypt(true, key, nonce, aad, plaintext, ciphertext, tag)) {
        throw std::runtime_error("AES-256-GCM encryption failed");
    }
    return {
        Base64UrlEncode(nonce),
        Base64UrlEncode(ciphertext),
        Base64UrlEncode(tag),
    };
}

std::string ProtocolCore::OpenForTest(const std::string &keyBase64Url,
                                      const std::string &nonceBase64Url,
                                      const std::string &ciphertextBase64Url,
                                      const std::string &authTagBase64Url,
                                      const std::string &aadJson)
{
    std::vector<uint8_t> key = Base64UrlDecode(keyBase64Url);
    std::vector<uint8_t> nonce = Base64UrlDecode(nonceBase64Url);
    std::vector<uint8_t> ciphertext = Base64UrlDecode(ciphertextBase64Url);
    std::vector<uint8_t> tag = Base64UrlDecode(authTagBase64Url);
    std::vector<uint8_t> aad(aadJson.begin(), aadJson.end());
    std::vector<uint8_t> plaintext;
    if (!Crypt(false, key, nonce, aad, ciphertext, plaintext, tag)) {
        throw std::runtime_error("AES-256-GCM authentication failed");
    }
    return std::string(plaintext.begin(), plaintext.end());
}

std::string ProtocolCore::RedactDiagnostic(const std::string &text)
{
    std::string redacted = text;
    const std::regex sensitive(
        R"REGEX(("(?:credential|dataKey|token|nonce|ciphertext|authTag)"\s*:\s*")[^"]*("))REGEX",
        std::regex::icase);
    redacted = std::regex_replace(redacted, sensitive, "$1***$2");
    const std::regex bearer(R"(Bearer\s+[A-Za-z0-9_-]+)", std::regex::icase);
    return std::regex_replace(redacted, bearer, "Bearer ***");
}
