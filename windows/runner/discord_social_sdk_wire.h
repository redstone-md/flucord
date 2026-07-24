#ifndef RUNNER_DISCORD_SOCIAL_SDK_WIRE_H_
#define RUNNER_DISCORD_SOCIAL_SDK_WIRE_H_

#include <flutter/encodable_value.h>
#include <flutter/method_call.h>
#include <flutter/method_result.h>

#include <cstdint>
#include <memory>
#include <optional>
#include <string>

namespace discord_social_sdk_wire {

using MethodResult = flutter::MethodResult<flutter::EncodableValue>;

const flutter::EncodableMap* ArgumentsOf(const flutter::MethodCall<>& call);

std::optional<std::string> StringArgument(
    const flutter::MethodCall<>& call,
    const std::string& key);

std::optional<uint64_t> SnowflakeArgument(
    const flutter::MethodCall<>& call,
    const std::string& key);

std::optional<int32_t> Int32Argument(
    const flutter::MethodCall<>& call,
    const std::string& key);

void InvalidArguments(std::unique_ptr<MethodResult> result);

}  // namespace discord_social_sdk_wire

#endif  // RUNNER_DISCORD_SOCIAL_SDK_WIRE_H_
