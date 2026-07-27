import '../../domain/user_settings_repository.dart';
import '../proto/proto_message.dart';
import 'discord_user_settings_proto.dart';

/// Builds the single-group roots Discord's settings write path expects.
abstract final class DiscordUserSettingsPatch {
  /// Produces a root carrying only the groups [patch] touches.
  ///
  /// Each group is taken from [root] and edited, never rebuilt: a settings
  /// write replaces the whole group on the account, so a group assembled from
  /// the leaves Flucord happens to model would delete every other preference
  /// in it — including ones no Discord client has shipped yet.
  static ProtoMessage build(ProtoMessage root, UserSettingsPatch patch) {
    final result = ProtoMessage();
    if (patch.touchesAppearance) {
      result.setMessage(
        PreloadedUserSettingsField.appearance,
        _appearance(root, patch),
      );
    }
    if (patch.touchesTextAndImages) {
      result.setMessage(
        PreloadedUserSettingsField.textAndImages,
        _textAndImages(root, patch),
      );
    }
    if (patch.touchesNotifications) {
      result.setMessage(
        PreloadedUserSettingsField.notifications,
        _notifications(root, patch),
      );
    }
    if (patch.touchesPrivacy) {
      result.setMessage(
        PreloadedUserSettingsField.privacy,
        _privacy(root, patch),
      );
    }
    if (patch.touchesStatus) {
      result.setMessage(
        PreloadedUserSettingsField.status,
        _status(root, patch),
      );
    }
    return result;
  }

  /// Applies a partial settings root the way Discord's store does.
  ///
  /// The renderer deletes each key the partial carries before merging, so a
  /// group in the partial replaces the stored group outright instead of being
  /// deep-merged into it. Getting this wrong is invisible for scalar leaves
  /// and wrong for every repeated or map field inside a group.
  static ProtoMessage replaceGroups(
    ProtoMessage current,
    ProtoMessage partial,
  ) {
    final result = current.clone();
    for (final number in partial.fields.map((field) => field.number).toSet()) {
      result.clearField(number);
    }
    for (final field in partial.fields) {
      result.addField(field);
    }
    return result;
  }

  static ProtoMessage _group(ProtoMessage root, int number) =>
      root.messageAt(number) ?? ProtoMessage();

  static ProtoMessage _appearance(ProtoMessage root, UserSettingsPatch patch) {
    final group = _group(root, PreloadedUserSettingsField.appearance);
    if (patch.theme case final theme?) {
      group.setVarint(AppearanceField.theme, theme.wireValue);
    }
    if (patch.timestampHourCycle case final cycle?) {
      group.setVarint(AppearanceField.timestampHourCycle, cycle.wireValue);
    }
    return group;
  }

  static ProtoMessage _textAndImages(
    ProtoMessage root,
    UserSettingsPatch patch,
  ) {
    final group = _group(root, PreloadedUserSettingsField.textAndImages);
    if (patch.renderEmbeds case final value?) {
      group.setBoolWrapper(TextAndImagesField.renderEmbeds, value);
    }
    if (patch.renderReactions case final value?) {
      group.setBoolWrapper(TextAndImagesField.renderReactions, value);
    }
    if (patch.inlineAttachmentMedia case final value?) {
      group.setBoolWrapper(TextAndImagesField.inlineAttachmentMedia, value);
    }
    if (patch.inlineEmbedMedia case final value?) {
      group.setBoolWrapper(TextAndImagesField.inlineEmbedMedia, value);
    }
    if (patch.spamFilter case final value?) {
      group.setVarint(TextAndImagesField.dmSpamFilterV2, value.wireValue);
    }
    return group;
  }

  static ProtoMessage _notifications(
    ProtoMessage root,
    UserSettingsPatch patch,
  ) {
    final group = _group(root, PreloadedUserSettingsField.notifications);
    if (patch.quietMode case final value?) {
      group.setBoolWrapper(NotificationField.quietMode, value);
    }
    if (patch.notifyFriendsOnGoLive case final value?) {
      group.setBoolWrapper(NotificationField.notifyFriendsOnGoLive, value);
    }
    if (patch.friendOnlineNotifications case final value?) {
      group.setBoolWrapper(NotificationField.friendOnlineNotifications, value);
    }
    if (patch.reactionNotifications case final value?) {
      group.setVarint(NotificationField.reactionNotifications, value.wireValue);
    }
    return group;
  }

  static ProtoMessage _privacy(ProtoMessage root, UserSettingsPatch patch) {
    final group = _group(root, PreloadedUserSettingsField.privacy);
    if (patch.allowActivityPartyFriends case final value?) {
      group.setBoolWrapper(PrivacyField.allowActivityPartyFriends, value);
    }
    if (patch.allowActivityPartyVoiceChannel case final value?) {
      group.setBoolWrapper(PrivacyField.allowActivityPartyVoiceChannel, value);
    }
    if (patch.detectPlatformAccounts case final value?) {
      group.setBoolWrapper(PrivacyField.detectPlatformAccounts, value);
    }
    if (patch.showLocalTime case final value?) {
      group.setBoolWrapper(PrivacyField.showLocalTime, value);
    }
    if (patch.hideLegacyUsername case final value?) {
      group.setBoolWrapper(PrivacyField.hideLegacyUsername, value);
    }
    return group;
  }

  static ProtoMessage _status(ProtoMessage root, UserSettingsPatch patch) {
    final group = _group(root, PreloadedUserSettingsField.status);
    if (patch.showCurrentGame case final value?) {
      group.setBoolWrapper(StatusField.showCurrentGame, value);
    }
    if (patch.onlineStatus case final status?) {
      group.setStringWrapper(StatusField.status, status.wireValue);
    }
    if (patch.clearCustomStatus) {
      group.clearField(StatusField.customStatus);
      return group;
    }
    final custom = _customStatus(group, patch);
    if (custom != null) group.setMessage(StatusField.customStatus, custom);
    return group;
  }

  /// Edits the stored `CustomStatus` submessage, or null when the patch says
  /// nothing about it.
  ///
  /// The submessage is cloned from what is stored for the same reason whole
  /// groups are: setting only the text would otherwise drop the emoji and the
  /// expiry the user set from another client.
  static ProtoMessage? _customStatus(
    ProtoMessage group,
    UserSettingsPatch patch,
  ) {
    if (patch.customStatusText == null &&
        patch.customStatusEmojiName == null &&
        patch.customStatusExpiresAtMs == null) {
      return null;
    }
    final custom = group.messageAt(StatusField.customStatus) ?? ProtoMessage();
    if (patch.customStatusText case final text?) {
      custom.setString(CustomStatusField.text, text);
    }
    if (patch.customStatusEmojiName case final emoji?) {
      // An empty name is how the surface says "no emoji"; writing it as an
      // empty string would leave a present-but-blank emoji on the account.
      if (emoji.isEmpty) {
        custom
          ..clearField(CustomStatusField.emojiName)
          ..clearField(CustomStatusField.emojiId);
      } else {
        custom
          ..setString(CustomStatusField.emojiName, emoji)
          ..clearField(CustomStatusField.emojiId);
      }
    }
    if (patch.customStatusExpiresAtMs case final expiry?) {
      if (expiry <= 0) {
        custom.clearField(CustomStatusField.expiresAtMs);
      } else {
        custom.setFixed64(CustomStatusField.expiresAtMs, expiry);
      }
    }
    return custom;
  }
}
