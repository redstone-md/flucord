import 'dart:async';

import 'package:flucord/src/application/stage_controller.dart';
import 'package:flucord/src/data/discord/discord_stage_service.dart';
import 'package:flucord/src/domain/stage_channel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('model', () {
    test('a role is read off suppression, the hand and the invitation', () {
      const audience = StagePresence(channelId: 'c');
      final raised = StagePresence(
        channelId: 'c',
        requestedAt: DateTime.utc(2026),
      );
      const invited = StagePresence(channelId: 'c', isInvited: true);
      const speaking = StagePresence(channelId: 'c', isSuppressed: false);

      expect(audience.role, StageRole.audience);
      expect(raised.role, StageRole.requestedToSpeak);
      expect(invited.role, StageRole.invitedToSpeak);
      expect(speaking.role, StageRole.speaker);
      // Already speaking wins over anything still set on the way up.
      expect(
        const StagePresence(
          channelId: 'c',
          isSuppressed: false,
          isInvited: true,
        ).role,
        StageRole.speaker,
      );
    });

    test('a stage compares by every field', () {
      const stage = StageInstance(id: '1', channelId: 'c', guildId: 'g');

      expect(stage, const StageInstance(id: '1', channelId: 'c', guildId: 'g'));
      expect(
        stage.hashCode,
        const StageInstance(id: '1', channelId: 'c', guildId: 'g').hashCode,
      );
      expect(
        stage ==
            const StageInstance(
              id: '1',
              channelId: 'c',
              guildId: 'g',
              topic: 'x',
            ),
        isFalse,
      );
      expect(stage == Object(), isFalse);
      expect(stage.privacyLevel, StagePrivacyLevel.guildOnly);
      expect(stage.isDiscoverable, isFalse);
    });

    test('the retired public privacy level still maps', () {
      expect(StagePrivacyLevel.fromWire(1), StagePrivacyLevel.public);
      expect(StagePrivacyLevel.fromWire(2), StagePrivacyLevel.guildOnly);
      expect(StagePrivacyLevel.fromWire(null), StagePrivacyLevel.guildOnly);
      expect(StagePrivacyLevel.public.wireValue, 1);
      expect(StagePrivacyLevel.guildOnly.wireValue, 2);
    });
  });

  group('service', () {
    test('seats a stage announced during bootstrap', () {
      final service = DiscordStageService(_FakeTransport());
      addTearDown(service.close);

      service.accept('GUILD_CREATE', const {
        'id': 'guild-1',
        'channels': [
          {'id': 'stage-1'},
          {'name': 'no id'},
        ],
        'stage_instances': [
          {
            'id': 'instance-1',
            'channel_id': 'stage-1',
            'topic': 'Release notes',
            'privacy_level': 2,
          },
        ],
      });

      final stage = service.stageFor('stage-1');
      expect(stage?.id, 'instance-1');
      expect(stage?.guildId, 'guild-1');
      expect(stage?.topic, 'Release notes');
      expect(stage?.isDiscoverable, isTrue);
    });

    test('a supplemental burst carries them too', () {
      final service = DiscordStageService(_FakeTransport());
      addTearDown(service.close);

      service.accept('READY_SUPPLEMENTAL', const {
        'guilds': [
          {
            'id': 'guild-1',
            'stage_instances': [
              {'channel_id': 'stage-1', 'discoverable_disabled': true},
            ],
          },
          // Nothing to report, and nothing claimed.
          {'id': 'guild-2'},
          {'no': 'id'},
        ],
      });

      expect(service.stageFor('stage-1')?.isDiscoverable, isFalse);
      // With no instance id Discord's channel stands in, so the row is still
      // addressable.
      expect(service.stageFor('stage-1')?.id, 'stage-1');
    });

    test('a stage starting and ending is followed', () async {
      final service = DiscordStageService(_FakeTransport());
      final seen = <String>[];
      final subscription = service.updates.listen(seen.add);
      addTearDown(subscription.cancel);
      addTearDown(service.close);

      service.accept('STAGE_INSTANCE_CREATE', const {
        'id': 'i',
        'channel_id': 'stage-1',
        'guild_id': 'guild-1',
        'topic': 'Live',
      });
      expect(service.stageFor('stage-1')?.topic, 'Live');

      service.accept('STAGE_INSTANCE_UPDATE', const {
        'id': 'i',
        'channel_id': 'stage-1',
        'guild_id': 'guild-1',
        'topic': 'Renamed',
      });
      expect(service.stageFor('stage-1')?.topic, 'Renamed');

      service.accept('STAGE_INSTANCE_DELETE', const {'channel_id': 'stage-1'});
      expect(service.stageFor('stage-1'), isNull);
      // Deleting one that was never seated says nothing.
      expect(
        service.accept('STAGE_INSTANCE_DELETE', const {
          'channel_id': 'stage-1',
        }),
        isNull,
      );
      // The stream is broadcast, so the listener runs a turn later.
      await Future<void>.delayed(Duration.zero);
      expect(seen, ['stage-1', 'stage-1', 'stage-1']);
    });

    test('a malformed stage payload is refused', () {
      final service = DiscordStageService(_FakeTransport());
      addTearDown(service.close);

      expect(
        service.accept('STAGE_INSTANCE_CREATE', const {'channel_id': ''}),
        isNull,
      );
      expect(
        service.accept('STAGE_INSTANCE_CREATE', const {'channel_id': 'c'}),
        isNull,
      );
      expect(service.accept('STAGE_INSTANCE_DELETE', const {}), isNull);
      expect(service.accept('MESSAGE_CREATE', const {}), isNull);
      expect(service.accept('GUILD_CREATE', const {}), isNull);
      expect(service.accept('READY_SUPPLEMENTAL', const {}), isNull);
    });

    test('reads this account\'s own standing, and nobody else\'s', () {
      final service = DiscordStageService(_FakeTransport())
        ..setCurrentUserId('me');
      addTearDown(service.close);

      service.accept('VOICE_STATE_UPDATE', const {
        'user_id': 'other',
        'channel_id': 'stage-1',
        'guild_id': 'guild-1',
        'suppress': false,
      });
      expect(service.presenceFor('stage-1'), isNull);

      service.accept('VOICE_STATE_UPDATE', const {
        'user_id': 'me',
        'channel_id': 'stage-1',
        'guild_id': 'guild-1',
        'suppress': true,
        'request_to_speak_timestamp': '2026-07-27T10:00:00+00:00',
      });

      final presence = service.presenceFor('stage-1');
      expect(presence?.role, StageRole.requestedToSpeak);
      expect(presence?.requestedAt, DateTime.utc(2026, 7, 27, 10));
    });

    test('a voice state before the account is known is ignored', () {
      final service = DiscordStageService(_FakeTransport());
      addTearDown(service.close);

      expect(
        service.accept('VOICE_STATE_UPDATE', const {
          'user_id': 'me',
          'channel_id': 'stage-1',
        }),
        isNull,
      );
    });

    test('leaving clears the standing rather than freezing it', () {
      final service = DiscordStageService(_FakeTransport())
        ..setCurrentUserId('me');
      addTearDown(service.close);
      service.accept('VOICE_STATE_UPDATE', const {
        'user_id': 'me',
        'channel_id': 'stage-1',
        'guild_id': 'guild-1',
        'suppress': false,
      });

      expect(
        service.accept('VOICE_STATE_UPDATE', const {
          'user_id': 'me',
          'channel_id': null,
        }),
        'stage-1',
      );
      expect(service.presenceFor('stage-1'), isNull);
      // A departure with nothing to clear reports nothing.
      expect(
        service.accept('VOICE_STATE_UPDATE', const {
          'user_id': 'me',
          'channel_id': null,
        }),
        isNull,
      );
    });

    test('raising a hand sends the moment it went up', () async {
      final transport = _FakeTransport();
      final service = DiscordStageService(
        transport,
        clock: () => DateTime.utc(2026, 7, 27, 12),
      );
      addTearDown(service.close);
      service.accept('STAGE_INSTANCE_CREATE', const {
        'channel_id': 'stage-1',
        'guild_id': 'guild-1',
      });

      await service.requestToSpeak('stage-1');

      expect(transport.patches.single, {
        'guild_id': 'guild-1',
        'channel_id': 'stage-1',
        'request_to_speak_timestamp': '2026-07-27T12:00:00.000Z',
        'suppress': null,
        'clear': false,
      });
    });

    test('lowering it clears the timestamp explicitly', () async {
      final transport = _FakeTransport();
      final service = DiscordStageService(transport);
      addTearDown(service.close);
      service.accept('STAGE_INSTANCE_CREATE', const {
        'channel_id': 'stage-1',
        'guild_id': 'guild-1',
      });

      await service.cancelSpeakRequest('stage-1');

      // Absent and null mean different things on this route: absent leaves the
      // hand where it is.
      expect(transport.patches.single['clear'], isTrue);
      expect(transport.patches.single['suppress'], isNull);
    });

    test('taking the stage unsuppresses and drops the hand', () async {
      final transport = _FakeTransport();
      final service = DiscordStageService(transport);
      addTearDown(service.close);
      service.accept('STAGE_INSTANCE_CREATE', const {
        'channel_id': 'stage-1',
        'guild_id': 'guild-1',
      });

      await service.setSpeaking('stage-1', speaking: true);
      expect(transport.patches.single['suppress'], isFalse);
      expect(transport.patches.single['clear'], isTrue);

      await service.setSpeaking('stage-1', speaking: false);
      expect(transport.patches.last['suppress'], isTrue);
      // Stepping down leaves the hand alone: it is already down.
      expect(transport.patches.last['clear'], isFalse);
    });

    test('a channel with no known guild sends nothing', () async {
      final transport = _FakeTransport();
      final service = DiscordStageService(transport);
      addTearDown(service.close);

      await service.requestToSpeak('unknown');
      await service.cancelSpeakRequest('unknown');
      await service.setSpeaking('unknown', speaking: true);

      expect(transport.patches, isEmpty);
    });

    test('closing twice is harmless and stops publishing', () async {
      final service = DiscordStageService(_FakeTransport());

      await service.close();
      await service.close();

      expect(
        service.accept('STAGE_INSTANCE_CREATE', const {
          'channel_id': 'stage-1',
          'guild_id': 'guild-1',
        }),
        'stage-1',
      );
    });
  });

  group('moderation', () {
    test('starting a stage adopts the server echo', () async {
      final transport = _FakeTransport();
      final service = DiscordStageService(transport);
      addTearDown(service.close);
      // The channel's guild is known from bootstrap, not from the response.
      service.accept('GUILD_CREATE', const {
        'id': 'guild-1',
        'channels': [
          {'id': 'stage-1'},
        ],
      });

      await service.startStage(
        'stage-1',
        topic: 'Release notes',
        sendStartNotification: true,
      );

      expect(transport.created.single, {
        'channel_id': 'stage-1',
        'topic': 'Release notes',
        'notify': true,
      });
      final stage = service.stageFor('stage-1');
      expect(stage?.topic, 'Release notes');
      expect(stage?.id, 'instance-1');
      expect(stage?.guildId, 'guild-1');
    });

    test('a response the mapper cannot read leaves the store alone', () async {
      final transport = _FakeTransport()..echo = const {'topic': 'nonsense'};
      final service = DiscordStageService(transport);
      addTearDown(service.close);
      service.accept('GUILD_CREATE', const {
        'id': 'guild-1',
        'channels': [
          {'id': 'stage-1'},
        ],
      });

      await service.startStage('stage-1', topic: 'x');

      expect(service.stageFor('stage-1'), isNull);
    });

    test('renaming republishes the topic', () async {
      final transport = _FakeTransport();
      final service = DiscordStageService(transport);
      addTearDown(service.close);
      service.accept('STAGE_INSTANCE_CREATE', const {
        'channel_id': 'stage-1',
        'guild_id': 'guild-1',
        'topic': 'Before',
      });

      await service.setStageTopic('stage-1', 'After');

      expect(transport.renamed.single['topic'], 'After');
      expect(service.stageFor('stage-1')?.topic, 'After');
    });

    test('ending it clears the store without the dispatch', () async {
      final transport = _FakeTransport();
      final service = DiscordStageService(transport);
      addTearDown(service.close);
      service.accept('STAGE_INSTANCE_CREATE', const {
        'channel_id': 'stage-1',
        'guild_id': 'guild-1',
      });

      await service.endStage('stage-1');

      expect(transport.ended, ['stage-1']);
      expect(service.stageFor('stage-1'), isNull);
      // Ending one that is already gone reports nothing further.
      await service.endStage('stage-1');
      expect(transport.ended.length, 2);
    });

    test('a moderator moves somebody on and off stage', () async {
      final transport = _FakeTransport();
      final service = DiscordStageService(transport);
      addTearDown(service.close);
      service.accept('STAGE_INSTANCE_CREATE', const {
        'channel_id': 'stage-1',
        'guild_id': 'guild-1',
      });

      await service.setMemberSpeaking(
        'stage-1',
        userId: 'someone',
        speaking: true,
      );
      await service.setMemberSpeaking(
        'stage-1',
        userId: 'someone',
        speaking: false,
      );

      expect(transport.memberPatches.first, {
        'guild_id': 'guild-1',
        'user_id': 'someone',
        'channel_id': 'stage-1',
        'suppress': false,
      });
      expect(transport.memberPatches.last['suppress'], isTrue);
    });

    test('a channel with no known guild moves nobody', () async {
      final transport = _FakeTransport();
      final service = DiscordStageService(transport);
      addTearDown(service.close);

      await service.setMemberSpeaking('nope', userId: 'a', speaking: true);

      expect(transport.memberPatches, isEmpty);
    });
  });

  group('controller', () {
    test('a transport with no stage plane offers nothing', () async {
      final controller = StageController(() => null);
      addTearDown(controller.dispose);

      controller.show('stage-1');

      expect(controller.isSupported, isFalse);
      expect(await controller.requestToSpeak(), isFalse);
      expect(controller.role, StageRole.audience);
      expect(controller.isLive, isFalse);
      expect(controller.topic, isEmpty);
    });

    test('follows the stage on screen', () async {
      final service = DiscordStageService(_FakeTransport())
        ..setCurrentUserId('me');
      final controller = StageController(() => service);
      addTearDown(controller.dispose);
      addTearDown(service.close);

      controller.show('stage-1');
      service.accept('STAGE_INSTANCE_CREATE', const {
        'channel_id': 'stage-1',
        'guild_id': 'guild-1',
        'topic': 'Live',
      });
      await Future<void>.delayed(Duration.zero);

      expect(controller.isLive, isTrue);
      expect(controller.topic, 'Live');
      expect(controller.role, StageRole.audience);

      // Showing the same channel twice changes nothing.
      controller.show('stage-1');
      controller.show(null);
      expect(controller.isLive, isFalse);
      expect(controller.stage, isNull);
      expect(controller.presence, isNull);
    });

    test('walks the audience through to speaking', () async {
      final transport = _FakeTransport();
      final service = DiscordStageService(transport)..setCurrentUserId('me');
      final controller = StageController(() => service);
      addTearDown(controller.dispose);
      addTearDown(service.close);
      service.accept('STAGE_INSTANCE_CREATE', const {
        'channel_id': 'stage-1',
        'guild_id': 'guild-1',
      });
      controller.show('stage-1');

      expect(await controller.requestToSpeak(), isTrue);
      expect(await controller.cancelRequest(), isTrue);
      expect(await controller.takeStage(), isTrue);
      expect(await controller.leaveStage(), isTrue);
      expect(transport.patches.length, 4);
      expect(controller.error, isNull);
    });

    test('moderation is refused without the permission', () async {
      final transport = _FakeTransport();
      final service = DiscordStageService(transport);
      final controller = StageController(() => service);
      addTearDown(controller.dispose);
      addTearDown(service.close);
      service.accept('STAGE_INSTANCE_CREATE', const {
        'channel_id': 'stage-1',
        'guild_id': 'guild-1',
      });
      controller.show('stage-1');

      expect(controller.canModerate, isFalse);
      expect(await controller.startStage('x'), isFalse);
      expect(await controller.setTopic('x'), isFalse);
      expect(await controller.endStage(), isFalse);
      expect(await controller.setMemberSpeaking('a', speaking: true), isFalse);
      // Nothing was sent for Discord to refuse.
      expect(transport.created, isEmpty);
      expect(transport.renamed, isEmpty);
      expect(transport.ended, isEmpty);
      expect(transport.memberPatches, isEmpty);
    });

    test('a moderator runs the stage', () async {
      final transport = _FakeTransport();
      final service = DiscordStageService(transport);
      final controller = StageController(() => service);
      addTearDown(controller.dispose);
      addTearDown(service.close);
      service.accept('GUILD_CREATE', const {
        'id': 'guild-1',
        'channels': [
          {'id': 'stage-1'},
        ],
      });
      controller.show('stage-1', canModerate: true);

      expect(controller.canModerate, isTrue);
      // The topic is trimmed before it is sent: Discord stores what it is
      // given, trailing spaces included.
      expect(await controller.startStage('  Release notes  '), isTrue);
      expect(transport.created.single['topic'], 'Release notes');
      expect(await controller.setTopic(' Renamed '), isTrue);
      expect(transport.renamed.single['topic'], 'Renamed');
      expect(await controller.setMemberSpeaking('a', speaking: true), isTrue);
      expect(await controller.endStage(), isTrue);
      expect(transport.ended, ['stage-1']);
    });

    test('a permission change alone repaints the controls', () {
      final service = DiscordStageService(_FakeTransport());
      final controller = StageController(() => service);
      addTearDown(controller.dispose);
      addTearDown(service.close);

      controller.show('stage-1');
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.show('stage-1', canModerate: true);
      expect(notifications, 1);
      expect(controller.canModerate, isTrue);

      controller.show('stage-1', canModerate: true);
      expect(notifications, 1);
    });

    test('a rejected request is reported', () async {
      final transport = _FakeTransport(failWrites: true);
      final service = DiscordStageService(transport);
      final controller = StageController(() => service);
      addTearDown(controller.dispose);
      addTearDown(service.close);
      service.accept('STAGE_INSTANCE_CREATE', const {
        'channel_id': 'stage-1',
        'guild_id': 'guild-1',
      });
      controller.show('stage-1');

      expect(await controller.requestToSpeak(), isFalse);

      expect(controller.error, isNotNull);
      expect(controller.isBusy, isFalse);
    });

    test('a second action while one is in flight is refused', () async {
      final gate = Completer<void>();
      final transport = _FakeTransport(gate: gate);
      final service = DiscordStageService(transport);
      final controller = StageController(() => service);
      addTearDown(controller.dispose);
      addTearDown(service.close);
      service.accept('STAGE_INSTANCE_CREATE', const {
        'channel_id': 'stage-1',
        'guild_id': 'guild-1',
      });
      controller.show('stage-1');

      final first = controller.requestToSpeak();
      expect(controller.isBusy, isTrue);
      expect(await controller.takeStage(), isFalse);

      gate.complete();
      expect(await first, isTrue);
    });

    test('another channel changing does not repaint this one', () async {
      final service = DiscordStageService(_FakeTransport());
      final controller = StageController(() => service);
      addTearDown(controller.dispose);
      addTearDown(service.close);
      controller.show('stage-1');
      var notifications = 0;
      controller.addListener(() => notifications++);

      service.accept('STAGE_INSTANCE_CREATE', const {
        'channel_id': 'stage-9',
        'guild_id': 'guild-1',
      });
      await Future<void>.delayed(Duration.zero);
      expect(notifications, 0);

      service.accept('STAGE_INSTANCE_CREATE', const {
        'channel_id': 'stage-1',
        'guild_id': 'guild-1',
      });
      await Future<void>.delayed(Duration.zero);
      expect(notifications, 1);
    });

    test('swapping the transport rebinds the store', () async {
      var service = DiscordStageService(_FakeTransport());
      final controller = StageController(() => service);
      addTearDown(controller.dispose);
      final first = service;
      addTearDown(first.close);

      controller.show('stage-1');
      service.accept('STAGE_INSTANCE_CREATE', const {
        'channel_id': 'stage-1',
        'guild_id': 'guild-1',
        'topic': 'Old session',
      });
      expect(controller.topic, 'Old session');

      service = DiscordStageService(_FakeTransport());
      addTearDown(() => service.close());

      expect(controller.isSupported, isTrue);
      expect(controller.isLive, isFalse);
    });
  });
}

final class _FakeTransport implements DiscordStageTransport {
  _FakeTransport({this.failWrites = false, this.gate});

  final bool failWrites;
  final Completer<void>? gate;
  final List<Map<String, Object?>> patches = [];
  final List<Map<String, Object?>> memberPatches = [];
  final List<Map<String, Object?>> created = [];
  final List<Map<String, Object?>> renamed = [];
  final List<String> ended = [];
  Map<String, Object?> echo = const {
    'id': 'instance-1',
    'channel_id': 'stage-1',
    'topic': 'Live',
    'privacy_level': 2,
  };

  @override
  Future<void> patchSelfVoiceState(
    String guildId, {
    required String channelId,
    bool? suppress,
    String? requestToSpeakTimestamp,
    bool clearRequestToSpeak = false,
  }) async {
    await gate?.future;
    if (failWrites) throw StateError('rejected');
    patches.add({
      'guild_id': guildId,
      'channel_id': channelId,
      'suppress': suppress,
      'request_to_speak_timestamp': requestToSpeakTimestamp,
      'clear': clearRequestToSpeak,
    });
  }

  @override
  Future<void> patchMemberVoiceState(
    String guildId, {
    required String userId,
    required String channelId,
    required bool suppress,
  }) async {
    await gate?.future;
    if (failWrites) throw StateError('rejected');
    memberPatches.add({
      'guild_id': guildId,
      'user_id': userId,
      'channel_id': channelId,
      'suppress': suppress,
    });
  }

  @override
  Future<Map<String, Object?>> createStageInstance({
    required String channelId,
    required String topic,
    bool sendStartNotification = false,
  }) async {
    await gate?.future;
    if (failWrites) throw StateError('rejected');
    created.add({
      'channel_id': channelId,
      'topic': topic,
      'notify': sendStartNotification,
    });
    return {...echo, 'topic': topic};
  }

  @override
  Future<Map<String, Object?>> updateStageInstance(
    String channelId, {
    required String topic,
  }) async {
    await gate?.future;
    if (failWrites) throw StateError('rejected');
    renamed.add({'channel_id': channelId, 'topic': topic});
    return {...echo, 'topic': topic};
  }

  @override
  Future<void> deleteStageInstance(String channelId) async {
    await gate?.future;
    if (failWrites) throw StateError('rejected');
    ended.add(channelId);
  }
}
