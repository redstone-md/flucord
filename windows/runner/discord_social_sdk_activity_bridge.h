#ifndef RUNNER_DISCORD_SOCIAL_SDK_ACTIVITY_BRIDGE_H_
#define RUNNER_DISCORD_SOCIAL_SDK_ACTIVITY_BRIDGE_H_

#include <flutter/encodable_value.h>
#include <flutter/method_call.h>
#include <flutter/method_channel.h>
#include <flutter/method_result.h>

#include <memory>
#include <string>

namespace discordpp {
class Client;
}

class DiscordSocialSdkActivityBridge {
 public:
  DiscordSocialSdkActivityBridge(
      discordpp::Client* client,
      flutter::MethodChannel<flutter::EncodableValue>* channel);
  ~DiscordSocialSdkActivityBridge();

  DiscordSocialSdkActivityBridge(const DiscordSocialSdkActivityBridge&) =
      delete;
  DiscordSocialSdkActivityBridge& operator=(
      const DiscordSocialSdkActivityBridge&) = delete;

  bool CanHandle(const std::string& method) const;
  void ResetSession();
  void Handle(
      const flutter::MethodCall<>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};

#endif  // RUNNER_DISCORD_SOCIAL_SDK_ACTIVITY_BRIDGE_H_
