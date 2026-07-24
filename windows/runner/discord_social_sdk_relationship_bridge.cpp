#include "discord_social_sdk_relationship_bridge.h"

#include "discord_social_sdk_wire.h"

#include <cstdint>
#include <memory>
#include <optional>
#include <string>
#include <utility>

#if defined(FLUCORD_DISCORD_SOCIAL_SDK_ENABLED)
#include <discord_partner_sdk/discordpp.h>
#endif

namespace {

using discord_social_sdk_wire::InvalidArguments;
using discord_social_sdk_wire::MethodResult;
using discord_social_sdk_wire::SnowflakeArgument;
using discord_social_sdk_wire::StringArgument;

#if defined(FLUCORD_DISCORD_SOCIAL_SDK_ENABLED)
std::string PresenceName(discordpp::StatusType status) {
  switch (status) {
    case discordpp::StatusType::Online:
    case discordpp::StatusType::Streaming:
      return "online";
    case discordpp::StatusType::Idle:
      return "idle";
    case discordpp::StatusType::Dnd:
      return "dnd";
    case discordpp::StatusType::Offline:
    case discordpp::StatusType::Invisible:
      return "offline";
    default:
      return "unknown";
  }
}

std::string RelationshipName(discordpp::RelationshipType type) {
  switch (type) {
    case discordpp::RelationshipType::Friend:
      return "friend";
    case discordpp::RelationshipType::Blocked:
      return "blocked";
    case discordpp::RelationshipType::PendingIncoming:
      return "pending_incoming";
    case discordpp::RelationshipType::PendingOutgoing:
      return "pending_outgoing";
    case discordpp::RelationshipType::Implicit:
      return "implicit";
    default:
      return "unknown";
  }
}

std::optional<discordpp::StatusType> OnlineStatus(const std::string& value) {
  if (value == "online") {
    return discordpp::StatusType::Online;
  }
  if (value == "idle") {
    return discordpp::StatusType::Idle;
  }
  if (value == "dnd") {
    return discordpp::StatusType::Dnd;
  }
  if (value == "invisible") {
    return discordpp::StatusType::Invisible;
  }
  return std::nullopt;
}
#endif

}  // namespace

class DiscordSocialSdkRelationshipBridge::Impl {
 public:
  Impl(discordpp::Client* client,
       flutter::MethodChannel<flutter::EncodableValue>* channel)
      : client_(client), channel_(channel) {
#if defined(FLUCORD_DISCORD_SOCIAL_SDK_ENABLED)
    client_->SetUserUpdatedCallback(
        [this](uint64_t user_id) { NotifyUserUpdated(user_id); });
    client_->SetRelationshipCreatedCallback(
        [this](uint64_t user_id, bool is_discord_relationship_update) {
          if (is_discord_relationship_update) {
            NotifyUserUpdated(user_id);
          }
        });
    client_->SetRelationshipGroupsUpdatedCallback(
        [this](uint64_t user_id) { NotifyUserUpdated(user_id); });
#endif
  }

  bool CanHandle(const std::string& method) const {
    return method == "getRelationships" || method == "updateRelationship" ||
           method == "sendFriendRequest" || method == "setOnlineStatus";
  }

  void Handle(const flutter::MethodCall<>& call,
              std::unique_ptr<MethodResult> result) {
#if defined(FLUCORD_DISCORD_SOCIAL_SDK_ENABLED)
    if (client_->GetStatus() != discordpp::Client::Status::Ready) {
      result->Error("not_authenticated",
                    "Relationships require a ready Social SDK session.");
      return;
    }
    if (call.method_name() == "getRelationships") {
      GetRelationships(std::move(result));
    } else if (call.method_name() == "updateRelationship") {
      UpdateRelationship(call, std::move(result));
    } else if (call.method_name() == "sendFriendRequest") {
      SendFriendRequest(call, std::move(result));
    } else {
      SetOnlineStatus(call, std::move(result));
    }
#else
    result->Error("sdk_not_bundled",
                  "The Discord Social SDK package is not linked.");
#endif
  }

 private:
#if defined(FLUCORD_DISCORD_SOCIAL_SDK_ENABLED)
  void GetRelationships(std::unique_ptr<MethodResult> result) {
    flutter::EncodableList payload;
    for (const auto& relationship : client_->GetRelationships()) {
      const auto user = relationship.User();
      if (!user) {
        continue;
      }
      flutter::EncodableMap item;
      item[flutter::EncodableValue("id")] =
          flutter::EncodableValue(std::to_string(relationship.Id()));
      item[flutter::EncodableValue("display_name")] =
          flutter::EncodableValue(user->DisplayName());
      item[flutter::EncodableValue("username")] =
          flutter::EncodableValue(user->Username());
      item[flutter::EncodableValue("avatar_url")] = flutter::EncodableValue(
          user->AvatarUrl(discordpp::UserHandle::AvatarType::Gif,
                          discordpp::UserHandle::AvatarType::Webp));
      item[flutter::EncodableValue("status")] =
          flutter::EncodableValue(PresenceName(user->Status()));
      item[flutter::EncodableValue("relationship_type")] =
          flutter::EncodableValue(
              RelationshipName(relationship.DiscordRelationshipType()));
      item[flutter::EncodableValue("is_provisional")] =
          flutter::EncodableValue(user->IsProvisional());
      payload.emplace_back(item);
    }
    result->Success(flutter::EncodableValue(payload));
  }

  void UpdateRelationship(const flutter::MethodCall<>& call,
                          std::unique_ptr<MethodResult> result) {
    const auto user_id = SnowflakeArgument(call, "user_id");
    const auto action = StringArgument(call, "action");
    if (!user_id || !action) {
      InvalidArguments(std::move(result));
      return;
    }
    auto pending = std::shared_ptr<MethodResult>(std::move(result));
    auto callback = [pending](const discordpp::ClientResult& sdk_result) {
      if (sdk_result.Successful()) {
        pending->Success();
      } else {
        pending->Error("relationship_update_failed",
                       "Discord rejected the relationship update.");
      }
    };
    if (*action == "accept_request") {
      client_->AcceptDiscordFriendRequest(*user_id, callback);
    } else if (*action == "reject_request") {
      client_->RejectDiscordFriendRequest(*user_id, callback);
    } else if (*action == "cancel_request") {
      client_->CancelDiscordFriendRequest(*user_id, callback);
    } else if (*action == "remove_friend") {
      client_->RemoveDiscordAndGameFriend(*user_id, callback);
    } else if (*action == "block_user") {
      client_->BlockUser(*user_id, callback);
    } else {
      pending->Error("unsupported_action",
                     "The relationship action is not supported.");
    }
  }

  void SetOnlineStatus(const flutter::MethodCall<>& call,
                       std::unique_ptr<MethodResult> result) {
    const auto status_name = StringArgument(call, "status");
    const auto status = status_name ? OnlineStatus(*status_name) : std::nullopt;
    if (!status) {
      InvalidArguments(std::move(result));
      return;
    }
    auto pending = std::shared_ptr<MethodResult>(std::move(result));
    client_->SetOnlineStatus(
        *status, [pending](const discordpp::ClientResult& sdk_result) {
          if (sdk_result.Successful()) {
            pending->Success();
          } else {
            pending->Error("status_update_failed",
                           "Discord rejected the online status update.");
          }
        });
  }

  void SendFriendRequest(const flutter::MethodCall<>& call,
                         std::unique_ptr<MethodResult> result) {
    const auto user_id = SnowflakeArgument(call, "user_id");
    if (!user_id) {
      InvalidArguments(std::move(result));
      return;
    }
    auto pending = std::shared_ptr<MethodResult>(std::move(result));
    client_->SendDiscordFriendRequestById(
        *user_id, [pending](const discordpp::ClientResult& sdk_result) {
          if (sdk_result.Successful()) {
            pending->Success();
          } else {
            pending->Error("friend_request_failed",
                           "Discord rejected the friend request.");
          }
        });
  }

  void NotifyUserUpdated(uint64_t user_id) {
    flutter::EncodableMap payload;
    payload[flutter::EncodableValue("user_id")] =
        flutter::EncodableValue(std::to_string(user_id));
    channel_->InvokeMethod(
        "socialUserUpdated",
        std::make_unique<flutter::EncodableValue>(payload));
  }
#endif

  discordpp::Client* client_;
  flutter::MethodChannel<flutter::EncodableValue>* channel_;
};

DiscordSocialSdkRelationshipBridge::DiscordSocialSdkRelationshipBridge(
    discordpp::Client* client,
    flutter::MethodChannel<flutter::EncodableValue>* channel)
    : impl_(std::make_unique<Impl>(client, channel)) {}

DiscordSocialSdkRelationshipBridge::~DiscordSocialSdkRelationshipBridge() =
    default;

bool DiscordSocialSdkRelationshipBridge::CanHandle(
    const std::string& method) const {
  return impl_->CanHandle(method);
}

void DiscordSocialSdkRelationshipBridge::Handle(
    const flutter::MethodCall<>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  impl_->Handle(call, std::move(result));
}
