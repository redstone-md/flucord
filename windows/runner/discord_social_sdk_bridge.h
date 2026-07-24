#ifndef RUNNER_DISCORD_SOCIAL_SDK_BRIDGE_H_
#define RUNNER_DISCORD_SOCIAL_SDK_BRIDGE_H_

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <memory>

namespace flutter {
class BinaryMessenger;
}

class DiscordSocialSdkBridge {
 public:
  explicit DiscordSocialSdkBridge(flutter::BinaryMessenger* messenger);
  ~DiscordSocialSdkBridge();

  DiscordSocialSdkBridge(const DiscordSocialSdkBridge&) = delete;
  DiscordSocialSdkBridge& operator=(const DiscordSocialSdkBridge&) = delete;

 private:
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // RUNNER_DISCORD_SOCIAL_SDK_BRIDGE_H_
