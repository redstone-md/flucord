import 'package:flucord/src/data/discord/discord_cdn.dart';
import 'package:flucord/src/data/discord/discord_desktop_gateway_protocol.dart';
import 'package:flucord/src/data/discord/discord_desktop_profile.dart';
import 'package:flucord/src/data/discord/discord_user_settings_patch.dart';
import 'package:flucord/src/data/discord/discord_user_settings_proto.dart';
import 'package:flucord/src/data/proto/proto_message.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/user_settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';

DiscordDesktopGatewayProtocol _protocol() => DiscordDesktopGatewayProtocol(
  token: 'token',
  properties: const {'os': 'Windows'},
  profile: DiscordDesktopProtocolProfile.installedStable20260725,
);

void main() {
  group('gateway frames', () {
    test('opcode 3 carries exactly the four documented keys', () {
      final frame = _protocol().presenceUpdate(const {
        'status': 'dnd',
        'since': 0,
        'activities': <Object?>[],
        'afk': false,
      });

      expect(frame.opcode, DiscordDesktopGatewayOpcode.presenceUpdate);
      expect(frame.toJson(), {
        'op': 3,
        'd': {
          'status': 'dnd',
          'since': 0,
          'activities': <Object?>[],
          'afk': false,
        },
      });
    });

    test('the presence sent last is the one the next IDENTIFY carries', () {
      final protocol = _protocol();
      expect(protocol.identify().toJson(), containsPair('d', isA<Map>()));
      expect(
        (protocol.identify().data! as Map<String, Object?>)['presence'],
        isEmpty,
      );

      protocol.presenceUpdate(const {'status': 'invisible'});

      final identify = protocol.identify().data! as Map<String, Object?>;
      expect(identify['presence'], {'status': 'invisible'});
    });

    test(
      'a dispatch whose payload is a bare array still reaches a consumer',
      () {
        final actions = _protocol().accept(const {
          'op': 0,
          't': 'SESSIONS_REPLACE',
          'd': [
            {'session_id': 'desktop'},
          ],
        });

        final dispatch = actions.single as DiscordDesktopGatewayDispatch;
        expect(dispatch.name, 'SESSIONS_REPLACE');
        expect(
          dispatch.data[DiscordDesktopGatewayDispatch.arrayPayloadKey],
          hasLength(1),
        );
      },
    );

    test('a dispatch with a payload of neither shape is dropped', () {
      expect(
        _protocol().accept(const {'op': 0, 't': 'WEIRD', 'd': 7}),
        isEmpty,
      );
      expect(_protocol().accept(const {'op': 0, 't': 7, 'd': null}), isEmpty);
    });
  });

  group('activity artwork', () {
    test('resolves the three addressable asset forms', () {
      expect(
        DiscordCdn.activityAsset(
          'abc123',
          applicationId: '987654321098765432',
          size: 256,
        ),
        'https://cdn.discordapp.com/app-assets/987654321098765432/abc123.png'
        '?size=256',
      );
      expect(
        DiscordCdn.activityAsset('spotify:cover'),
        'https://i.scdn.co/image/cover',
      );
      expect(
        DiscordCdn.activityAsset('mp:external/a/b.png'),
        'https://media.discordapp.net/external/a/b.png',
      );
    });

    test('refuses to guess a host it does not know', () {
      expect(DiscordCdn.activityAsset(null), isNull);
      expect(DiscordCdn.activityAsset(''), isNull);
      expect(DiscordCdn.activityAsset('mp:'), isNull);
      expect(DiscordCdn.activityAsset('spotify:'), isNull);
      expect(DiscordCdn.activityAsset('twitch:someone'), isNull);
      expect(DiscordCdn.activityAsset('abc123'), isNull);
      expect(DiscordCdn.activityAsset('abc123', applicationId: ''), isNull);
    });

    test('refuses a size the CDN does not serve', () {
      expect(
        () => DiscordCdn.activityAsset(
          'abc',
          applicationId: '987654321098765432',
          size: 100,
        ),
        throwsArgumentError,
      );
    });
  });

  group('settings proto', () {
    test('reads the AFK timeout the idle machine needs', () {
      final root = ProtoMessage()
        ..setMessage(
          PreloadedUserSettingsField.voiceAndVideo,
          ProtoMessage()..setIntWrapper(VoiceAndVideoField.afkTimeout, 300),
        );

      expect(
        DiscordUserSettingsProto.read(root).voiceAndVideo.afkTimeoutSeconds,
        300,
      );
      expect(
        DiscordUserSettingsProto.read(ProtoMessage()).voiceAndVideo.afkTimeout,
        60,
      );
    });

    test('reads a custom emoji id, and treats zero as unset', () {
      ProtoMessage rootWith(int emojiId) => ProtoMessage()
        ..setMessage(
          PreloadedUserSettingsField.status,
          ProtoMessage()..setMessage(
            StatusField.customStatus,
            ProtoMessage()
              ..setString(CustomStatusField.emojiName, 'shipit')
              ..setFixed64(CustomStatusField.emojiId, emojiId),
          ),
        );

      expect(
        DiscordUserSettingsProto.read(
          rootWith(123456789012345678),
        ).status.customStatusEmojiId,
        '123456789012345678',
      );
      expect(
        DiscordUserSettingsProto.read(rootWith(0)).status.customStatusEmojiId,
        isNull,
      );
    });

    test('writes the chosen status into the status group', () {
      final patch = DiscordUserSettingsPatch.build(
        ProtoMessage(),
        const UserSettingsPatch(onlineStatus: Presence.doNotDisturb),
      );

      expect(
        patch
            .messageAt(PreloadedUserSettingsField.status)!
            .stringWrapperAt(StatusField.status),
        'dnd',
      );
    });

    test('edits the stored custom status instead of rebuilding it', () {
      final root = ProtoMessage()
        ..setMessage(
          PreloadedUserSettingsField.status,
          ProtoMessage()..setMessage(
            StatusField.customStatus,
            ProtoMessage()
              ..setString(CustomStatusField.text, 'Old')
              ..setFixed64(CustomStatusField.expiresAtMs, 5)
              // A leaf Flucord does not model, which must survive the edit.
              ..setFixed64(5, 99),
          ),
        );

      final custom =
          DiscordUserSettingsPatch.build(
                root,
                const UserSettingsPatch(customStatusText: 'New'),
              )
              .messageAt(PreloadedUserSettingsField.status)!
              .messageAt(StatusField.customStatus)!;

      expect(custom.stringAt(CustomStatusField.text), 'New');
      expect(custom.fixed64At(CustomStatusField.expiresAtMs), 5);
      expect(custom.fixed64At(5), 99);
    });

    test('writes an emoji and an expiry, and clears both when blanked', () {
      final set =
          DiscordUserSettingsPatch.build(
                ProtoMessage(),
                const UserSettingsPatch(
                  customStatusEmojiName: '🛠',
                  customStatusExpiresAtMs: 1770000000000,
                ),
              )
              .messageAt(PreloadedUserSettingsField.status)!
              .messageAt(StatusField.customStatus)!;
      expect(set.stringAt(CustomStatusField.emojiName), '🛠');
      expect(set.fixed64At(CustomStatusField.expiresAtMs), 1770000000000);

      final cleared =
          DiscordUserSettingsPatch.build(
                ProtoMessage()..setMessage(
                  PreloadedUserSettingsField.status,
                  ProtoMessage()..setMessage(
                    StatusField.customStatus,
                    ProtoMessage()
                      ..setString(CustomStatusField.emojiName, '🛠')
                      ..setFixed64(CustomStatusField.emojiId, 1)
                      ..setFixed64(CustomStatusField.expiresAtMs, 5),
                  ),
                ),
                const UserSettingsPatch(
                  customStatusEmojiName: '',
                  customStatusExpiresAtMs: 0,
                ),
              )
              .messageAt(PreloadedUserSettingsField.status)!
              .messageAt(StatusField.customStatus)!;
      expect(cleared.stringAt(CustomStatusField.emojiName), isNull);
      expect(cleared.fixed64At(CustomStatusField.emojiId), isNull);
      expect(cleared.fixed64At(CustomStatusField.expiresAtMs), isNull);
    });

    test('clearing the custom status wins over editing it', () {
      final group = DiscordUserSettingsPatch.build(
        ProtoMessage()..setMessage(
          PreloadedUserSettingsField.status,
          ProtoMessage()..setMessage(
            StatusField.customStatus,
            ProtoMessage()..setString(CustomStatusField.text, 'Old'),
          ),
        ),
        const UserSettingsPatch(
          clearCustomStatus: true,
          customStatusText: 'New',
        ),
      ).messageAt(PreloadedUserSettingsField.status)!;

      expect(group.messageAt(StatusField.customStatus), isNull);
    });

    test('a status-only patch reports that it touches the status group', () {
      expect(
        const UserSettingsPatch(onlineStatus: Presence.idle).touchesStatus,
        isTrue,
      );
      expect(
        const UserSettingsPatch(customStatusEmojiName: 'x').touchesStatus,
        isTrue,
      );
      expect(
        const UserSettingsPatch(customStatusExpiresAtMs: 1).touchesStatus,
        isTrue,
      );
      expect(const UserSettingsPatch().isEmpty, isTrue);
    });
  });
}
