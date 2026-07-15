#include "protocol_parser.h"
#include <sstream>

std::map<std::string, std::string> ProtocolParser::parseKeyValueString(const std::string& str)
{
    std::map<std::string, std::string> result;
    std::istringstream stream(str);
    std::string pair;
    while (std::getline(stream, pair, ';')) {
        size_t eq = pair.find('=');
        if (eq != std::string::npos) {
            std::string key = pair.substr(0, eq);
            std::string value = pair.substr(eq + 1);
            result[key] = unescapeValue(value);
        }
    }
    return result;
}

std::string ProtocolParser::escapeValue(const std::string& value)
{
    std::string result;
    for (char c : value) {
        if (c == ';' || c == '=' || c == '\\') {
            result.push_back('\\');
        }
        result.push_back(c);
    }
    return result;
}

std::string ProtocolParser::unescapeValue(const std::string& value)
{
    std::string result;
    bool escaped = false;
    for (char c : value) {
        if (escaped) {
            result.push_back(c);
            escaped = false;
        } else if (c == '\\') {
            escaped = true;
        } else {
            result.push_back(c);
        }
    }
    return result;
}

DeviceCommand ProtocolParser::parseCommand(const std::string& raw)
{
    DeviceCommand cmd;
    auto kv = parseKeyValueString(raw);
    cmd.deviceId = kv.count("deviceId") ? kv["deviceId"] : "";
    cmd.action = kv.count("action") ? kv["action"] : "";
    cmd.param = kv.count("param") ? kv["param"] : "";
    cmd.signature = kv.count("signature") ? kv["signature"] : "";
    return cmd;
}

std::string ProtocolParser::serializeCommand(const DeviceCommand& cmd)
{
    std::string result;
    result = "deviceId=" + escapeValue(cmd.deviceId) +
             ";action=" + escapeValue(cmd.action) +
             ";param=" + escapeValue(cmd.param);
    if (!cmd.signature.empty()) {
        result += ";signature=" + escapeValue(cmd.signature);
    }
    return result;
}

std::string ProtocolParser::buildCommand(const std::string& deviceId, const std::string& action, const std::string& param)
{
    DeviceCommand cmd;
    cmd.deviceId = deviceId;
    cmd.action = action;
    cmd.param = param;
    cmd.signature = "";
    return serializeCommand(cmd);
}
