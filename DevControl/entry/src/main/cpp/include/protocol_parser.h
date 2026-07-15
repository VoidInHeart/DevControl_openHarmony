#ifndef PROTOCOL_PARSER_H
#define PROTOCOL_PARSER_H

#include <string>
#include <map>

struct DeviceCommand {
    std::string deviceId;
    std::string action;
    std::string param;
    std::string signature;
};

class ProtocolParser {
public:
    static DeviceCommand parseCommand(const std::string& raw);
    static std::string serializeCommand(const DeviceCommand& cmd);
    static std::string buildCommand(const std::string& deviceId, const std::string& action, const std::string& param);

private:
    static std::map<std::string, std::string> parseKeyValueString(const std::string& str);
    static std::string escapeValue(const std::string& value);
    static std::string unescapeValue(const std::string& value);
};

#endif
