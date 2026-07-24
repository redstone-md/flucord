#include "discord_social_sdk_chat_bridge.h"

#include "discord_social_sdk_wire.h"

#include <algorithm>
#include <cstdint>
#include <memory>
#include <string>
#include <utility>
#include <vector>

#if defined(FLUCORD_DISCORD_SOCIAL_SDK_ENABLED)
#include <discord_partner_sdk/discordpp.h>
#endif

namespace {

using discord_social_sdk_wire::Int32Argument;
using discord_social_sdk_wire::InvalidArguments;
using discord_social_sdk_wire::MethodResult;
using discord_social_sdk_wire::SnowflakeArgument;
using discord_social_sdk_wire::StringArgument;

constexpr int32_t kMaximumMessageLimit = 100;
constexpr size_t kMaximumMessageLength = 2000;

size_t Utf8CodePointCount(const std::string& value) {
  return static_cast<size_t>(std::count_if(
      value.begin(), value.end(), [](unsigned char byte) {
        return (byte & 0xC0) != 0x80;
      }));
}

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
#endif

}  // namespace

class DiscordSocialSdkChatBridge::Impl {
 public:
  Impl(discordpp::Client* client,
       flutter::MethodChannel<flutter::EncodableValue>* channel)
      : client_(client), channel_(channel) {
#if defined(FLUCORD_DISCORD_SOCIAL_SDK_ENABLED)
    client_->SetMessageCreatedCallback(
        [this](uint64_t message_id) {
          NotifyMessageChanged("created", message_id);
        });
    client_->SetMessageUpdatedCallback(
        [this](uint64_t message_id) {
          NotifyMessageChanged("updated", message_id);
        });
    client_->SetMessageDeletedCallback(
        [this](uint64_t message_id, uint64_t channel_id) {
          flutter::EncodableMap payload;
          payload[flutter::EncodableValue("message_id")] =
              flutter::EncodableValue(std::to_string(message_id));
          payload[flutter::EncodableValue("channel_id")] =
              flutter::EncodableValue(std::to_string(channel_id));
          channel_->InvokeMethod(
              "socialMessageDeleted",
              std::make_unique<flutter::EncodableValue>(payload));
        });
#endif
  }

  bool CanHandle(const std::string& method) const {
    return method == "getDmConversations" || method == "getDmMessages" ||
           method == "sendDmMessage";
  }

  void Handle(const flutter::MethodCall<>& call,
              std::unique_ptr<MethodResult> result) {
#if defined(FLUCORD_DISCORD_SOCIAL_SDK_ENABLED)
    if (client_->GetStatus() != discordpp::Client::Status::Ready) {
      result->Error("not_authenticated",
                    "Direct messages require a ready Social SDK session.");
      return;
    }
    if (call.method_name() == "getDmConversations") {
      GetConversations(std::move(result));
    } else if (call.method_name() == "getDmMessages") {
      GetMessages(call, std::move(result));
    } else {
      SendMessage(call, std::move(result));
    }
#else
    result->Error("sdk_not_bundled",
                  "The Discord Social SDK package is not linked.");
#endif
  }

 private:
#if defined(FLUCORD_DISCORD_SOCIAL_SDK_ENABLED)
  void GetConversations(std::unique_ptr<MethodResult> result) {
    auto pending = std::shared_ptr<MethodResult>(std::move(result));
    client_->GetUserMessageSummaries(
        [this, pending](
            const discordpp::ClientResult& sdk_result,
            std::vector<discordpp::UserMessageSummary> summaries) {
          if (!sdk_result.Successful()) {
            pending->Error("dm_conversations_failed",
                           "Discord rejected the DM summary request.");
            return;
          }
          flutter::EncodableList payload;
          for (const auto& summary : summaries) {
            const auto user = client_->GetUser(summary.UserId());
            const auto user_id = std::to_string(summary.UserId());
            flutter::EncodableMap item;
            item[flutter::EncodableValue("user_id")] =
                flutter::EncodableValue(user_id);
            item[flutter::EncodableValue("last_message_id")] =
                flutter::EncodableValue(
                    std::to_string(summary.LastMessageId()));
            item[flutter::EncodableValue("display_name")] =
                flutter::EncodableValue(user ? user->DisplayName() : user_id);
            item[flutter::EncodableValue("username")] =
                flutter::EncodableValue(user ? user->Username() : "");
            item[flutter::EncodableValue("status")] =
                flutter::EncodableValue(
                    user ? PresenceName(user->Status()) : "unknown");
            item[flutter::EncodableValue("is_provisional")] =
                flutter::EncodableValue(user && user->IsProvisional());
            payload.emplace_back(item);
          }
          pending->Success(flutter::EncodableValue(payload));
        });
  }

  void GetMessages(const flutter::MethodCall<>& call,
                   std::unique_ptr<MethodResult> result) {
    const auto user_id = SnowflakeArgument(call, "user_id");
    const auto requested_limit = Int32Argument(call, "limit");
    if (!user_id || !requested_limit || *requested_limit < 1) {
      InvalidArguments(std::move(result));
      return;
    }
    const auto limit = std::min(*requested_limit, kMaximumMessageLimit);
    auto pending = std::shared_ptr<MethodResult>(std::move(result));
    client_->GetUserMessagesWithLimit(
        *user_id, limit,
        [this, pending](const discordpp::ClientResult& sdk_result,
                        std::vector<discordpp::MessageHandle> messages) {
          if (!sdk_result.Successful()) {
            pending->Error("dm_messages_failed",
                           "Discord rejected the DM history request.");
            return;
          }
          flutter::EncodableList payload;
          for (const auto& message : messages) {
            const auto encoded = MessagePayload(message);
            if (encoded) {
              payload.emplace_back(*encoded);
            }
          }
          pending->Success(flutter::EncodableValue(payload));
        });
  }

  void SendMessage(const flutter::MethodCall<>& call,
                   std::unique_ptr<MethodResult> result) {
    const auto user_id = SnowflakeArgument(call, "user_id");
    const auto content = StringArgument(call, "content");
    if (!user_id || !content ||
        Utf8CodePointCount(*content) > kMaximumMessageLength) {
      InvalidArguments(std::move(result));
      return;
    }
    auto pending = std::shared_ptr<MethodResult>(std::move(result));
    client_->SendUserMessage(
        *user_id, *content,
        [pending](const discordpp::ClientResult& sdk_result,
                  uint64_t message_id) {
          if (!sdk_result.Successful()) {
            pending->Error("dm_send_failed",
                           "Discord rejected the direct message.");
            return;
          }
          flutter::EncodableMap payload;
          payload[flutter::EncodableValue("message_id")] =
              flutter::EncodableValue(std::to_string(message_id));
          pending->Success(flutter::EncodableValue(payload));
        });
  }

  std::optional<flutter::EncodableValue> MessagePayload(
      const discordpp::MessageHandle& message) const {
    const auto current_user = client_->GetCurrentUserV2();
    if (!current_user) {
      return std::nullopt;
    }
    const auto current_user_id = current_user->Id();
    const bool authored_by_current_user =
        message.AuthorId() == current_user_id;
    const auto conversation_user_id = authored_by_current_user
                                          ? message.RecipientId()
                                          : message.AuthorId();
    if (conversation_user_id == 0 ||
        (!authored_by_current_user &&
         message.RecipientId() != current_user_id)) {
      return std::nullopt;
    }
    std::string author_display_name = "Unknown user";
    if (const auto author = message.Author()) {
      author_display_name = author->DisplayName();
    }
    flutter::EncodableMap payload;
    payload[flutter::EncodableValue("id")] =
        flutter::EncodableValue(std::to_string(message.Id()));
    payload[flutter::EncodableValue("conversation_user_id")] =
        flutter::EncodableValue(std::to_string(conversation_user_id));
    payload[flutter::EncodableValue("author_id")] =
        flutter::EncodableValue(std::to_string(message.AuthorId()));
    payload[flutter::EncodableValue("recipient_id")] =
        flutter::EncodableValue(std::to_string(message.RecipientId()));
    payload[flutter::EncodableValue("author_display_name")] =
        flutter::EncodableValue(author_display_name);
    payload[flutter::EncodableValue("content")] =
        flutter::EncodableValue(message.Content());
    payload[flutter::EncodableValue("sent_timestamp")] =
        flutter::EncodableValue(
            static_cast<int64_t>(message.SentTimestamp()));
    payload[flutter::EncodableValue("edited_timestamp")] =
        flutter::EncodableValue(
            static_cast<int64_t>(message.EditedTimestamp()));
    payload[flutter::EncodableValue("authored_by_current_user")] =
        flutter::EncodableValue(authored_by_current_user);
    return flutter::EncodableValue(payload);
  }

  void NotifyMessageChanged(const std::string& type, uint64_t message_id) {
    const auto message = client_->GetMessageHandle(message_id);
    if (!message) {
      return;
    }
    const auto encoded = MessagePayload(*message);
    if (!encoded) {
      return;
    }
    flutter::EncodableMap payload;
    payload[flutter::EncodableValue("type")] =
        flutter::EncodableValue(type);
    payload[flutter::EncodableValue("message")] = *encoded;
    channel_->InvokeMethod(
        "socialMessageChanged",
        std::make_unique<flutter::EncodableValue>(payload));
  }
#endif

  discordpp::Client* client_;
  flutter::MethodChannel<flutter::EncodableValue>* channel_;
};

DiscordSocialSdkChatBridge::DiscordSocialSdkChatBridge(
    discordpp::Client* client,
    flutter::MethodChannel<flutter::EncodableValue>* channel)
    : impl_(std::make_unique<Impl>(client, channel)) {}

DiscordSocialSdkChatBridge::~DiscordSocialSdkChatBridge() = default;

bool DiscordSocialSdkChatBridge::CanHandle(const std::string& method) const {
  return impl_->CanHandle(method);
}

void DiscordSocialSdkChatBridge::Handle(
    const flutter::MethodCall<>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  impl_->Handle(call, std::move(result));
}
