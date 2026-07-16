#include "napi/native_api.h"
#include "protocol_core.h"

#include <sstream>
#include <string>
#include <vector>

namespace {
std::string GetString(napi_env env, napi_value value)
{
    size_t length = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &length) != napi_ok) {
        throw std::invalid_argument("string argument required");
    }
    std::vector<char> buffer(length + 1, '\0');
    size_t copied = 0;
    if (napi_get_value_string_utf8(env, value, buffer.data(), buffer.size(), &copied) !=
        napi_ok) {
        throw std::invalid_argument("failed to read string argument");
    }
    return std::string(buffer.data(), copied);
}

napi_value MakeString(napi_env env, const std::string &value)
{
    napi_value result = nullptr;
    napi_create_string_utf8(env, value.c_str(), value.size(), &result);
    return result;
}

napi_value Throw(napi_env env, const std::exception &error)
{
    napi_throw_error(env, "PROTOCOL_CORE_ERROR", error.what());
    napi_value undefined = nullptr;
    napi_get_undefined(env, &undefined);
    return undefined;
}

napi_value GenerateMessageId(napi_env env, napi_callback_info)
{
    try {
        return MakeString(env, ProtocolCore::GenerateMessageId());
    } catch (const std::exception &error) {
        return Throw(env, error);
    }
}

napi_value GenerateNonce(napi_env env, napi_callback_info)
{
    try {
        return MakeString(env, ProtocolCore::GenerateNonce());
    } catch (const std::exception &error) {
        return Throw(env, error);
    }
}

napi_value SealCommand(napi_env env, napi_callback_info info)
{
    try {
        size_t argc = 3;
        napi_value args[3] = {nullptr};
        napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
        if (argc != 3) {
            throw std::invalid_argument("sealCommand requires key, payload and AAD");
        }
        SealedPayload sealed =
            ProtocolCore::SealCommand(GetString(env, args[0]), GetString(env, args[1]),
                                      GetString(env, args[2]));
        std::ostringstream json;
        json << "{\"nonce\":\"" << sealed.nonce << "\",\"ciphertext\":\""
             << sealed.ciphertext << "\",\"authTag\":\"" << sealed.authTag << "\"}";
        return MakeString(env, json.str());
    } catch (const std::exception &error) {
        return Throw(env, error);
    }
}

napi_value OpenForTest(napi_env env, napi_callback_info info)
{
    try {
        size_t argc = 5;
        napi_value args[5] = {nullptr};
        napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
        if (argc != 5) {
            throw std::invalid_argument("openForTest requires five arguments");
        }
        return MakeString(
            env, ProtocolCore::OpenForTest(
                     GetString(env, args[0]), GetString(env, args[1]),
                     GetString(env, args[2]), GetString(env, args[3]),
                     GetString(env, args[4])));
    } catch (const std::exception &error) {
        return Throw(env, error);
    }
}

napi_value RedactDiagnostic(napi_env env, napi_callback_info info)
{
    try {
        size_t argc = 1;
        napi_value args[1] = {nullptr};
        napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
        if (argc != 1) {
            throw std::invalid_argument("redactDiagnostic requires text");
        }
        return MakeString(env, ProtocolCore::RedactDiagnostic(GetString(env, args[0])));
    } catch (const std::exception &error) {
        return Throw(env, error);
    }
}
}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor descriptors[] = {
        {"generateMessageId", nullptr, GenerateMessageId, nullptr, nullptr, nullptr,
         napi_default, nullptr},
        {"generateNonce", nullptr, GenerateNonce, nullptr, nullptr, nullptr,
         napi_default, nullptr},
        {"sealCommand", nullptr, SealCommand, nullptr, nullptr, nullptr, napi_default,
         nullptr},
        {"openForTest", nullptr, OpenForTest, nullptr, nullptr, nullptr, napi_default,
         nullptr},
        {"redactDiagnostic", nullptr, RedactDiagnostic, nullptr, nullptr, nullptr,
         napi_default, nullptr},
    };
    napi_define_properties(env, exports,
                           sizeof(descriptors) / sizeof(descriptors[0]), descriptors);
    return exports;
}
EXTERN_C_END

static napi_module module = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "entry",
    .nm_priv = nullptr,
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterEntryModule()
{
    napi_module_register(&module);
}
