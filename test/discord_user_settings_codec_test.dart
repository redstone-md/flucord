import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_user_settings_patch.dart';
import 'package:flucord/src/data/discord/discord_user_settings_proto.dart';
import 'package:flucord/src/data/proto/proto_message.dart';
import 'package:flucord/src/data/proto/proto_wire.dart';
import 'package:flucord/src/domain/user_settings.dart';
import 'package:flucord/src/domain/user_settings_repository.dart';

void main() {
  group('base64 envelope', () {
    test('accepts the URL-safe alphabet, whitespace and missing padding', () {
      final standard = base64.encode(const [251, 255, 190, 1]);
      final relaxed = standard
          .replaceAll('+', '-')
          .replaceAll('/', '_')
          .replaceAll('=', '');

      expect(
        DiscordUserSettingsProto.decodeBase64('  $relaxed\n'),
        orderedEquals(const [251, 255, 190, 1]),
      );
    });

    test('rejects a payload that cannot be base64 at all', () {
      expect(
        () => DiscordUserSettingsProto.decodeBase64('AAAAA'),
        throwsA(
          isA<ProtoFormatException>().having(
            (error) => error.message,
            'message',
            contains('trailing byte'),
          ),
        ),
      );
      expect(
        () => DiscordUserSettingsProto.decodeBase64('!!!!'),
        throwsA(isA<ProtoFormatException>()),
      );
    });

    test('encodes with the standard alphabet', () {
      expect(
        DiscordUserSettingsProto.encodeBase64(
          Uint8List.fromList(const [251, 255, 190]),
        ),
        base64.encode(const [251, 255, 190]),
      );
    });

    test('decodes a root from its envelope', () {
      final root = ProtoMessage()
        ..setMessage(
          PreloadedUserSettingsField.versions,
          ProtoMessage()..setVarint(VersionsField.dataVersion, 12),
        );
      final envelope = DiscordUserSettingsProto.encodeBase64(root.encode());

      expect(
        DiscordUserSettingsProto.read(
          DiscordUserSettingsProto.decodeRoot(envelope),
        ).dataVersion,
        12,
      );
    });
  });

  group('reading PreloadedUserSettings', () {
    test('falls back to the documented defaults when nothing is stored', () {
      final settings = DiscordUserSettingsProto.read(ProtoMessage());

      expect(settings.appearance.theme, UserSettingsTheme.unset);
      expect(settings.appearance.timestampHourCycle, TimestampHourCycle.auto);
      expect(settings.appearance.density, UserInterfaceDensity.unset);
      expect(settings.messageDisplay.rendersEmbeds, isTrue);
      expect(settings.messageDisplay.rendersReactions, isTrue);
      expect(settings.messageDisplay.rendersAttachmentMedia, isTrue);
      expect(settings.messageDisplay.rendersEmbedMedia, isTrue);
      expect(settings.messageDisplay.isCompact, isFalse);
      expect(
        settings.messageDisplay.spamFilter,
        DirectMessageSpamFilter.defaultUnset,
      );
      expect(settings.notifications.isQuiet, isFalse);
      expect(settings.notifications.showsInAppNotifications, isTrue);
      expect(settings.notifications.notifiesFriendsOnGoLive, isTrue);
      expect(settings.notifications.notifiesOnFriendOnline, isTrue);
      expect(
        settings.notifications.reactionNotifications,
        ReactionNotifications.enabled,
      );
      expect(settings.privacy.allowsActivityPartyFriends, isTrue);
      expect(settings.privacy.allowsActivityPartyVoiceChannel, isTrue);
      expect(settings.privacy.detectsPlatformAccounts, isFalse);
      expect(settings.privacy.showsLocalTime, isFalse);
      expect(settings.privacy.hidesLegacyUsername, isFalse);
      expect(settings.privacy.defaultGuildsRestricted, isFalse);
      expect(settings.localization.locale, isNull);
      expect(settings.localization.timezoneName, isNull);
      expect(settings.localization.timezoneOffsetMinutes, isNull);
      expect(settings.status.status, isNull);
      expect(settings.status.showsCurrentGame, isTrue);
      expect(settings.status.hasCustomStatus, isFalse);
      expect(settings.status.statusExpiresAtMs, 0);
      expect(settings.dataVersion, 0);
    });

    test('reads every group Flucord models', () {
      final settings = DiscordUserSettingsProto.read(_populatedRoot());

      expect(settings.appearance.theme, UserSettingsTheme.midnight);
      expect(settings.appearance.developerMode, isTrue);
      expect(settings.appearance.density, UserInterfaceDensity.compact);
      expect(settings.appearance.timestampHourCycle, TimestampHourCycle.hour12);
      expect(settings.appearance.darkSidebar, isTrue);

      expect(settings.messageDisplay.renderEmbeds, isFalse);
      expect(settings.messageDisplay.renderReactions, isFalse);
      expect(settings.messageDisplay.inlineAttachmentMedia, isFalse);
      expect(settings.messageDisplay.inlineEmbedMedia, isFalse);
      expect(settings.messageDisplay.gifAutoPlay, isFalse);
      expect(settings.messageDisplay.animateEmoji, isFalse);
      expect(settings.messageDisplay.compact, isTrue);
      expect(settings.messageDisplay.convertEmoticons, isFalse);
      expect(settings.messageDisplay.enableTextToSpeechCommand, isFalse);
      expect(settings.messageDisplay.showCommandSuggestions, isFalse);
      expect(
        settings.messageDisplay.spamFilter,
        DirectMessageSpamFilter.friendsAndNonFriends,
      );

      expect(settings.notifications.isQuiet, isTrue);
      expect(settings.notifications.showsInAppNotifications, isFalse);
      expect(settings.notifications.notifiesFriendsOnGoLive, isFalse);
      expect(settings.notifications.notifiesOnFriendOnline, isFalse);
      expect(
        settings.notifications.reactionNotifications,
        ReactionNotifications.onlyDirectMessages,
      );

      expect(settings.privacy.allowsActivityPartyFriends, isFalse);
      expect(settings.privacy.allowsActivityPartyVoiceChannel, isFalse);
      expect(settings.privacy.defaultGuildsRestricted, isTrue);
      expect(settings.privacy.detectsPlatformAccounts, isTrue);
      expect(settings.privacy.showsLocalTime, isTrue);
      expect(settings.privacy.hidesLegacyUsername, isTrue);

      expect(settings.localization.locale, 'en-GB');
      expect(settings.localization.timezoneName, 'Europe/London');
      expect(settings.localization.timezoneOffsetMinutes, 60);

      expect(settings.status.status, 'dnd');
      expect(settings.status.customStatusText, 'shipping');
      expect(settings.status.customStatusEmojiName, 'rocket');
      expect(settings.status.customStatusExpiresAtMs, 1700000000000);
      expect(settings.status.showsCurrentGame, isFalse);
      expect(settings.status.statusExpiresAtMs, 1800000000000);
      expect(settings.status.hasCustomStatus, isTrue);
      expect(settings.dataVersion, 41);
    });

    test('maps every enum value the spec establishes', () {
      expect(UserSettingsTheme.fromWire(1), UserSettingsTheme.dark);
      expect(UserSettingsTheme.fromWire(2), UserSettingsTheme.light);
      expect(UserSettingsTheme.fromWire(3), UserSettingsTheme.darker);
      expect(UserSettingsTheme.fromWire(4), UserSettingsTheme.midnight);
      expect(UserSettingsTheme.fromWire(99), UserSettingsTheme.unset);
      expect(UserSettingsTheme.dark.isRenderable, isTrue);
      expect(UserSettingsTheme.midnight.isRenderable, isFalse);

      expect(TimestampHourCycle.fromWire(1), TimestampHourCycle.hour12);
      expect(TimestampHourCycle.fromWire(2), TimestampHourCycle.hour23);
      expect(TimestampHourCycle.fromWire(null), TimestampHourCycle.auto);

      expect(UserInterfaceDensity.fromWire(1), UserInterfaceDensity.compact);
      expect(UserInterfaceDensity.fromWire(2), UserInterfaceDensity.cozy);
      expect(UserInterfaceDensity.fromWire(3), UserInterfaceDensity.responsive);
      expect(UserInterfaceDensity.fromWire(4), UserInterfaceDensity.standard);
      expect(UserInterfaceDensity.fromWire(0), UserInterfaceDensity.unset);

      expect(
        DirectMessageSpamFilter.fromWire(1),
        DirectMessageSpamFilter.disabled,
      );
      expect(
        DirectMessageSpamFilter.fromWire(2),
        DirectMessageSpamFilter.nonFriends,
      );
      expect(
        DirectMessageSpamFilter.fromWire(3),
        DirectMessageSpamFilter.friendsAndNonFriends,
      );
      expect(
        DirectMessageSpamFilter.fromWire(0),
        DirectMessageSpamFilter.defaultUnset,
      );

      expect(
        ReactionNotifications.fromWire(1),
        ReactionNotifications.onlyDirectMessages,
      );
      expect(ReactionNotifications.fromWire(2), ReactionNotifications.disabled);
      expect(ReactionNotifications.fromWire(0), ReactionNotifications.enabled);
    });
  });

  group('building a write', () {
    test('carries only the groups the patch touches', () {
      final patch = DiscordUserSettingsPatch.build(
        _populatedRoot(),
        const UserSettingsPatch(theme: UserSettingsTheme.light),
      );

      expect(
        patch.fields.map((field) => field.number),
        orderedEquals([PreloadedUserSettingsField.appearance]),
      );
    });

    test('keeps the rest of a group it edits', () {
      final patch = DiscordUserSettingsPatch.build(
        _populatedRoot(),
        const UserSettingsPatch(
          theme: UserSettingsTheme.light,
          timestampHourCycle: TimestampHourCycle.hour23,
        ),
      );
      final appearance = patch.messageAt(
        PreloadedUserSettingsField.appearance,
      )!;

      expect(appearance.varintAt(AppearanceField.theme), 2);
      expect(appearance.varintAt(AppearanceField.timestampHourCycle), 2);
      // Untouched leaves and the field Flucord does not model both survive.
      expect(appearance.boolAt(AppearanceField.developerMode), isTrue);
      expect(appearance.stringAt(_unmodelledField), 'keep me');
    });

    test('writes every editable leaf into its own group', () {
      final patch = DiscordUserSettingsPatch.build(
        ProtoMessage(),
        const UserSettingsPatch(
          renderEmbeds: false,
          renderReactions: false,
          inlineAttachmentMedia: false,
          inlineEmbedMedia: false,
          spamFilter: DirectMessageSpamFilter.nonFriends,
          quietMode: true,
          notifyFriendsOnGoLive: false,
          friendOnlineNotifications: false,
          reactionNotifications: ReactionNotifications.disabled,
          allowActivityPartyFriends: false,
          allowActivityPartyVoiceChannel: false,
          detectPlatformAccounts: true,
          showLocalTime: true,
          hideLegacyUsername: true,
          showCurrentGame: false,
          customStatusText: 'heads down',
        ),
      );
      final settings = DiscordUserSettingsProto.read(patch);

      expect(settings.messageDisplay.renderEmbeds, isFalse);
      expect(settings.messageDisplay.renderReactions, isFalse);
      expect(settings.messageDisplay.inlineAttachmentMedia, isFalse);
      expect(settings.messageDisplay.inlineEmbedMedia, isFalse);
      expect(
        settings.messageDisplay.spamFilter,
        DirectMessageSpamFilter.nonFriends,
      );
      expect(settings.notifications.isQuiet, isTrue);
      expect(settings.notifications.notifiesFriendsOnGoLive, isFalse);
      expect(settings.notifications.notifiesOnFriendOnline, isFalse);
      expect(
        settings.notifications.reactionNotifications,
        ReactionNotifications.disabled,
      );
      expect(settings.privacy.allowsActivityPartyFriends, isFalse);
      expect(settings.privacy.allowsActivityPartyVoiceChannel, isFalse);
      expect(settings.privacy.detectsPlatformAccounts, isTrue);
      expect(settings.privacy.showsLocalTime, isTrue);
      expect(settings.privacy.hidesLegacyUsername, isTrue);
      expect(settings.status.showsCurrentGame, isFalse);
      expect(settings.status.customStatusText, 'heads down');
    });

    test('editing the custom status text keeps its emoji and expiry', () {
      final patch = DiscordUserSettingsPatch.build(
        _populatedRoot(),
        const UserSettingsPatch(customStatusText: 'back soon'),
      );
      final status = DiscordUserSettingsProto.read(patch).status;

      expect(status.customStatusText, 'back soon');
      expect(status.customStatusEmojiName, 'rocket');
      expect(status.customStatusExpiresAtMs, 1700000000000);
    });

    test('clearing the custom status drops the whole submessage', () {
      final patch = DiscordUserSettingsPatch.build(
        _populatedRoot(),
        const UserSettingsPatch(
          clearCustomStatus: true,
          customStatusText: 'ignored',
          showCurrentGame: true,
        ),
      );
      final status = DiscordUserSettingsProto.read(patch).status;

      expect(status.hasCustomStatus, isFalse);
      expect(status.customStatusExpiresAtMs, 0);
      expect(status.showsCurrentGame, isTrue);
    });

    test('reports which groups a patch touches', () {
      const empty = UserSettingsPatch();

      expect(empty.isEmpty, isTrue);
      expect(empty.touchesAppearance, isFalse);
      expect(empty.touchesTextAndImages, isFalse);
      expect(empty.touchesNotifications, isFalse);
      expect(empty.touchesPrivacy, isFalse);
      expect(empty.touchesStatus, isFalse);
      expect(const UserSettingsPatch(clearCustomStatus: true).isEmpty, isFalse);
    });
  });

  group('merge semantics', () {
    test('a partial replaces a whole group instead of merging into it', () {
      final current = _populatedRoot();
      final partial = ProtoMessage()
        ..setMessage(
          PreloadedUserSettingsField.appearance,
          ProtoMessage()..setVarint(AppearanceField.theme, 2),
        );

      final merged = DiscordUserSettingsPatch.replaceGroups(current, partial);
      final settings = DiscordUserSettingsProto.read(merged);

      expect(settings.appearance.theme, UserSettingsTheme.light);
      // Everything else in the replaced group is gone, exactly as Discord's
      // own store leaves it.
      expect(settings.appearance.developerMode, isFalse);
      expect(settings.appearance.timestampHourCycle, TimestampHourCycle.auto);
      // Groups the partial never mentioned are untouched.
      expect(settings.privacy.showsLocalTime, isTrue);
      expect(settings.status.customStatusText, 'shipping');
    });

    test('keeps repeated occurrences the partial carries', () {
      final partial = ProtoMessage()..setVarint(1, 1);
      partial.addField(const ProtoField(1, ProtoVarint(2)));

      final merged = DiscordUserSettingsPatch.replaceGroups(
        ProtoMessage()..setVarint(1, 9),
        partial,
      );

      expect(merged.fields, hasLength(2));
      expect(merged.varintAt(1), 2);
    });
  });
}

/// A field number no Discord client documents, standing in for whatever the
/// server may add after this build shipped.
const _unmodelledField = 4242;

ProtoMessage _populatedRoot() => ProtoMessage()
  ..setMessage(
    PreloadedUserSettingsField.versions,
    ProtoMessage()
      ..setVarint(VersionsField.clientVersion, 21)
      ..setVarint(VersionsField.dataVersion, 41),
  )
  ..setMessage(
    PreloadedUserSettingsField.appearance,
    ProtoMessage()
      ..setVarint(AppearanceField.theme, 4)
      ..setBool(AppearanceField.developerMode, true)
      ..setVarint(AppearanceField.timestampHourCycle, 1)
      ..setVarint(AppearanceField.uiDensity, 1)
      ..setBool(AppearanceField.darkSidebar, true)
      ..setString(_unmodelledField, 'keep me'),
  )
  ..setMessage(
    PreloadedUserSettingsField.textAndImages,
    ProtoMessage()
      ..setBoolWrapper(TextAndImagesField.showCommandSuggestions, false)
      ..setBoolWrapper(TextAndImagesField.inlineAttachmentMedia, false)
      ..setBoolWrapper(TextAndImagesField.inlineEmbedMedia, false)
      ..setBoolWrapper(TextAndImagesField.gifAutoPlay, false)
      ..setBoolWrapper(TextAndImagesField.renderEmbeds, false)
      ..setBoolWrapper(TextAndImagesField.renderReactions, false)
      ..setBoolWrapper(TextAndImagesField.animateEmoji, false)
      ..setBoolWrapper(TextAndImagesField.enableTtsCommand, false)
      ..setBoolWrapper(TextAndImagesField.messageDisplayCompact, true)
      ..setBoolWrapper(TextAndImagesField.convertEmoticons, false)
      ..setVarint(TextAndImagesField.dmSpamFilterV2, 3),
  )
  ..setMessage(
    PreloadedUserSettingsField.notifications,
    ProtoMessage()
      ..setBoolWrapper(NotificationField.showInAppNotifications, false)
      ..setBoolWrapper(NotificationField.notifyFriendsOnGoLive, false)
      ..setBoolWrapper(NotificationField.quietMode, true)
      ..setVarint(NotificationField.reactionNotifications, 1)
      ..setBoolWrapper(NotificationField.friendOnlineNotifications, false),
  )
  ..setMessage(
    PreloadedUserSettingsField.privacy,
    ProtoMessage()
      ..setBoolWrapper(PrivacyField.allowActivityPartyFriends, false)
      ..setBoolWrapper(PrivacyField.allowActivityPartyVoiceChannel, false)
      ..setBool(PrivacyField.defaultGuildsRestricted, true)
      ..setBoolWrapper(PrivacyField.detectPlatformAccounts, true)
      ..setBoolWrapper(PrivacyField.hideLegacyUsername, true)
      ..setBoolWrapper(PrivacyField.showLocalTime, true),
  )
  ..setMessage(
    PreloadedUserSettingsField.localization,
    ProtoMessage()
      ..setStringWrapper(LocalizationField.locale, 'en-GB')
      ..setIntWrapper(LocalizationField.timezoneOffset, 60)
      ..setStringWrapper(LocalizationField.timezoneName, 'Europe/London'),
  )
  ..setMessage(
    PreloadedUserSettingsField.status,
    ProtoMessage()
      ..setStringWrapper(StatusField.status, 'dnd')
      ..setMessage(
        StatusField.customStatus,
        ProtoMessage()
          ..setString(CustomStatusField.text, 'shipping')
          ..setString(CustomStatusField.emojiName, 'rocket')
          ..setField(
            CustomStatusField.expiresAtMs,
            const ProtoFixed64(1700000000000),
          ),
      )
      ..setBoolWrapper(StatusField.showCurrentGame, false)
      ..setField(
        StatusField.statusExpiresAtMs,
        const ProtoFixed64(1800000000000),
      ),
  );
