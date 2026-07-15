#ifndef CRYPTO_ENGINE_H
#define CRYPTO_ENGINE_H

#include <string>
#include <vector>

class CryptoEngine {
public:
    static std::string encryptData(const std::string& data, const std::string& key);
    static std::string decryptData(const std::string& encryptedData, const std::string& key);
    static std::string hmacSign(const std::string& data, const std::string& key);
    static std::string deriveKey(const std::string& masterKey, const std::string& salt, int iterations);

private:
    static std::vector<unsigned char> xorProcess(const std::vector<unsigned char>& data, const std::vector<unsigned char>& key);
    static std::vector<unsigned char> toBytes(const std::string& hex);
    static std::string toHex(const std::vector<unsigned char>& bytes);
    static unsigned char hexCharToByte(char c);
};

#endif
