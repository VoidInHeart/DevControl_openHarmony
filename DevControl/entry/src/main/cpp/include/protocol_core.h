#ifndef DEVCONTROL_PROTOCOL_CORE_H
#define DEVCONTROL_PROTOCOL_CORE_H

#include <cstdint>
#include <string>
#include <vector>

class ProtocolCore {
public:
    static std::string CreateMessageId();
    static std::string CreateNonce();
    static std::string BuildCommandEnvelope(const std::string& deviceId,
                                            const std::string& action,
                                            const std::string& payloadJson,
                                            int64_t expectedStateVersion,
                                            int64_t timestampMs);
    static std::string BuildSecureCommandEnvelope(const std::string& deviceId,
                                                  const std::string& action,
                                                  const std::string& payloadJson,
                                                  const std::string& base64Key,
                                                  int64_t expectedStateVersion,
                                                  int64_t timestampMs);
    static std::string ValidateGatewayMessage(const std::string& raw,
                                              int64_t nowMs,
                                              int64_t maxClockSkewMs);
    static std::string RedactDiagnostic(const std::string& raw);

private:
    static std::string SecureRandomHex(std::size_t byteCount);
    static std::string EscapeJson(const std::string& value);
    static std::string Base64Encode(const std::vector<uint8_t>& value);
    static bool Base64Decode(const std::string& value, std::vector<uint8_t>& output);
    static bool HexDecode(const std::string& value, std::vector<uint8_t>& output);
};

#endif
