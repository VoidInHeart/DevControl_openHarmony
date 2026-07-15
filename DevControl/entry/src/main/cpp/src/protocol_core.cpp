#include "protocol_core.h"

#include <CryptoArchitectureKit/crypto_common.h>
#include <CryptoArchitectureKit/crypto_rand.h>
#include <CryptoArchitectureKit/crypto_sym_cipher.h>
#include <CryptoArchitectureKit/crypto_sym_key.h>

#include <algorithm>
#include <array>
#include <cctype>
#include <cstdlib>
#include <sstream>
#include <vector>

namespace {
constexpr const char* PROTOCOL_VERSION = "1.0";
constexpr std::size_t AES_256_KEY_BYTES = 32;
constexpr std::size_t GCM_NONCE_BYTES = 12;
constexpr std::size_t GCM_TAG_BYTES = 16;

bool HasStringField(const std::string& raw, const std::string& field)
{
    return raw.find("\"" + field + "\":\"") != std::string::npos ||
        raw.find("\"" + field + "\": \"") != std::string::npos;
}

bool ExtractInt64(const std::string& raw, const std::string& field, int64_t& value)
{
    const std::string marker = "\"" + field + "\"";
    std::size_t position = raw.find(marker);
    if (position == std::string::npos) {
        return false;
    }
    position = raw.find(':', position + marker.size());
    if (position == std::string::npos) {
        return false;
    }
    ++position;
    while (position < raw.size() && std::isspace(static_cast<unsigned char>(raw[position]))) {
        ++position;
    }
    std::size_t end = position;
    if (end < raw.size() && raw[end] == '-') {
        ++end;
    }
    while (end < raw.size() && std::isdigit(static_cast<unsigned char>(raw[end]))) {
        ++end;
    }
    if (end == position || (end == position + 1 && raw[position] == '-')) {
        return false;
    }
    char* parseEnd = nullptr;
    value = std::strtoll(raw.substr(position, end - position).c_str(), &parseEnd, 10);
    return parseEnd != nullptr && *parseEnd == '\0';
}

void RedactJsonString(std::string& value, const std::string& field)
{
    const std::string marker = "\"" + field + "\"";
    std::size_t searchFrom = 0;
    while (true) {
        std::size_t fieldPosition = value.find(marker, searchFrom);
        if (fieldPosition == std::string::npos) {
            return;
        }
        std::size_t colon = value.find(':', fieldPosition + marker.size());
        std::size_t quote = colon == std::string::npos ? std::string::npos : value.find('"', colon + 1);
        if (quote == std::string::npos) {
            return;
        }
        std::size_t endQuote = quote + 1;
        bool escaped = false;
        while (endQuote < value.size()) {
            const char current = value[endQuote];
            if (current == '"' && !escaped) {
                break;
            }
            escaped = current == '\\' && !escaped;
            if (current != '\\') {
                escaped = false;
            }
            ++endQuote;
        }
        if (endQuote >= value.size()) {
            return;
        }
        value.replace(quote + 1, endQuote - quote - 1, "***");
        searchFrom = quote + 4;
    }
}

bool EncryptAes256Gcm(const std::vector<uint8_t>& key,
                      const std::vector<uint8_t>& nonce,
                      const std::string& aad,
                      const std::string& plaintext,
                      std::vector<uint8_t>& ciphertext,
                      std::vector<uint8_t>& authTag)
{
    if (key.size() != AES_256_KEY_BYTES || nonce.size() != GCM_NONCE_BYTES) {
        return false;
    }

    OH_CryptoSymKeyGenerator* generator = nullptr;
    OH_CryptoSymKey* keyContext = nullptr;
    OH_CryptoSymCipherParams* parameters = nullptr;
    OH_CryptoSymCipher* cipher = nullptr;
    Crypto_DataBlob encrypted = {nullptr, 0};
    Crypto_DataBlob tag = {nullptr, 0};
    std::array<uint8_t, GCM_TAG_BYTES> initialTag = {};

    Crypto_DataBlob keyBlob = {const_cast<uint8_t*>(key.data()), key.size()};
    Crypto_DataBlob nonceBlob = {const_cast<uint8_t*>(nonce.data()), nonce.size()};
    Crypto_DataBlob aadBlob = {
        reinterpret_cast<uint8_t*>(const_cast<char*>(aad.data())), aad.size()
    };
    Crypto_DataBlob tagBlob = {initialTag.data(), initialTag.size()};
    Crypto_DataBlob plaintextBlob = {
        reinterpret_cast<uint8_t*>(const_cast<char*>(plaintext.data())), plaintext.size()
    };

    OH_Crypto_ErrCode result = OH_CryptoSymKeyGenerator_Create("AES256", &generator);
    if (result == CRYPTO_SUCCESS) {
        result = OH_CryptoSymKeyGenerator_Convert(generator, &keyBlob, &keyContext);
    }
    if (result == CRYPTO_SUCCESS) {
        result = OH_CryptoSymCipherParams_Create(&parameters);
    }
    if (result == CRYPTO_SUCCESS) {
        result = OH_CryptoSymCipherParams_SetParam(parameters, CRYPTO_IV_DATABLOB, &nonceBlob);
    }
    if (result == CRYPTO_SUCCESS) {
        result = OH_CryptoSymCipherParams_SetParam(parameters, CRYPTO_AAD_DATABLOB, &aadBlob);
    }
    if (result == CRYPTO_SUCCESS) {
        result = OH_CryptoSymCipherParams_SetParam(parameters, CRYPTO_TAG_DATABLOB, &tagBlob);
    }
    if (result == CRYPTO_SUCCESS) {
        result = OH_CryptoSymCipher_Create("AES256|GCM|NoPadding", &cipher);
    }
    if (result == CRYPTO_SUCCESS) {
        result = OH_CryptoSymCipher_Init(cipher, CRYPTO_ENCRYPT_MODE, keyContext, parameters);
    }
    if (result == CRYPTO_SUCCESS) {
        result = OH_CryptoSymCipher_Update(cipher, &plaintextBlob, &encrypted);
    }
    if (result == CRYPTO_SUCCESS) {
        result = OH_CryptoSymCipher_Final(cipher, nullptr, &tag);
    }
    if (result == CRYPTO_SUCCESS && encrypted.data != nullptr && tag.data != nullptr && tag.len == GCM_TAG_BYTES) {
        ciphertext.assign(encrypted.data, encrypted.data + encrypted.len);
        authTag.assign(tag.data, tag.data + tag.len);
    } else {
        result = CRYPTO_OPERTION_ERROR;
    }

    OH_Crypto_FreeDataBlob(&encrypted);
    OH_Crypto_FreeDataBlob(&tag);
    OH_CryptoSymCipher_Destroy(cipher);
    OH_CryptoSymCipherParams_Destroy(parameters);
    OH_CryptoSymKey_Destroy(keyContext);
    OH_CryptoSymKeyGenerator_Destroy(generator);
    return result == CRYPTO_SUCCESS;
}
}

std::string ProtocolCore::SecureRandomHex(std::size_t byteCount)
{
    OH_CryptoRand* random = nullptr;
    if (OH_CryptoRand_Create(&random) != CRYPTO_SUCCESS || random == nullptr) {
        return "";
    }

    Crypto_DataBlob randomBytes = {nullptr, 0};
    const OH_Crypto_ErrCode result = OH_CryptoRand_GenerateRandom(random,
        static_cast<int>(byteCount), &randomBytes);
    OH_CryptoRand_Destroy(random);
    if (result != CRYPTO_SUCCESS || randomBytes.data == nullptr || randomBytes.len != byteCount) {
        OH_Crypto_FreeDataBlob(&randomBytes);
        return "";
    }

    static constexpr std::array<char, 16> HEX = {
        '0', '1', '2', '3', '4', '5', '6', '7',
        '8', '9', 'a', 'b', 'c', 'd', 'e', 'f'
    };
    std::string encoded;
    encoded.reserve(randomBytes.len * 2);
    for (std::size_t index = 0; index < randomBytes.len; ++index) {
        const uint8_t byte = randomBytes.data[index];
        encoded.push_back(HEX[(byte >> 4U) & 0x0FU]);
        encoded.push_back(HEX[byte & 0x0FU]);
    }
    OH_Crypto_FreeDataBlob(&randomBytes);
    return encoded;
}

std::string ProtocolCore::CreateMessageId()
{
    return SecureRandomHex(16);
}

std::string ProtocolCore::CreateNonce()
{
    return SecureRandomHex(12);
}

std::string ProtocolCore::EscapeJson(const std::string& value)
{
    std::ostringstream escaped;
    for (const unsigned char character : value) {
        switch (character) {
            case '"': escaped << "\\\""; break;
            case '\\': escaped << "\\\\"; break;
            case '\b': escaped << "\\b"; break;
            case '\f': escaped << "\\f"; break;
            case '\n': escaped << "\\n"; break;
            case '\r': escaped << "\\r"; break;
            case '\t': escaped << "\\t"; break;
            default:
                if (character < 0x20U) {
                    static constexpr char HEX[] = "0123456789abcdef";
                    escaped << "\\u00" << HEX[(character >> 4U) & 0x0FU] << HEX[character & 0x0FU];
                } else {
                    escaped << static_cast<char>(character);
                }
        }
    }
    return escaped.str();
}

std::string ProtocolCore::BuildCommandEnvelope(const std::string& deviceId,
                                               const std::string& action,
                                               const std::string& payloadJson,
                                               int64_t expectedStateVersion,
                                               int64_t timestampMs)
{
    const std::string messageId = CreateMessageId();
    const std::string nonce = CreateNonce();
    if (messageId.empty() || nonce.empty()) {
        return "";
    }
    const bool isObjectPayload = payloadJson.size() >= 2 && payloadJson.front() == '{' && payloadJson.back() == '}';
    const std::string safePayload = isObjectPayload ? payloadJson : "{}";

    std::ostringstream envelope;
    envelope << "{\"protocolVersion\":\"" << PROTOCOL_VERSION
             << "\",\"messageId\":\"" << messageId
             << "\",\"deviceId\":\"" << EscapeJson(deviceId)
             << "\",\"timestamp\":" << timestampMs
             << ",\"nonce\":\"" << nonce
             << "\",\"type\":\"command.request\""
             << ",\"action\":\"" << EscapeJson(action) << "\""
             << ",\"payload\":" << safePayload;
    if (expectedStateVersion >= 0) {
        envelope << ",\"expectedStateVersion\":" << expectedStateVersion;
    }
    envelope << '}';
    return envelope.str();
}

std::string ProtocolCore::BuildSecureCommandEnvelope(const std::string& deviceId,
                                                     const std::string& action,
                                                     const std::string& payloadJson,
                                                     const std::string& base64Key,
                                                     int64_t expectedStateVersion,
                                                     int64_t timestampMs)
{
    const std::string messageId = CreateMessageId();
    const std::string nonceHex = CreateNonce();
    const bool isObjectPayload = payloadJson.size() >= 2 && payloadJson.front() == '{' && payloadJson.back() == '}';
    if (messageId.empty() || nonceHex.empty() || !isObjectPayload) {
        return "";
    }

    std::vector<uint8_t> key;
    std::vector<uint8_t> nonce;
    if (!Base64Decode(base64Key, key) || !HexDecode(nonceHex, nonce)) {
        return "";
    }
    const std::string expectedVersionText = std::to_string(expectedStateVersion);
    const std::string aad = std::string(PROTOCOL_VERSION) + '|' + messageId + '|' + deviceId + '|' +
        std::to_string(timestampMs) + "|command.request|" + action + '|' + expectedVersionText;
    std::vector<uint8_t> ciphertext;
    std::vector<uint8_t> authTag;
    if (!EncryptAes256Gcm(key, nonce, aad, payloadJson, ciphertext, authTag)) {
        std::fill(key.begin(), key.end(), 0U);
        return "";
    }
    std::fill(key.begin(), key.end(), 0U);

    std::ostringstream envelope;
    envelope << "{\"protocolVersion\":\"" << PROTOCOL_VERSION
             << "\",\"messageId\":\"" << messageId
             << "\",\"deviceId\":\"" << EscapeJson(deviceId)
             << "\",\"timestamp\":" << timestampMs
             << ",\"nonce\":\"" << nonceHex
             << "\",\"type\":\"command.request\""
             << ",\"action\":\"" << EscapeJson(action) << "\""
             << ",\"expectedStateVersion\":" << expectedStateVersion
             << ",\"securePayload\":{\"algorithm\":\"AES-256-GCM\""
             << ",\"ciphertext\":\"" << Base64Encode(ciphertext)
             << "\",\"authTag\":\"" << Base64Encode(authTag) << "\"}}";
    return envelope.str();
}

std::string ProtocolCore::Base64Encode(const std::vector<uint8_t>& value)
{
    static constexpr char ALPHABET[] =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    std::string output;
    output.reserve(((value.size() + 2U) / 3U) * 4U);
    for (std::size_t index = 0; index < value.size(); index += 3U) {
        const uint32_t first = value[index];
        const uint32_t second = index + 1U < value.size() ? value[index + 1U] : 0U;
        const uint32_t third = index + 2U < value.size() ? value[index + 2U] : 0U;
        const uint32_t combined = (first << 16U) | (second << 8U) | third;
        output.push_back(ALPHABET[(combined >> 18U) & 0x3FU]);
        output.push_back(ALPHABET[(combined >> 12U) & 0x3FU]);
        output.push_back(index + 1U < value.size() ? ALPHABET[(combined >> 6U) & 0x3FU] : '=');
        output.push_back(index + 2U < value.size() ? ALPHABET[combined & 0x3FU] : '=');
    }
    return output;
}

bool ProtocolCore::Base64Decode(const std::string& value, std::vector<uint8_t>& output)
{
    if (value.empty() || value.size() % 4U != 0U) {
        return false;
    }
    std::array<int16_t, 256> reverse = {};
    reverse.fill(-1);
    const std::string alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    for (std::size_t index = 0; index < alphabet.size(); ++index) {
        reverse[static_cast<uint8_t>(alphabet[index])] = static_cast<int16_t>(index);
    }
    output.clear();
    output.reserve((value.size() / 4U) * 3U);
    for (std::size_t index = 0; index < value.size(); index += 4U) {
        uint32_t combined = 0U;
        int padding = 0;
        for (std::size_t offset = 0; offset < 4U; ++offset) {
            const unsigned char character = static_cast<unsigned char>(value[index + offset]);
            if (character == '=') {
                ++padding;
                combined <<= 6U;
            } else {
                const int16_t decoded = reverse[character];
                if (decoded < 0 || padding > 0) {
                    return false;
                }
                combined = (combined << 6U) | static_cast<uint32_t>(decoded);
            }
        }
        output.push_back(static_cast<uint8_t>((combined >> 16U) & 0xFFU));
        if (padding < 2) {
            output.push_back(static_cast<uint8_t>((combined >> 8U) & 0xFFU));
        }
        if (padding < 1) {
            output.push_back(static_cast<uint8_t>(combined & 0xFFU));
        }
    }
    return true;
}

bool ProtocolCore::HexDecode(const std::string& value, std::vector<uint8_t>& output)
{
    if (value.size() % 2U != 0U) {
        return false;
    }
    output.clear();
    output.reserve(value.size() / 2U);
    auto decode = [](const char character) -> int {
        if (character >= '0' && character <= '9') return character - '0';
        if (character >= 'a' && character <= 'f') return character - 'a' + 10;
        if (character >= 'A' && character <= 'F') return character - 'A' + 10;
        return -1;
    };
    for (std::size_t index = 0; index < value.size(); index += 2U) {
        const int high = decode(value[index]);
        const int low = decode(value[index + 1U]);
        if (high < 0 || low < 0) {
            return false;
        }
        output.push_back(static_cast<uint8_t>((high << 4) | low));
    }
    return true;
}

std::string ProtocolCore::ValidateGatewayMessage(const std::string& raw,
                                                 int64_t nowMs,
                                                 int64_t maxClockSkewMs)
{
    if (raw.size() < 2 || raw.front() != '{' || raw.back() != '}') {
        return "INVALID_JSON_OBJECT";
    }
    if (raw.find("\"protocolVersion\":\"1.0\"") == std::string::npos &&
        raw.find("\"protocolVersion\": \"1.0\"") == std::string::npos) {
        return "UNSUPPORTED_PROTOCOL";
    }
    if (!HasStringField(raw, "messageId") || !HasStringField(raw, "type")) {
        return "MISSING_HEADER";
    }
    int64_t timestamp = 0;
    if (!ExtractInt64(raw, "timestamp", timestamp)) {
        return "INVALID_TIMESTAMP";
    }
    const int64_t difference = timestamp > nowMs ? timestamp - nowMs : nowMs - timestamp;
    if (maxClockSkewMs >= 0 && difference > maxClockSkewMs) {
        return "STALE_MESSAGE";
    }
    return "";
}

std::string ProtocolCore::RedactDiagnostic(const std::string& raw)
{
    std::string redacted = raw;
    const std::array<std::string, 6> sensitiveFields = {
        "credential", "token", "dataKey", "ciphertext", "authTag", "nonce"
    };
    for (const std::string& field : sensitiveFields) {
        RedactJsonString(redacted, field);
    }
    return redacted;
}
