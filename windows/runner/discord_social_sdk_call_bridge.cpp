#include "discord_social_sdk_call_bridge.h"

#include "discord_social_sdk_wire.h"

#include <cstdint>
#include <memory>
#include <string>
#include <utility>

#if defined(FLUCORD_DISCORD_SOCIAL_SDK_ENABLED)
#include <discord_partner_sdk/discordpp.h>
#endif

namespace {

using discord_social_sdk_wire::BoolArgument;
using discord_social_sdk_wire::InvalidArguments;
using discord_social_sdk_wire::MethodResult;
using discord_social_sdk_wire::SnowflakeArgument;

#if defined(FLUCORD_DISCORD_SOCIAL_SDK_ENABLED)
std::string CallStatusName(discordpp::Call::Status status) {
  switch (status) {
    case discordpp::Call::Status::Disconnected:
      return "disconnected";
    case discordpp::Call::Status::Joining:
      return "joining";
    case discordpp::Call::Status::Connecting:
      return "connecting";
    case discordpp::Call::Status::SignalingConnected:
      return "signaling_connected";
    case discordpp::Call::Status::Connected:
      return "connected";
    case discordpp::Call::Status::Reconnecting:
      return "reconnecting";
    case discordpp::Call::Status::Disconnecting:
      return "disconnecting";
    default:
      return "unknown";
  }
}

flutter::EncodableValue DisconnectedPayload(uint64_t lobby_id) {
  flutter::EncodableMap payload;
  payload[flutter::EncodableValue("lobby_id")] =
      flutter::EncodableValue(std::to_string(lobby_id));
  payload[flutter::EncodableValue("status")] =
      flutter::EncodableValue("disconnected");
  payload[flutter::EncodableValue("participant_user_ids")] =
      flutter::EncodableValue(flutter::EncodableList{});
  payload[flutter::EncodableValue("self_muted")] =
      flutter::EncodableValue(false);
  payload[flutter::EncodableValue("self_deafened")] =
      flutter::EncodableValue(false);
  return flutter::EncodableValue(payload);
}

flutter::EncodableValue CallPayload(uint64_t lobby_id,
                                    discordpp::Call& call) {
  flutter::EncodableList participants;
  for (const auto user_id : call.GetParticipants()) {
    participants.emplace_back(std::to_string(user_id));
  }
  flutter::EncodableMap payload;
  payload[flutter::EncodableValue("lobby_id")] =
      flutter::EncodableValue(std::to_string(lobby_id));
  payload[flutter::EncodableValue("status")] =
      flutter::EncodableValue(CallStatusName(call.GetStatus()));
  payload[flutter::EncodableValue("participant_user_ids")] =
      flutter::EncodableValue(participants);
  payload[flutter::EncodableValue("self_muted")] =
      flutter::EncodableValue(call.GetSelfMute());
  payload[flutter::EncodableValue("self_deafened")] =
      flutter::EncodableValue(call.GetSelfDeaf());
  return flutter::EncodableValue(payload);
}
#endif

}  // namespace

class DiscordSocialSdkCallBridge::Impl {
 public:
  Impl(discordpp::Client* client,
       flutter::MethodChannel<flutter::EncodableValue>* channel)
      : client_(client), channel_(channel) {}

  bool CanHandle(const std::string& method) const {
    return method == "startActivityCall" ||
           method == "setActivityCallMuted" ||
           method == "setActivityCallDeafened" ||
           method == "leaveActivityCall";
  }

  void ResetSession() {
#if defined(FLUCORD_DISCORD_SOCIAL_SDK_ENABLED)
    call_.reset();
    active_lobby_id_ = 0;
#endif
  }

  void Handle(const flutter::MethodCall<>& method_call,
              std::unique_ptr<MethodResult> result) {
#if defined(FLUCORD_DISCORD_SOCIAL_SDK_ENABLED)
    if (client_->GetStatus() != discordpp::Client::Status::Ready) {
      result->Error("not_authenticated",
                    "Activity voice requires a ready Social SDK session.");
      return;
    }
    if (method_call.method_name() == "startActivityCall") {
      Start(method_call, std::move(result));
    } else if (method_call.method_name() == "leaveActivityCall") {
      Leave(method_call, std::move(result));
    } else {
      SetVoiceState(method_call, std::move(result));
    }
#else
    result->Error("sdk_not_bundled",
                  "The Discord Social SDK package is not linked.");
#endif
  }

 private:
#if defined(FLUCORD_DISCORD_SOCIAL_SDK_ENABLED)
  void Start(const flutter::MethodCall<>& method_call,
             std::unique_ptr<MethodResult> result) {
    const auto lobby_id = SnowflakeArgument(method_call, "lobby_id");
    if (!lobby_id) {
      InvalidArguments(std::move(result));
      return;
    }
    if (call_ && active_lobby_id_ == *lobby_id) {
      result->Success(CallPayload(active_lobby_id_, *call_));
      return;
    }
    if (call_) {
      result->Error("activity_call_active",
                    "Another activity voice call is already active.");
      return;
    }
    active_lobby_id_ = *lobby_id;
    call_ = std::make_unique<discordpp::Call>(
        client_->StartCall(active_lobby_id_));
    call_->SetStatusChangedCallback(
        [this](discordpp::Call::Status, discordpp::Call::Error, int32_t) {
          NotifyCallState();
        });
    call_->SetParticipantChangedCallback(
        [this](uint64_t, bool) { NotifyCallState(); });
    result->Success(CallPayload(active_lobby_id_, *call_));
  }

  void SetVoiceState(const flutter::MethodCall<>& method_call,
                     std::unique_ptr<MethodResult> result) {
    const auto lobby_id = SnowflakeArgument(method_call, "lobby_id");
    const auto value = BoolArgument(method_call, "value");
    if (!lobby_id || !value || !call_ || *lobby_id != active_lobby_id_) {
      InvalidArguments(std::move(result));
      return;
    }
    if (method_call.method_name() == "setActivityCallMuted") {
      call_->SetSelfMute(*value);
    } else {
      call_->SetSelfDeaf(*value);
    }
    const auto payload = CallPayload(active_lobby_id_, *call_);
    result->Success(payload);
    NotifyCallState();
  }

  void Leave(const flutter::MethodCall<>& method_call,
             std::unique_ptr<MethodResult> result) {
    const auto lobby_id = SnowflakeArgument(method_call, "lobby_id");
    if (!lobby_id || !call_ || *lobby_id != active_lobby_id_) {
      InvalidArguments(std::move(result));
      return;
    }
    const auto ending_lobby_id = active_lobby_id_;
    auto pending = std::shared_ptr<MethodResult>(std::move(result));
    client_->EndCalls(
        [this, pending, ending_lobby_id](
            const discordpp::ClientResult& sdk_result) {
          if (!sdk_result.Successful()) {
            pending->Error("activity_call_leave_failed",
                           "Discord could not leave activity voice.");
            return;
          }
          call_.reset();
          active_lobby_id_ = 0;
          const auto payload = DisconnectedPayload(ending_lobby_id);
          pending->Success(payload);
          channel_->InvokeMethod(
              "socialActivityCallChanged",
              std::make_unique<flutter::EncodableValue>(payload));
        });
  }

  void NotifyCallState() {
    if (!call_ || active_lobby_id_ == 0) {
      return;
    }
    const auto payload = CallPayload(active_lobby_id_, *call_);
    channel_->InvokeMethod(
        "socialActivityCallChanged",
        std::make_unique<flutter::EncodableValue>(payload));
  }

  uint64_t active_lobby_id_ = 0;
  std::unique_ptr<discordpp::Call> call_;
#endif

  discordpp::Client* client_;
  flutter::MethodChannel<flutter::EncodableValue>* channel_;
};

DiscordSocialSdkCallBridge::DiscordSocialSdkCallBridge(
    discordpp::Client* client,
    flutter::MethodChannel<flutter::EncodableValue>* channel)
    : impl_(std::make_unique<Impl>(client, channel)) {}

DiscordSocialSdkCallBridge::~DiscordSocialSdkCallBridge() = default;

bool DiscordSocialSdkCallBridge::CanHandle(const std::string& method) const {
  return impl_->CanHandle(method);
}

void DiscordSocialSdkCallBridge::ResetSession() {
  impl_->ResetSession();
}

void DiscordSocialSdkCallBridge::Handle(
    const flutter::MethodCall<>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  impl_->Handle(call, std::move(result));
}
