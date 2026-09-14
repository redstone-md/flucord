#ifndef RUNNER_DISCORD_SOCIAL_SDK_RELATIONSHIP_BRIDGE_H_
#define RUNNER_DISCORD_SOCIAL_SDK_RELATIONSHIP_BRIDGE_H_

#include <flutter/encodable_value.h>
#include <flutter/method_call.h>
#include <flutter/method_channel.h>
#include <flutter/method_result.h>

#include <memory>
#include <string>

namespace discordpp {
class Client;
}

class DiscordSocialSdkRelationshipBridge {
 public:
  DiscordSocialSdkRelationshipBridge(
      discordpp::Client* client,
      flutter::MethodChannel<flutter::EncodableValue>* channel);
  ~DiscordSocialSdkRelationshipBridge();

  DiscordSocialSdkRelationshipBridge(
      const DiscordSocialSdkRelationshipBridge&) = delete;
  DiscordSocialSdkRelationshipBridge& operator=(
      const DiscordSocialSdkRelationshipBridge&) = delete;

  bool CanHandle(const std::string& method) const;
  void Handle(
      const flutter::MethodCall<>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};

#endif  // RUNNER_DISCORD_SOCIAL_SDK_RELATIONSHIP_BRIDGE_H_
