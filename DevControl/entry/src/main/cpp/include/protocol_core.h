#ifndef DEVCONTROL_PROTOCOL_CORE_H
#define DEVCONTROL_PROTOCOL_CORE_H

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

struct SealedPayload {
    std::string nonce;
    std::string ciphertext;
    std::string authTag;
};

class ProtocolCore {
public:
    static std::string GenerateMessageId();
    static std::string GenerateNonce();
    static SealedPayload SealCommand(const std::string &keyBase64Url,
                                     const std::string &payloadJson,
                                     const std::string &aadJson);
    static std::string OpenForTest(const std::string &keyBase64Url,
                                   const std::string &nonceBase64Url,
                                   const std::string &ciphertextBase64Url,
                                   const std::string &authTagBase64Url,
                                   const std::string &aadJson);
    static std::string RedactDiagnostic(const std::string &text);

private:
    static std::vector<uint8_t> RandomBytes(size_t length);
    static std::string Base64UrlEncode(const std::vector<uint8_t> &bytes);
    static std::vector<uint8_t> Base64UrlDecode(const std::string &value);
    static bool Crypt(bool encrypt, const std::vector<uint8_t> &key,
                      const std::vector<uint8_t> &nonce,
                      const std::vector<uint8_t> &aad,
                      const std::vector<uint8_t> &input,
                      std::vector<uint8_t> &output,
                      std::vector<uint8_t> &tag);
};

#endif

