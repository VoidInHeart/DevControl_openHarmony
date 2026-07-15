#include "napi/native_api.h"
#include "protocol_core.h"

#include <chrono>
#include <cstdint>
#include <string>
#include <vector>

namespace {
bool ReadString(napi_env env, napi_value value, std::string& result)
{
    size_t length = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &length) != napi_ok) {
        return false;
    }
    std::vector<char> buffer(length + 1, '\0');
    size_t copied = 0;
    if (napi_get_value_string_utf8(env, value, buffer.data(), buffer.size(), &copied) != napi_ok) {
        return false;
    }
    result.assign(buffer.data(), copied);
    return true;
}

napi_value StringResult(napi_env env, const std::string& value)
{
    napi_value result = nullptr;
    napi_create_string_utf8(env, value.c_str(), value.size(), &result);
    return result;
}

napi_value ThrowTypeError(napi_env env, const char* message)
{
    napi_throw_type_error(env, nullptr, message);
    return nullptr;
}

napi_value CreateMessageId(napi_env env, napi_callback_info)
{
    const std::string value = ProtocolCore::CreateMessageId();
    if (value.empty()) {
        napi_throw_error(env, nullptr, "Secure random generation failed");
        return nullptr;
    }
    return StringResult(env, value);
}

napi_value CreateNonce(napi_env env, napi_callback_info)
{
    const std::string value = ProtocolCore::CreateNonce();
    if (value.empty()) {
        napi_throw_error(env, nullptr, "Secure random generation failed");
        return nullptr;
    }
    return StringResult(env, value);
}

napi_value BuildCommandEnvelope(napi_env env, napi_callback_info info)
{
    size_t argc = 4;
    napi_value args[4] = {nullptr, nullptr, nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc != 4) {
        return ThrowTypeError(env, "Expected deviceId, action, payloadJson and expectedStateVersion");
    }

    std::string deviceId;
    std::string action;
    std::string payloadJson;
    int64_t expectedStateVersion = -1;
    if (!ReadString(env, args[0], deviceId) || !ReadString(env, args[1], action) ||
        !ReadString(env, args[2], payloadJson) ||
        napi_get_value_int64(env, args[3], &expectedStateVersion) != napi_ok) {
        return ThrowTypeError(env, "Invalid command envelope arguments");
    }

    const int64_t timestampMs = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::system_clock::now().time_since_epoch()).count();
    const std::string envelope = ProtocolCore::BuildCommandEnvelope(
        deviceId, action, payloadJson, expectedStateVersion, timestampMs);
    if (envelope.empty()) {
        napi_throw_error(env, nullptr, "Unable to build command envelope");
        return nullptr;
    }
    return StringResult(env, envelope);
}

napi_value BuildSecureCommandEnvelope(napi_env env, napi_callback_info info)
{
    size_t argc = 5;
    napi_value args[5] = {nullptr, nullptr, nullptr, nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc != 5) {
        return ThrowTypeError(env, "Expected deviceId, action, payloadJson, base64Key and expectedStateVersion");
    }

    std::string deviceId;
    std::string action;
    std::string payloadJson;
    std::string base64Key;
    int64_t expectedStateVersion = -1;
    if (!ReadString(env, args[0], deviceId) || !ReadString(env, args[1], action) ||
        !ReadString(env, args[2], payloadJson) || !ReadString(env, args[3], base64Key) ||
        napi_get_value_int64(env, args[4], &expectedStateVersion) != napi_ok) {
        return ThrowTypeError(env, "Invalid secure command envelope arguments");
    }
    const int64_t timestampMs = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::system_clock::now().time_since_epoch()).count();
    const std::string envelope = ProtocolCore::BuildSecureCommandEnvelope(
        deviceId, action, payloadJson, base64Key, expectedStateVersion, timestampMs);
    std::fill(base64Key.begin(), base64Key.end(), '\0');
    if (envelope.empty()) {
        napi_throw_error(env, nullptr, "Unable to encrypt secure command envelope");
        return nullptr;
    }
    return StringResult(env, envelope);
}

napi_value ValidateGatewayMessage(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc != 2) {
        return ThrowTypeError(env, "Expected raw message and maximum clock skew");
    }

    std::string raw;
    int64_t maxClockSkewMs = 0;
    if (!ReadString(env, args[0], raw) || napi_get_value_int64(env, args[1], &maxClockSkewMs) != napi_ok) {
        return ThrowTypeError(env, "Invalid gateway message arguments");
    }
    const int64_t nowMs = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::system_clock::now().time_since_epoch()).count();
    return StringResult(env, ProtocolCore::ValidateGatewayMessage(raw, nowMs, maxClockSkewMs));
}

napi_value RedactDiagnostic(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    std::string raw;
    if (argc != 1 || !ReadString(env, args[0], raw)) {
        return ThrowTypeError(env, "Expected a diagnostic string");
    }
    return StringResult(env, ProtocolCore::RedactDiagnostic(raw));
}
}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor descriptors[] = {
        {"createMessageId", nullptr, CreateMessageId, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"createNonce", nullptr, CreateNonce, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"buildCommandEnvelope", nullptr, BuildCommandEnvelope, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"buildSecureCommandEnvelope", nullptr, BuildSecureCommandEnvelope, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"validateGatewayMessage", nullptr, ValidateGatewayMessage, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"redactDiagnostic", nullptr, RedactDiagnostic, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(descriptors) / sizeof(descriptors[0]), descriptors);
    return exports;
}
EXTERN_C_END

static napi_module devControlModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "entry",
    .nm_priv = nullptr,
    .reserved = {nullptr},
};

extern "C" __attribute__((constructor)) void RegisterEntryModule()
{
    napi_module_register(&devControlModule);
}
