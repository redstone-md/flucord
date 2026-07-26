import 'dart:convert';
import 'dart:typed_data';

import '../../domain/user_settings.dart';
import '../proto/proto_message.dart';
import '../proto/proto_wire.dart';

/// The numeric settings types `/users/@me/settings-proto/{type}` is keyed by.
abstract final class DiscordSettingsProtoType {
  /// `PreloadedUserSettings`, the blob `READY` carries.
  static const preloadedUserSettings = 1;

  /// `FrecencyUserSettings`. Flucord registers no codec for it, so a dispatch
  /// naming this type is ignored rather than misread as the preloaded blob.
  static const frecencyAndFavorites = 2;
}

/// Field numbers inside `PreloadedUserSettings`.
abstract final class PreloadedUserSettingsField {
  static const versions = 1;
  static const textAndImages = 6;
  static const notifications = 7;
  static const privacy = 8;
  static const status = 11;
  static const localization = 12;
  static const appearance = 13;
}

abstract final class VersionsField {
  static const clientVersion = 1;
  static const dataVersion = 3;
}

abstract final class AppearanceField {
  static const theme = 1;
  static const developerMode = 2;
  static const timestampHourCycle = 9;
  static const uiDensity = 12;
  static const darkSidebar = 15;
}

abstract final class TextAndImagesField {
  static const showCommandSuggestions = 8;
  static const inlineAttachmentMedia = 9;
  static const inlineEmbedMedia = 10;
  static const gifAutoPlay = 11;
  static const renderEmbeds = 12;
  static const renderReactions = 13;
  static const animateEmoji = 14;
  static const enableTtsCommand = 16;
  static const messageDisplayCompact = 17;
  static const convertEmoticons = 21;
  static const dmSpamFilterV2 = 27;
}

abstract final class NotificationField {
  static const showInAppNotifications = 1;
  static const notifyFriendsOnGoLive = 2;
  static const quietMode = 5;
  static const reactionNotifications = 7;
  static const friendOnlineNotifications = 12;
}

abstract final class PrivacyField {
  static const allowActivityPartyFriends = 1;
  static const allowActivityPartyVoiceChannel = 2;
  static const defaultGuildsRestricted = 4;
  static const detectPlatformAccounts = 8;
  static const hideLegacyUsername = 22;
  static const showLocalTime = 31;
}

abstract final class StatusField {
  static const status = 1;
  static const customStatus = 2;
  static const showCurrentGame = 3;
  static const statusExpiresAtMs = 4;
}

abstract final class CustomStatusField {
  static const text = 1;
  static const emojiName = 3;
  static const expiresAtMs = 4;
}

abstract final class LocalizationField {
  static const locale = 1;
  static const timezoneOffset = 2;
  static const timezoneName = 3;
}

/// Turns the wire form of `PreloadedUserSettings` into what Flucord models.
abstract final class DiscordUserSettingsProto {
  /// Decodes the base64 envelope Discord wraps every settings blob in.
  ///
  /// The renderer's decoder also accepts the URL-safe alphabet and ignores
  /// whitespace, and Dart's own decoder is stricter about padding than the
  /// server is about producing it, so both are normalised here rather than
  /// left to fail a settings load over a cosmetic difference.
  static Uint8List decodeBase64(String value) {
    final buffer = StringBuffer();
    for (final unit in value.codeUnits) {
      const whitespace = {0x20, 0x09, 0x0a, 0x0d};
      if (whitespace.contains(unit)) continue;
      buffer.writeCharCode(unit);
    }
    var text = buffer.toString();
    final remainder = text.length % 4;
    if (remainder == 1) {
      throw const ProtoFormatException('Base64 payload has a trailing byte');
    }
    if (remainder != 0) {
      text = text.padRight(text.length + (4 - remainder), '=');
    }
    try {
      return base64.decode(text);
    } on FormatException catch (error) {
      throw ProtoFormatException(
        'Base64 payload is malformed: ${error.message}',
      );
    }
  }

  static String encodeBase64(Uint8List value) => base64.encode(value);

  static ProtoMessage decodeRoot(String base64Text) =>
      ProtoMessage.decode(decodeBase64(base64Text));

  static UserSettings read(ProtoMessage root) => UserSettings(
    appearance: _appearance(
      root.messageAt(PreloadedUserSettingsField.appearance),
    ),
    messageDisplay: _messageDisplay(
      root.messageAt(PreloadedUserSettingsField.textAndImages),
    ),
    notifications: _notifications(
      root.messageAt(PreloadedUserSettingsField.notifications),
    ),
    privacy: _privacy(root.messageAt(PreloadedUserSettingsField.privacy)),
    localization: _localization(
      root.messageAt(PreloadedUserSettingsField.localization),
    ),
    status: _status(root.messageAt(PreloadedUserSettingsField.status)),
    dataVersion:
        root
            .messageAt(PreloadedUserSettingsField.versions)
            ?.varintAt(VersionsField.dataVersion) ??
        0,
  );

  static AppearancePreferences _appearance(ProtoMessage? group) {
    if (group == null) return const AppearancePreferences();
    return AppearancePreferences(
      theme: UserSettingsTheme.fromWire(group.varintAt(AppearanceField.theme)),
      developerMode: group.boolAt(AppearanceField.developerMode) ?? false,
      density: UserInterfaceDensity.fromWire(
        group.varintAt(AppearanceField.uiDensity),
      ),
      timestampHourCycle: TimestampHourCycle.fromWire(
        group.varintAt(AppearanceField.timestampHourCycle),
      ),
      darkSidebar: group.boolAt(AppearanceField.darkSidebar) ?? false,
    );
  }

  static MessageDisplayPreferences _messageDisplay(ProtoMessage? group) {
    if (group == null) return const MessageDisplayPreferences();
    return MessageDisplayPreferences(
      renderEmbeds: group.boolWrapperAt(TextAndImagesField.renderEmbeds),
      renderReactions: group.boolWrapperAt(TextAndImagesField.renderReactions),
      inlineAttachmentMedia: group.boolWrapperAt(
        TextAndImagesField.inlineAttachmentMedia,
      ),
      inlineEmbedMedia: group.boolWrapperAt(
        TextAndImagesField.inlineEmbedMedia,
      ),
      gifAutoPlay: group.boolWrapperAt(TextAndImagesField.gifAutoPlay),
      animateEmoji: group.boolWrapperAt(TextAndImagesField.animateEmoji),
      compact: group.boolWrapperAt(TextAndImagesField.messageDisplayCompact),
      convertEmoticons: group.boolWrapperAt(
        TextAndImagesField.convertEmoticons,
      ),
      enableTextToSpeechCommand: group.boolWrapperAt(
        TextAndImagesField.enableTtsCommand,
      ),
      showCommandSuggestions: group.boolWrapperAt(
        TextAndImagesField.showCommandSuggestions,
      ),
      spamFilter: DirectMessageSpamFilter.fromWire(
        group.varintAt(TextAndImagesField.dmSpamFilterV2),
      ),
    );
  }

  static NotificationPreferences _notifications(ProtoMessage? group) {
    if (group == null) return const NotificationPreferences();
    return NotificationPreferences(
      quietMode: group.boolWrapperAt(NotificationField.quietMode),
      showInAppNotifications: group.boolWrapperAt(
        NotificationField.showInAppNotifications,
      ),
      notifyFriendsOnGoLive: group.boolWrapperAt(
        NotificationField.notifyFriendsOnGoLive,
      ),
      friendOnlineNotifications: group.boolWrapperAt(
        NotificationField.friendOnlineNotifications,
      ),
      reactionNotifications: ReactionNotifications.fromWire(
        group.varintAt(NotificationField.reactionNotifications),
      ),
    );
  }

  static PrivacyPreferences _privacy(ProtoMessage? group) {
    if (group == null) return const PrivacyPreferences();
    return PrivacyPreferences(
      allowActivityPartyFriends: group.boolWrapperAt(
        PrivacyField.allowActivityPartyFriends,
      ),
      allowActivityPartyVoiceChannel: group.boolWrapperAt(
        PrivacyField.allowActivityPartyVoiceChannel,
      ),
      defaultGuildsRestricted:
          group.boolAt(PrivacyField.defaultGuildsRestricted) ?? false,
      detectPlatformAccounts: group.boolWrapperAt(
        PrivacyField.detectPlatformAccounts,
      ),
      showLocalTime: group.boolWrapperAt(PrivacyField.showLocalTime),
      hideLegacyUsername: group.boolWrapperAt(PrivacyField.hideLegacyUsername),
    );
  }

  static LocalizationPreferences _localization(ProtoMessage? group) {
    if (group == null) return const LocalizationPreferences();
    return LocalizationPreferences(
      locale: group.stringWrapperAt(LocalizationField.locale),
      timezoneName: group.stringWrapperAt(LocalizationField.timezoneName),
      timezoneOffsetMinutes: group.intWrapperAt(
        LocalizationField.timezoneOffset,
      ),
    );
  }

  static StatusPreferences _status(ProtoMessage? group) {
    if (group == null) return const StatusPreferences();
    final custom = group.messageAt(StatusField.customStatus);
    return StatusPreferences(
      status: group.stringWrapperAt(StatusField.status),
      customStatusText: custom?.stringAt(CustomStatusField.text),
      customStatusEmojiName: custom?.stringAt(CustomStatusField.emojiName),
      customStatusExpiresAtMs:
          custom?.fixed64At(CustomStatusField.expiresAtMs) ?? 0,
      showCurrentGame: group.boolWrapperAt(StatusField.showCurrentGame),
      statusExpiresAtMs: group.fixed64At(StatusField.statusExpiresAtMs) ?? 0,
    );
  }
}
