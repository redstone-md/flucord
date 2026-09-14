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

  void PumpCallbacks();

 private:
  class Impl;

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::unique_ptr<Impl> impl_;
};

#endif  // RUNNER_DISCORD_SOCIAL_SDK_BRIDGE_H_
