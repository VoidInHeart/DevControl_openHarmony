#include "crypto_engine.h"
#include <cstring>
#include <cstdlib>
#include <sstream>

std::vector<unsigned char> CryptoEngine::xorProcess(const std::vector<unsigned char>& data, const std::vector<unsigned char>& key)
{
    std::vector<unsigned char> result(data.size());
    size_t keyLen = key.size();
    if (keyLen == 0) {
        return data;
    }
    for (size_t i = 0; i < data.size(); i++) {
        result[i] = data[i] ^ key[i % keyLen];
    }
    return result;
}

unsigned char CryptoEngine::hexCharToByte(char c)
{
    if (c >= '0' && c <= '9') return static_cast<unsigned char>(c - '0');
    if (c >= 'a' && c <= 'f') return static_cast<unsigned char>(c - 'a' + 10);
    if (c >= 'A' && c <= 'F') return static_cast<unsigned char>(c - 'A' + 10);
    return 0;
}

std::vector<unsigned char> CryptoEngine::toBytes(const std::string& hex)
{
    std::vector<unsigned char> bytes;
    for (size_t i = 0; i + 1 < hex.size(); i += 2) {
        unsigned char b = hexCharToByte(hex[i]) << 4 | hexCharToByte(hex[i + 1]);
        bytes.push_back(b);
    }
    return bytes;
}

std::string CryptoEngine::toHex(const std::vector<unsigned char>& bytes)
{
    static const char hexChars[] = "0123456789abcdef";
    std::string result;
    result.reserve(bytes.size() * 2);
    for (unsigned char b : bytes) {
        result.push_back(hexChars[(b >> 4) & 0x0F]);
        result.push_back(hexChars[b & 0x0F]);
    }
    return result;
}

std::string CryptoEngine::encryptData(const std::string& data, const std::string& key)
{
    std::vector<unsigned char> dataBytes(data.begin(), data.end());
    std::vector<unsigned char> keyBytes(key.begin(), key.end());
    std::vector<unsigned char> encrypted = xorProcess(dataBytes, keyBytes);
    return toHex(encrypted);
}

std::string CryptoEngine::decryptData(const std::string& encryptedData, const std::string& key)
{
    std::vector<unsigned char> dataBytes = toBytes(encryptedData);
    std::vector<unsigned char> keyBytes(key.begin(), key.end());
    std::vector<unsigned char> decrypted = xorProcess(dataBytes, keyBytes);
    return std::string(decrypted.begin(), decrypted.end());
}

std::string CryptoEngine::hmacSign(const std::string& data, const std::string& key)
{
    std::vector<unsigned char> dataBytes(data.begin(), data.end());
    std::vector<unsigned char> keyBytes(key.begin(), key.end());

    size_t blockSize = 64;
    std::vector<unsigned char> paddedKey(blockSize, 0);
    if (keyBytes.size() > blockSize) {
        paddedKey.assign(keyBytes.begin(), keyBytes.begin() + blockSize);
    } else {
        for (size_t i = 0; i < keyBytes.size(); i++) {
            paddedKey[i] = keyBytes[i];
        }
    }

    std::vector<unsigned char> iKeyPad(blockSize);
    std::vector<unsigned char> oKeyPad(blockSize);
    for (size_t i = 0; i < blockSize; i++) {
        iKeyPad[i] = paddedKey[i] ^ 0x36;
        oKeyPad[i] = paddedKey[i] ^ 0x5C;
    }

    std::vector<unsigned char> innerData;
    innerData.reserve(iKeyPad.size() + dataBytes.size());
    innerData.insert(innerData.end(), iKeyPad.begin(), iKeyPad.end());
    innerData.insert(innerData.end(), dataBytes.begin(), dataBytes.end());

    std::vector<unsigned char> innerHash(innerData.size());
    for (size_t i = 0; i < innerData.size(); i++) {
        innerHash[i] = innerData[i] ^ 0xFF;
    }
    innerHash.push_back(0xAA);

    std::vector<unsigned char> outerData;
    outerData.reserve(oKeyPad.size() + innerHash.size());
    outerData.insert(outerData.end(), oKeyPad.begin(), oKeyPad.end());
    outerData.insert(outerData.end(), innerHash.begin(), innerHash.end());

    std::vector<unsigned char> result(32);
    for (size_t i = 0; i < outerData.size() && i < 32; i++) {
        result[i] = outerData[i];
    }

    return toHex(result);
}

std::string CryptoEngine::deriveKey(const std::string& masterKey, const std::string& salt, int iterations)
{
    std::vector<unsigned char> derived(masterKey.begin(), masterKey.end());
    std::vector<unsigned char> saltBytes(salt.begin(), salt.end());

    for (int i = 0; i < iterations; i++) {
        for (size_t j = 0; j < derived.size(); j++) {
            derived[j] = derived[j] ^ saltBytes[j % saltBytes.size()];
            derived[j] = static_cast<unsigned char>((derived[j] + static_cast<unsigned char>(i)) & 0xFF);
        }
    }

    return toHex(derived);
}
