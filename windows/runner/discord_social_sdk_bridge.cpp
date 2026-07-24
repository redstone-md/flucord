#include "discord_social_sdk_bridge.h"

#include <flutter/standard_method_codec.h>

#include <string>

#if defined(FLUCORD_DISCORD_SOCIAL_SDK_ENABLED)
#define DISCORDPP_IMPLEMENTATION
#include <discord_partner_sdk/discordpp.h>
#endif

namespace {

flutter::EncodableValue GetAvailabilityPayload() {
#if defined(FLUCORD_DISCORD_SOCIAL_SDK_ENABLED)
  const std::string status = "ready";
#else
  const std::string status = "sdk_not_bundled";
#endif
  flutter::EncodableMap payload;
  payload[flutter::EncodableValue("status")] = flutter::EncodableValue(status);
  return flutter::EncodableValue(payload);
}

}  // namespace

DiscordSocialSdkBridge::DiscordSocialSdkBridge(
    flutter::BinaryMessenger* messenger)
    : channel_(std::make_unique<flutter::MethodChannel<>>(
          messenger, "flucord/social_sdk",
          &flutter::StandardMethodCodec::GetInstance())) {
  channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<>& call,
         std::unique_ptr<flutter::MethodResult<>> result) {
        if (call.method_name() == "getAvailability") {
          result->Success(GetAvailabilityPayload());
          return;
        }
        if (call.method_name() == "getRelationships") {
#if defined(FLUCORD_DISCORD_SOCIAL_SDK_ENABLED)
          result->Error(
              "not_authenticated",
              "The Discord Social SDK package is linked, but its native "
              "account session has not been authenticated.");
#else
          result->Error(
              "sdk_not_bundled",
              "The Discord Social SDK package is not linked into this build.");
#endif
          return;
        }
        result->NotImplemented();
      });
}

DiscordSocialSdkBridge::~DiscordSocialSdkBridge() = default;
