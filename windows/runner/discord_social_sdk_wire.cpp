#include "discord_social_sdk_wire.h"

#include <limits>

namespace discord_social_sdk_wire {

const flutter::EncodableMap* ArgumentsOf(const flutter::MethodCall<>& call) {
  const auto* arguments = call.arguments();
  return arguments == nullptr
             ? nullptr
             : std::get_if<flutter::EncodableMap>(arguments);
}

std::optional<std::string> StringArgument(
    const flutter::MethodCall<>& call,
    const std::string& key) {
  const auto* arguments = ArgumentsOf(call);
  if (arguments == nullptr) {
    return std::nullopt;
  }
  const auto iterator = arguments->find(flutter::EncodableValue(key));
  if (iterator == arguments->end()) {
    return std::nullopt;
  }
  const auto* value = std::get_if<std::string>(&iterator->second);
  if (value == nullptr || value->empty()) {
    return std::nullopt;
  }
  return *value;
}

std::optional<uint64_t> SnowflakeArgument(
    const flutter::MethodCall<>& call,
    const std::string& key) {
  const auto value = StringArgument(call, key);
  if (!value) {
    return std::nullopt;
  }
  try {
    size_t parsed = 0;
    const auto result = std::stoull(*value, &parsed);
    if (parsed != value->size() || result == 0) {
      return std::nullopt;
    }
    return result;
  } catch (...) {
    return std::nullopt;
  }
}

std::optional<int32_t> Int32Argument(
    const flutter::MethodCall<>& call,
    const std::string& key) {
  const auto* arguments = ArgumentsOf(call);
  if (arguments == nullptr) {
    return std::nullopt;
  }
  const auto iterator = arguments->find(flutter::EncodableValue(key));
  if (iterator == arguments->end()) {
    return std::nullopt;
  }
  if (const auto* value = std::get_if<int32_t>(&iterator->second)) {
    return *value;
  }
  if (const auto* value = std::get_if<int64_t>(&iterator->second);
      value != nullptr && *value >= std::numeric_limits<int32_t>::min() &&
      *value <= std::numeric_limits<int32_t>::max()) {
    return static_cast<int32_t>(*value);
  }
  return std::nullopt;
}

void InvalidArguments(std::unique_ptr<MethodResult> result) {
  result->Error("invalid_arguments",
                "Required Social SDK arguments are invalid.");
}

}  // namespace discord_social_sdk_wire
