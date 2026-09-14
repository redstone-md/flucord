#include "discord_social_sdk_activity_bridge.h"

#include "discord_social_sdk_wire.h"

#include <algorithm>
#include <cstdint>
#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <variant>

#if defined(FLUCORD_DISCORD_SOCIAL_SDK_ENABLED)
#include <discord_partner_sdk/discordpp.h>
#endif

namespace {

using discord_social_sdk_wire::BoolArgument;
using discord_social_sdk_wire::ArgumentsOf;
using discord_social_sdk_wire::InvalidArguments;
using discord_social_sdk_wire::MethodResult;
using discord_social_sdk_wire::SnowflakeArgument;
using discord_social_sdk_wire::StringArgument;

#if defined(FLUCORD_DISCORD_SOCIAL_SDK_ENABLED)
std::optional<std::string> AnyStringArgument(
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
  return value == nullptr ? std::nullopt : std::optional<std::string>(*value);
}

std::string InviteTypeName(discordpp::ActivityActionTypes type) {
  switch (type) {
    case discordpp::ActivityActionTypes::Join:
      return "join";
    case discordpp::ActivityActionTypes::JoinRequest:
      return "join_request";
    default:
      return "unknown";
  }
}

std::optional<discordpp::ActivityActionTypes> InviteType(
    const std::string& value) {
  if (value == "join") {
    return discordpp::ActivityActionTypes::Join;
  }
  if (value == "join_request") {
    return discordpp::ActivityActionTypes::JoinRequest;
  }
  return std::nullopt;
}

std::optional<uint64_t> Uint64Value(const std::optional<std::string>& value) {
  if (!value) {
    return std::nullopt;
  }
  try {
    size_t parsed = 0;
    const auto result = std::stoull(*value, &parsed);
    return parsed == value->size() ? std::optional<uint64_t>(result)
                                   : std::nullopt;
  } catch (...) {
    return std::nullopt;
  }
}

flutter::EncodableMap InvitePayload(const discordpp::ActivityInvite& invite) {
  flutter::EncodableMap payload;
  payload[flutter::EncodableValue("application_id")] =
      flutter::EncodableValue(std::to_string(invite.ApplicationId()));
  payload[flutter::EncodableValue("parent_application_id")] =
      flutter::EncodableValue(std::to_string(invite.ParentApplicationId()));
  payload[flutter::EncodableValue("channel_id")] =
      flutter::EncodableValue(std::to_string(invite.ChannelId()));
  payload[flutter::EncodableValue("message_id")] =
      flutter::EncodableValue(std::to_string(invite.MessageId()));
  payload[flutter::EncodableValue("sender_id")] =
      flutter::EncodableValue(std::to_string(invite.SenderId()));
  payload[flutter::EncodableValue("party_id")] =
      flutter::EncodableValue(invite.PartyId());
  payload[flutter::EncodableValue("session_id")] =
      flutter::EncodableValue(invite.SessionId());
  payload[flutter::EncodableValue("invite_type")] =
      flutter::EncodableValue(InviteTypeName(invite.Type()));
  payload[flutter::EncodableValue("is_valid")] =
      flutter::EncodableValue(invite.IsValid());
  return payload;
}

flutter::EncodableValue SessionPayload(uint64_t lobby_id) {
  flutter::EncodableMap payload;
  payload[flutter::EncodableValue("lobby_id")] =
      flutter::EncodableValue(std::to_string(lobby_id));
  return flutter::EncodableValue(payload);
}
#endif

}  // namespace

class DiscordSocialSdkActivityBridge::Impl {
 public:
  Impl(discordpp::Client* client,
       flutter::MethodChannel<flutter::EncodableValue>* channel)
      : client_(client), channel_(channel) {
#if defined(FLUCORD_DISCORD_SOCIAL_SDK_ENABLED)
    client_->SetActivityInviteCreatedCallback(
        [this](discordpp::ActivityInvite invite) {
          NotifyInvite("created", invite);
        });
    client_->SetActivityInviteUpdatedCallback(
        [this](discordpp::ActivityInvite invite) {
          NotifyInvite("updated", invite);
        });
#endif
  }

  bool CanHandle(const std::string& method) const {
    return method == "sendActivityInvite" ||
           method == "acceptActivityInvite";
  }

  void ResetSession() {
#if defined(FLUCORD_DISCORD_SOCIAL_SDK_ENABLED)
    ResetStartingSession();
#endif
  }

  void Handle(const flutter::MethodCall<>& call,
              std::unique_ptr<MethodResult> result) {
#if defined(FLUCORD_DISCORD_SOCIAL_SDK_ENABLED)
    if (client_->GetStatus() != discordpp::Client::Status::Ready) {
      result->Error("not_authenticated",
                    "Activity invites require a ready Social SDK session.");
      return;
    }
    if (call.method_name() == "sendActivityInvite") {
      SendInvite(call, std::move(result));
    } else {
      AcceptInvite(call, std::move(result));
    }
#else
    result->Error("sdk_not_bundled",
                  "The Discord Social SDK package is not linked.");
#endif
  }

 private:
#if defined(FLUCORD_DISCORD_SOCIAL_SDK_ENABLED)
  void SendInvite(const flutter::MethodCall<>& call,
                  std::unique_ptr<MethodResult> result) {
    const auto user_id = SnowflakeArgument(call, "user_id");
    const auto requested_secret = StringArgument(call, "lobby_secret");
    if (!user_id || !requested_secret) {
      InvalidArguments(std::move(result));
      return;
    }
    auto pending = std::shared_ptr<MethodResult>(std::move(result));
    if (active_lobby_id_ != 0) {
      DispatchInvite(*user_id, pending);
      return;
    }
    if (session_starting_) {
      pending->Error("activity_session_busy",
                     "An activity lobby is already being created.");
      return;
    }
    session_starting_ = true;
    ClearActiveSecret();
    active_lobby_secret_ = *requested_secret;
    client_->CreateOrJoinLobby(
        active_lobby_secret_,
        [this, pending, user_id = *user_id](
            const discordpp::ClientResult& sdk_result, uint64_t lobby_id) {
          if (!sdk_result.Successful() || lobby_id == 0) {
            ResetStartingSession();
            pending->Error("activity_lobby_failed",
                           "Discord could not create the activity lobby.");
            return;
          }
          active_lobby_id_ = lobby_id;
          discordpp::ActivitySecrets secrets{};
          secrets.SetJoin(active_lobby_secret_);
          discordpp::Activity activity{};
          activity.SetType(discordpp::ActivityTypes::Playing);
          activity.SetDetails("Native social session");
          activity.SetState("Open activity lobby");
          activity.SetSecrets(secrets);
          client_->UpdateRichPresence(
              std::move(activity),
              [this, pending, user_id](
                  const discordpp::ClientResult& presence_result) {
                session_starting_ = false;
                if (!presence_result.Successful()) {
                  active_lobby_id_ = 0;
                  ClearActiveSecret();
                  pending->Error(
                      "activity_presence_failed",
                      "Discord could not publish the activity join secret.");
                  return;
                }
                DispatchInvite(user_id, pending);
              });
        });
  }

  void DispatchInvite(uint64_t user_id,
                      const std::shared_ptr<MethodResult>& pending) {
    client_->SendActivityInvite(
        user_id, "Join me in Flucord",
        [this, pending](const discordpp::ClientResult& sdk_result) {
          if (!sdk_result.Successful()) {
            pending->Error("activity_invite_failed",
                           "Discord rejected the activity invite.");
            return;
          }
          pending->Success(SessionPayload(active_lobby_id_));
        });
  }

  void AcceptInvite(const flutter::MethodCall<>& call,
                    std::unique_ptr<MethodResult> result) {
    const auto application_id = SnowflakeArgument(call, "application_id");
    const auto parent_application_id =
        Uint64Value(StringArgument(call, "parent_application_id"));
    const auto channel_id = SnowflakeArgument(call, "channel_id");
    const auto message_id = SnowflakeArgument(call, "message_id");
    const auto sender_id = SnowflakeArgument(call, "sender_id");
    const auto party_id = AnyStringArgument(call, "party_id");
    const auto session_id = AnyStringArgument(call, "session_id");
    const auto type_name = StringArgument(call, "invite_type");
    const auto type = type_name ? InviteType(*type_name) : std::nullopt;
    const auto is_valid = BoolArgument(call, "is_valid");
    if (!application_id || !parent_application_id || !channel_id ||
        !message_id || !sender_id || !party_id || !session_id || !type ||
        !is_valid || !*is_valid) {
      InvalidArguments(std::move(result));
      return;
    }
    discordpp::ActivityInvite invite{};
    invite.SetApplicationId(*application_id);
    invite.SetParentApplicationId(*parent_application_id);
    invite.SetChannelId(*channel_id);
    invite.SetMessageId(*message_id);
    invite.SetSenderId(*sender_id);
    invite.SetPartyId(*party_id);
    invite.SetSessionId(*session_id);
    invite.SetType(*type);
    invite.SetIsValid(true);
    auto pending = std::shared_ptr<MethodResult>(std::move(result));
    client_->AcceptActivityInvite(
        std::move(invite),
        [this, pending](const discordpp::ClientResult& sdk_result,
                        const std::string& join_secret) {
          if (!sdk_result.Successful() || join_secret.empty()) {
            pending->Error("activity_accept_failed",
                           "Discord rejected the activity invite.");
            return;
          }
          client_->CreateOrJoinLobby(
              join_secret,
              [this, pending, join_secret](
                  const discordpp::ClientResult& join_result,
                  uint64_t lobby_id) {
                if (!join_result.Successful() || lobby_id == 0) {
                  pending->Error("activity_join_failed",
                                 "Discord could not join the activity lobby.");
                  return;
                }
                active_lobby_id_ = lobby_id;
                ClearActiveSecret();
                active_lobby_secret_ = join_secret;
                pending->Success(SessionPayload(lobby_id));
              });
        });
  }

  void NotifyInvite(const std::string& type,
                    const discordpp::ActivityInvite& invite) {
    flutter::EncodableMap payload;
    payload[flutter::EncodableValue("type")] = flutter::EncodableValue(type);
    payload[flutter::EncodableValue("invite")] =
        flutter::EncodableValue(InvitePayload(invite));
    channel_->InvokeMethod(
        "socialActivityInviteChanged",
        std::make_unique<flutter::EncodableValue>(payload));
  }

  void ResetStartingSession() {
    session_starting_ = false;
    active_lobby_id_ = 0;
    ClearActiveSecret();
  }

  void ClearActiveSecret() {
    std::fill(active_lobby_secret_.begin(), active_lobby_secret_.end(), '\0');
    active_lobby_secret_.clear();
  }

  uint64_t active_lobby_id_ = 0;
  std::string active_lobby_secret_;
  bool session_starting_ = false;
#endif

  discordpp::Client* client_;
  flutter::MethodChannel<flutter::EncodableValue>* channel_;
};

DiscordSocialSdkActivityBridge::DiscordSocialSdkActivityBridge(
    discordpp::Client* client,
    flutter::MethodChannel<flutter::EncodableValue>* channel)
    : impl_(std::make_unique<Impl>(client, channel)) {}

DiscordSocialSdkActivityBridge::~DiscordSocialSdkActivityBridge() = default;

bool DiscordSocialSdkActivityBridge::CanHandle(
    const std::string& method) const {
  return impl_->CanHandle(method);
}

void DiscordSocialSdkActivityBridge::ResetSession() {
#if defined(FLUCORD_DISCORD_SOCIAL_SDK_ENABLED)
  impl_->ResetSession();
#endif
}

void DiscordSocialSdkActivityBridge::Handle(
    const flutter::MethodCall<>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  impl_->Handle(call, std::move(result));
}
