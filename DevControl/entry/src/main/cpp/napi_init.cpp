#include "napi/native_api.h"
#include "device_simulator.h"
#include "crypto_engine.h"
#include "protocol_parser.h"
#include "tls_client.h"
#include <string>
#include <sstream>
#include <vector>

static TLSClient g_tlsClient;

static std::string getStringArgument(napi_env env, napi_value value)
{
    size_t length = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &length) != napi_ok) {
        return "";
    }
    std::vector<char> buffer(length + 1, '\0');
    size_t copied = 0;
    if (napi_get_value_string_utf8(env, value, buffer.data(), buffer.size(), &copied) != napi_ok) {
        return "";
    }
    return std::string(buffer.data(), copied);
}

static std::string deviceStateToJson(const DeviceState& state) {
    std::ostringstream oss;
    oss << "{\"online\":" << (state.online ? "true" : "false")
        << ",\"isLocked\":" << (state.isLocked ? "true" : "false")
        << ",\"isOn\":" << (state.isOn ? "true" : "false")
        << ",\"brightness\":" << state.brightness
        << ",\"temperature\":" << state.temperature
        << ",\"humidity\":" << state.humidity
        << ",\"acPower\":" << (state.acPower ? "true" : "false")
        << ",\"acMode\":" << state.acMode
        << ",\"targetTemp\":" << state.targetTemp
        << ",\"targetHumidity\":" << state.targetHumidity
        << ",\"batteryLevel\":" << state.batteryLevel
        << "}";
    return oss.str();
}

static std::string deviceInfoToJson(const DeviceInfo& dev) {
    std::ostringstream oss;
    oss << "{\"id\":\"" << dev.id << "\""
        << ",\"name\":\"" << dev.name << "\""
        << ",\"type\":" << static_cast<int>(dev.type)
        << ",\"brand\":\"" << dev.brand << "\""
        << ",\"state\":" << deviceStateToJson(dev.state)
        << "}";
    return oss.str();
}

static napi_value SimulateDevice(napi_env env, napi_callback_info info)
{
    size_t argc = 3;
    napi_value args[3] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    std::string deviceId = getStringArgument(env, args[0]);
    std::string command = getStringArgument(env, args[1]);
    std::string param = getStringArgument(env, args[2]);

    std::string result = DeviceSimulator::getInstance().simulateCommand(deviceId, command, param);

    napi_value ret;
    napi_create_string_utf8(env, result.c_str(), result.size(), &ret);
    return ret;
}

static napi_value ListDevicesAsJson(napi_env env, napi_callback_info info)
{
    std::vector<DeviceInfo> devices = DeviceSimulator::getInstance().listDevices();
    std::ostringstream oss;
    oss << "[";
    for (size_t i = 0; i < devices.size(); i++) {
        if (i > 0) oss << ",";
        oss << deviceInfoToJson(devices[i]);
    }
    oss << "]";

    std::string result = oss.str();
    napi_value ret;
    napi_create_string_utf8(env, result.c_str(), result.size(), &ret);
    return ret;
}

static napi_value GetDeviceStateAsJson(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    std::string deviceId = getStringArgument(env, args[0]);

    DeviceState state = DeviceSimulator::getInstance().getDeviceState(deviceId);
    std::string result = deviceStateToJson(state);

    napi_value ret;
    napi_create_string_utf8(env, result.c_str(), result.size(), &ret);
    return ret;
}

static napi_value EncryptData(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    std::string data = getStringArgument(env, args[0]);
    std::string key = getStringArgument(env, args[1]);

    std::string result = CryptoEngine::encryptData(data, key);

    napi_value ret;
    napi_create_string_utf8(env, result.c_str(), result.size(), &ret);
    return ret;
}

static napi_value DecryptData(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    std::string data = getStringArgument(env, args[0]);
    std::string key = getStringArgument(env, args[1]);

    std::string result = CryptoEngine::decryptData(data, key);

    napi_value ret;
    napi_create_string_utf8(env, result.c_str(), result.size(), &ret);
    return ret;
}

static napi_value HmacSign(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    std::string data = getStringArgument(env, args[0]);
    std::string key = getStringArgument(env, args[1]);

    std::string result = CryptoEngine::hmacSign(data, key);

    napi_value ret;
    napi_create_string_utf8(env, result.c_str(), result.size(), &ret);
    return ret;
}

static napi_value ParseDeviceCommand(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    std::string raw = getStringArgument(env, args[0]);

    DeviceCommand cmd = ProtocolParser::parseCommand(raw);
    std::ostringstream oss;
    oss << "{\"deviceId\":\"" << cmd.deviceId << "\""
        << ",\"action\":\"" << cmd.action << "\""
        << ",\"param\":\"" << cmd.param << "\""
        << ",\"signature\":\"" << cmd.signature << "\"}";
    std::string result = oss.str();

    napi_value ret;
    napi_create_string_utf8(env, result.c_str(), result.size(), &ret);
    return ret;
}

static napi_value BuildCommand(napi_env env, napi_callback_info info)
{
    size_t argc = 3;
    napi_value args[3] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    std::string deviceId = getStringArgument(env, args[0]);
    std::string action = getStringArgument(env, args[1]);
    std::string param = getStringArgument(env, args[2]);

    std::string result = ProtocolParser::buildCommand(deviceId, action, param);

    napi_value ret;
    napi_create_string_utf8(env, result.c_str(), result.size(), &ret);
    return ret;
}

static napi_value TlsConnect(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    std::string host = getStringArgument(env, args[0]);

    int32_t port = 0;
    napi_get_value_int32(env, args[1], &port);

    TLSConfig config;
    config.host = host;
    config.port = port;

    bool success = g_tlsClient.connect(config);

    napi_value ret;
    napi_get_boolean(env, success, &ret);
    return ret;
}

static napi_value TlsSend(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    std::string data = getStringArgument(env, args[0]);

    std::string result = g_tlsClient.send(data);

    napi_value ret;
    napi_create_string_utf8(env, result.c_str(), result.size(), &ret);
    return ret;
}

static napi_value TlsClose(napi_env env, napi_callback_info info)
{
    g_tlsClient.close();

    napi_value ret;
    napi_get_undefined(env, &ret);
    return ret;
}

static napi_value Tick(napi_env env, napi_callback_info info)
{
    DeviceSimulator::getInstance().tick();

    napi_value ret;
    napi_get_undefined(env, &ret);
    return ret;
}

static napi_value InitDevices(napi_env env, napi_callback_info info)
{
    DeviceSimulator::getInstance().initDefaultDevices();

    napi_value ret;
    napi_get_boolean(env, true, &ret);
    return ret;
}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        {"simulateDevice", nullptr, SimulateDevice, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"listDevicesAsJson", nullptr, ListDevicesAsJson, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getDeviceStateAsJson", nullptr, GetDeviceStateAsJson, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"encryptData", nullptr, EncryptData, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"decryptData", nullptr, DecryptData, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"hmacSign", nullptr, HmacSign, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"parseDeviceCommand", nullptr, ParseDeviceCommand, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"buildCommand", nullptr, BuildCommand, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"tlsConnect", nullptr, TlsConnect, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"tlsSend", nullptr, TlsSend, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"tlsClose", nullptr, TlsClose, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"tick", nullptr, Tick, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"initDevices", nullptr, InitDevices, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module demoModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "entry",
    .nm_priv = ((void*)0),
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterEntryModule(void)
{
    napi_module_register(&demoModule);
}
