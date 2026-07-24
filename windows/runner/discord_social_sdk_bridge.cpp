#include "discord_social_sdk_bridge.h"
#include "discord_social_sdk_chat_bridge.h"
#include "discord_social_sdk_wire.h"

#include <flutter/standard_method_codec.h>

#include <cstdint>
#include <memory>
#include <string>
#include <utility>

#if defined(FLUCORD_DISCORD_SOCIAL_SDK_ENABLED)
#define DISCORDPP_IMPLEMENTATION
#include <discord_partner_sdk/discordpp.h>
#endif

namespace {

using discord_social_sdk_wire::InvalidArguments;
using discord_social_sdk_wire::MethodResult;
using discord_social_sdk_wire::SnowflakeArgument;
using discord_social_sdk_wire::StringArgument;

flutter::EncodableValue AvailabilityPayload() {
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

class DiscordSocialSdkBridge::Impl {
 public:
  explicit Impl(
      flutter::MethodChannel<flutter::EncodableValue>* channel)
      : channel_(channel) {
#if defined(FLUCORD_DISCORD_SOCIAL_SDK_ENABLED)
    client_ = std::make_unique<discordpp::Client>();
    client_->SetStatusChangedCallback(
        [this](discordpp::Client::Status status,
               discordpp::Client::Error error, int32_t) {
          if (status == discordpp::Client::Status::Ready) {
            CompleteAuthentication();
          } else if (status == discordpp::Client::Status::Disconnected &&
                     error != discordpp::Client::Error::None &&
                     pending_auth_result_) {
            FailAuthentication("connection_failed");
          }
        });
    client_->SetTokenExpirationCallback(
        [this]() { RefreshExpiringToken(); });
    chat_bridge_ =
        std::make_unique<DiscordSocialSdkChatBridge>(client_.get(), channel_);
#endif
  }

  void Handle(const flutter::MethodCall<>& call,
              std::unique_ptr<MethodResult> result) {
    if (call.method_name() == "getAvailability") {
      result->Success(AvailabilityPayload());
      return;
    }
#if defined(FLUCORD_DISCORD_SOCIAL_SDK_ENABLED)
    if (call.method_name() == "authorize") {
      Authorize(call, std::move(result));
      return;
    }
    if (call.method_name() == "restoreSession") {
      RestoreSession(call, std::move(result));
      return;
    }
    if (call.method_name() == "disconnect") {
      Disconnect(std::move(result));
      return;
    }
    if (call.method_name() == "getRelationships") {
      GetRelationships(std::move(result));
      return;
    }
    if (call.method_name() == "updateRelationship") {
      UpdateRelationship(call, std::move(result));
      return;
    }
    if (chat_bridge_->CanHandle(call.method_name())) {
      chat_bridge_->Handle(call, std::move(result));
      return;
    }
#else
    if (call.method_name() == "authorize" ||
        call.method_name() == "restoreSession" ||
        call.method_name() == "disconnect" ||
        call.method_name() == "getRelationships" ||
        call.method_name() == "updateRelationship" ||
        call.method_name() == "getDmConversations" ||
        call.method_name() == "getDmMessages" ||
        call.method_name() == "sendDmMessage") {
      result->Error(
          "sdk_not_bundled",
          "The Discord Social SDK package is not linked into this build.");
      return;
    }
#endif
    result->NotImplemented();
  }

  void PumpCallbacks() {
#if defined(FLUCORD_DISCORD_SOCIAL_SDK_ENABLED)
    discordpp::RunCallbacks();
#endif
  }

 private:
#if defined(FLUCORD_DISCORD_SOCIAL_SDK_ENABLED)
  struct Grant {
    std::string access_token;
    std::string refresh_token;
    std::string scopes;
    int32_t expires_in = 0;

    bool IsComplete() const {
      return !access_token.empty() && !refresh_token.empty() && expires_in > 0;
    }
  };

  void Authorize(const flutter::MethodCall<>& call,
                 std::unique_ptr<MethodResult> result) {
    const auto client_id = SnowflakeArgument(call, "client_id");
    if (!client_id) {
      InvalidArguments(std::move(result));
      return;
    }
    if (!StartAuthentication(*client_id, std::move(result))) {
      return;
    }
    client_->SetApplicationId(application_id_);
    const auto verifier = client_->CreateAuthorizationCodeVerifier();
    discordpp::AuthorizationArgs arguments{};
    arguments.SetClientId(application_id_);
    arguments.SetScopes(discordpp::Client::GetDefaultCommunicationScopes());
    arguments.SetCodeChallenge(verifier.Challenge());
    client_->Authorize(
        arguments,
        [this, verifier](const discordpp::ClientResult& auth_result,
                         const std::string& code,
                         const std::string& redirect_uri) {
          if (!auth_result.Successful()) {
            FailAuthentication("authorization_failed");
            return;
          }
          client_->GetToken(
              application_id_, code, verifier.Verifier(), redirect_uri,
              [this](const discordpp::ClientResult& token_result,
                     const std::string& access_token,
                     const std::string& refresh_token,
                     discordpp::AuthorizationTokenType token_type,
                     int32_t expires_in, const std::string& scopes) {
                HandleTokenExchange(token_result, access_token, refresh_token,
                                    token_type, expires_in, scopes, false);
              });
        });
  }

  void RestoreSession(const flutter::MethodCall<>& call,
                      std::unique_ptr<MethodResult> result) {
    const auto client_id = SnowflakeArgument(call, "client_id");
    const auto refresh_token = StringArgument(call, "refresh_token");
    if (!client_id || !refresh_token) {
      InvalidArguments(std::move(result));
      return;
    }
    if (!StartAuthentication(*client_id, std::move(result))) {
      return;
    }
    client_->SetApplicationId(application_id_);
    refresh_in_flight_ = true;
    client_->RefreshToken(
        application_id_, *refresh_token,
        [this](const discordpp::ClientResult& token_result,
               const std::string& access_token,
               const std::string& next_refresh_token,
               discordpp::AuthorizationTokenType token_type,
               int32_t expires_in, const std::string& scopes) {
          HandleTokenExchange(token_result, access_token, next_refresh_token,
                              token_type, expires_in, scopes, false);
        });
  }

  bool StartAuthentication(uint64_t application_id,
                           std::unique_ptr<MethodResult> result) {
    if (pending_auth_result_ || refresh_in_flight_) {
      result->Error("authentication_in_progress",
                    "A Social SDK authentication operation is already active.");
      return false;
    }
    application_id_ = application_id;
    pending_auth_result_ = std::shared_ptr<MethodResult>(std::move(result));
    return true;
  }

  void HandleTokenExchange(
      const discordpp::ClientResult& token_result,
      const std::string& access_token, const std::string& refresh_token,
      discordpp::AuthorizationTokenType token_type, int32_t expires_in,
      const std::string& scopes, bool background_refresh) {
    refresh_in_flight_ = false;
    if (!token_result.Successful()) {
      if (background_refresh) {
        NotifyAuthenticationExpired();
      } else {
        FailAuthentication("refresh_failed");
      }
      return;
    }
    grant_ = Grant{access_token, refresh_token, scopes, expires_in};
    client_->UpdateToken(
        token_type, access_token,
        [this, background_refresh](const discordpp::ClientResult& result) {
          if (!result.Successful()) {
            if (background_refresh) {
              NotifyAuthenticationExpired();
            } else {
              FailAuthentication("token_update_failed");
            }
            return;
          }
          if (background_refresh) {
            NotifyGrantChanged();
            return;
          }
          if (client_->GetStatus() == discordpp::Client::Status::Ready) {
            CompleteAuthentication();
          } else {
            client_->Connect();
          }
        });
  }

  void RefreshExpiringToken() {
    if (refresh_in_flight_ || !grant_.IsComplete() || application_id_ == 0) {
      NotifyAuthenticationExpired();
      return;
    }
    refresh_in_flight_ = true;
    client_->RefreshToken(
        application_id_, grant_.refresh_token,
        [this](const discordpp::ClientResult& token_result,
               const std::string& access_token,
               const std::string& refresh_token,
               discordpp::AuthorizationTokenType token_type,
               int32_t expires_in, const std::string& scopes) {
          HandleTokenExchange(token_result, access_token, refresh_token,
                              token_type, expires_in, scopes, true);
        });
  }

  void CompleteAuthentication() {
    if (!pending_auth_result_ || !grant_.IsComplete()) {
      return;
    }
    pending_auth_result_->Success(GrantPayload());
    pending_auth_result_.reset();
  }

  void FailAuthentication(const std::string& code) {
    refresh_in_flight_ = false;
    if (!pending_auth_result_) {
      return;
    }
    pending_auth_result_->Error(code, "Discord Social SDK authentication failed.");
    pending_auth_result_.reset();
  }

  flutter::EncodableValue GrantPayload() const {
    flutter::EncodableMap payload;
    payload[flutter::EncodableValue("access_token")] =
        flutter::EncodableValue(grant_.access_token);
    payload[flutter::EncodableValue("refresh_token")] =
        flutter::EncodableValue(grant_.refresh_token);
    payload[flutter::EncodableValue("expires_in")] =
        flutter::EncodableValue(grant_.expires_in);
    payload[flutter::EncodableValue("scopes")] =
        flutter::EncodableValue(grant_.scopes);
    return flutter::EncodableValue(payload);
  }

  void NotifyGrantChanged() {
    channel_->InvokeMethod("authenticationGrantChanged",
                           std::make_unique<flutter::EncodableValue>(
                               GrantPayload()));
  }

  void NotifyAuthenticationExpired() {
    grant_ = Grant{};
    channel_->InvokeMethod(
        "authenticationExpired",
        std::make_unique<flutter::EncodableValue>());
  }

  void Disconnect(std::unique_ptr<MethodResult> result) {
    client_->AbortAuthorize();
    if (pending_auth_result_) {
      pending_auth_result_->Error("authorization_cancelled",
                                  "Social SDK authorization was cancelled.");
      pending_auth_result_.reset();
    }
    refresh_in_flight_ = false;
    grant_ = Grant{};
    client_->Disconnect();
    result->Success();
  }

  void GetRelationships(std::unique_ptr<MethodResult> result) {
    if (client_->GetStatus() != discordpp::Client::Status::Ready) {
      result->Error("not_authenticated",
                    "Relationships require a ready Social SDK session.");
      return;
    }
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
    if (client_->GetStatus() != discordpp::Client::Status::Ready) {
      result->Error("not_authenticated",
                    "Relationship mutations require a ready SDK session.");
      return;
    }
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

  static std::string PresenceName(discordpp::StatusType status) {
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

  static std::string RelationshipName(discordpp::RelationshipType type) {
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

  std::unique_ptr<discordpp::Client> client_;
  std::unique_ptr<DiscordSocialSdkChatBridge> chat_bridge_;
  std::shared_ptr<MethodResult> pending_auth_result_;
  Grant grant_;
  uint64_t application_id_ = 0;
  bool refresh_in_flight_ = false;
#endif
  flutter::MethodChannel<flutter::EncodableValue>* channel_;
};

DiscordSocialSdkBridge::DiscordSocialSdkBridge(
    flutter::BinaryMessenger* messenger)
    : channel_(std::make_unique<flutter::MethodChannel<>>(
          messenger, "flucord/social_sdk",
          &flutter::StandardMethodCodec::GetInstance())),
      impl_(std::make_unique<Impl>(channel_.get())) {
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<>& call,
             std::unique_ptr<MethodResult> result) {
        impl_->Handle(call, std::move(result));
      });
}

DiscordSocialSdkBridge::~DiscordSocialSdkBridge() = default;

void DiscordSocialSdkBridge::PumpCallbacks() {
  impl_->PumpCallbacks();
}
