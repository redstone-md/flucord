import 'package:flucord/src/data/discord/discord_go_live_service.dart';
import 'package:flucord/src/domain/go_live_stream.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('stream key', () {
    test('composes the shape Discord parses apart', () {
      const guild = GoLiveStreamKey.guild(
        guildId: 'g',
        channelId: 'c',
        userId: 'u',
      );
      const call = GoLiveStreamKey.call(channelId: 'c', userId: 'u');

      expect(guild.value, 'guild:g:c:u');
      expect(call.value, 'call:c:u');
      expect(guild.isCall, isFalse);
      expect(call.isCall, isTrue);
      expect(call.toString(), 'call:c:u');
    });

    test('reads one back, and refuses anything else', () {
      expect(
        GoLiveStreamKey.parse('guild:g:c:u'),
        const GoLiveStreamKey.guild(guildId: 'g', channelId: 'c', userId: 'u'),
      );
      expect(
        GoLiveStreamKey.parse('call:c:u'),
        const GoLiveStreamKey.call(channelId: 'c', userId: 'u'),
      );
      expect(GoLiveStreamKey.parse('guild:g:c'), isNull);
      expect(GoLiveStreamKey.parse('call:c:u:extra'), isNull);
      expect(GoLiveStreamKey.parse('screen:c:u'), isNull);
      // An empty segment would compose back into a different key.
      expect(GoLiveStreamKey.parse('guild::c:u'), isNull);
      expect(GoLiveStreamKey.parse('call::u'), isNull);
      expect(GoLiveStreamKey.parse(''), isNull);
    });

    test('compares by what it names', () {
      const key = GoLiveStreamKey.call(channelId: 'c', userId: 'u');

      expect(key, const GoLiveStreamKey.call(channelId: 'c', userId: 'u'));
      expect(
        key.hashCode,
        const GoLiveStreamKey.call(channelId: 'c', userId: 'u').hashCode,
      );
      expect(
        key == const GoLiveStreamKey.call(channelId: 'c', userId: 'x'),
        isFalse,
      );
      expect(key == Object(), isFalse);
    });
  });

  group('service', () {
    test('starts a guild stream and hands back its key', () async {
      final gateway = _FakeGateway();
      final service = DiscordGoLiveService(gateway);
      addTearDown(service.close);

      final key = await service.startStream(
        channelId: 'voice-1',
        guildId: 'guild-1',
        preferredRegion: 'rotterdam',
      );

      expect(key.value, 'guild:guild-1:voice-1:me');
      expect(gateway.created.single, {
        'type': 'guild',
        'channel_id': 'voice-1',
        'guild_id': 'guild-1',
        'preferred_region': 'rotterdam',
      });
    });

    test('a call stream names no guild', () async {
      final gateway = _FakeGateway();
      final service = DiscordGoLiveService(gateway);
      addTearDown(service.close);

      final key = await service.startStream(channelId: 'dm-1');

      expect(key.value, 'call:dm-1:me');
      expect(gateway.created.single['type'], 'call');
      expect(gateway.created.single.containsKey('guild_id'), isFalse);
    });

    test('nothing is opened before the session names the account', () async {
      final service = DiscordGoLiveService(_FakeGateway(userId: null));
      addTearDown(service.close);

      await expectLater(
        service.startStream(channelId: 'voice-1'),
        throwsA(isA<StateError>()),
      );
    });

    test('watch, ping, pause and delete carry the key back', () async {
      final gateway = _FakeGateway();
      final service = DiscordGoLiveService(gateway);
      addTearDown(service.close);
      const key = GoLiveStreamKey.guild(
        guildId: 'g',
        channelId: 'c',
        userId: 'u',
      );

      await service.watchStream(key);
      await service.pingStream(key);
      await service.setPaused(key, paused: true);
      await service.endStream(key);

      expect(gateway.watched, ['guild:g:c:u']);
      expect(gateway.pinged, ['guild:g:c:u']);
      expect(gateway.paused.single, ('guild:g:c:u', true));
      expect(gateway.deleted, ['guild:g:c:u']);
    });

    test('a stream Discord announces is held and republished', () async {
      final service = DiscordGoLiveService(_FakeGateway());
      final seen = <GoLiveStream>[];
      final subscription = service.updates.listen(seen.add);
      addTearDown(subscription.cancel);
      addTearDown(service.close);

      service.accept('STREAM_CREATE', const {
        'stream_key': 'guild:g:c:u',
        'rtc_server_id': 'rtc-1',
        'region': 'rotterdam',
        'viewer_ids': ['viewer-1', 7],
      });
      expect(service.streams['guild:g:c:u']?.rtcServerId, 'rtc-1');
      expect(service.streams['guild:g:c:u']?.viewerIds, ['viewer-1']);

      // An update carries only what changed.
      service.accept('STREAM_UPDATE', const {
        'stream_key': 'guild:g:c:u',
        'viewer_ids': ['viewer-1', 'viewer-2'],
      });
      final updated = service.streams['guild:g:c:u']!;
      expect(updated.viewerIds.length, 2);
      expect(updated.region, 'rotterdam');
      expect(updated.rtcServerId, 'rtc-1');

      service.accept('STREAM_UPDATE', const {
        'stream_key': 'guild:g:c:u',
        'paused': true,
        'region': 'frankfurt',
      });
      expect(service.streams['guild:g:c:u']?.isPaused, isTrue);
      expect(service.streams['guild:g:c:u']?.region, 'frankfurt');

      await Future<void>.delayed(Duration.zero);
      expect(seen.length, 3);
    });

    test('an update for a stream nobody announced still lands', () {
      final service = DiscordGoLiveService(_FakeGateway());
      addTearDown(service.close);

      service.accept('STREAM_UPDATE', const {
        'stream_key': 'call:c:u',
        'paused': true,
      });

      expect(service.streams['call:c:u']?.isPaused, isTrue);
    });

    test('the RTC endpoint is reported apart from the stream', () async {
      final service = DiscordGoLiveService(_FakeGateway());
      final servers = <GoLiveServer>[];
      final subscription = service.servers.listen(servers.add);
      addTearDown(subscription.cancel);
      addTearDown(service.close);
      service.accept('STREAM_CREATE', const {'stream_key': 'call:c:u'});

      service.accept('STREAM_SERVER_UPDATE', const {
        'stream_key': 'call:c:u',
        'endpoint': 'stream.discord.gg',
        'token': 'token-1',
      });
      // Half an endpoint is no endpoint.
      expect(
        service.accept('STREAM_SERVER_UPDATE', const {
          'stream_key': 'call:c:u',
          'endpoint': 'stream.discord.gg',
        }),
        isNull,
      );
      await Future<void>.delayed(Duration.zero);

      expect(servers.single.endpoint, 'stream.discord.gg');
      expect(servers.single.token, 'token-1');
      expect(servers.single.key.channelId, 'c');
    });

    test('ending a stream forgets it, locally and on the wire', () async {
      final gateway = _FakeGateway();
      final service = DiscordGoLiveService(gateway);
      final seen = <GoLiveStream>[];
      final subscription = service.updates.listen(seen.add);
      addTearDown(subscription.cancel);
      addTearDown(service.close);
      service.accept('STREAM_CREATE', const {
        'stream_key': 'call:c:u',
        'viewer_ids': ['viewer-1'],
      });

      await service.endStream(
        const GoLiveStreamKey.call(channelId: 'c', userId: 'u'),
      );

      expect(service.streams, isEmpty);
      await Future<void>.delayed(Duration.zero);
      // The last word about it says nobody is watching any more.
      expect(seen.last.viewerIds, isEmpty);

      // Ending it twice sends the frame again but reports nothing further.
      await service.endStream(
        const GoLiveStreamKey.call(channelId: 'c', userId: 'u'),
      );
      expect(gateway.deleted.length, 2);
    });

    test('a stream somebody else ended is dropped', () {
      final service = DiscordGoLiveService(_FakeGateway());
      addTearDown(service.close);
      service.accept('STREAM_CREATE', const {'stream_key': 'call:c:u'});

      expect(
        service.accept('STREAM_DELETE', const {'stream_key': 'call:c:u'}),
        isNotNull,
      );
      expect(service.streams, isEmpty);
      // A second one says nothing.
      expect(
        service.accept('STREAM_DELETE', const {'stream_key': 'call:c:u'}),
        isNull,
      );
    });

    test('pausing applies locally rather than waiting to be told', () async {
      final service = DiscordGoLiveService(_FakeGateway());
      addTearDown(service.close);
      service.accept('STREAM_CREATE', const {'stream_key': 'call:c:u'});

      await service.setPaused(
        const GoLiveStreamKey.call(channelId: 'c', userId: 'u'),
        paused: true,
      );

      expect(service.streams['call:c:u']?.isPaused, isTrue);

      // Pausing one nobody announced changes no held state.
      await service.setPaused(
        const GoLiveStreamKey.call(channelId: 'other', userId: 'u'),
        paused: true,
      );
      expect(service.streams.length, 1);
    });

    test('a malformed dispatch changes nothing', () {
      final service = DiscordGoLiveService(_FakeGateway());
      addTearDown(service.close);

      expect(service.accept('MESSAGE_CREATE', const {}), isNull);
      expect(service.accept('STREAM_CREATE', const {}), isNull);
      expect(
        service.accept('STREAM_CREATE', const {'stream_key': 'nonsense'}),
        isNull,
      );
      expect(service.accept('STREAM_UPDATE', const {'stream_key': 7}), isNull);
      expect(service.accept('STREAM_SERVER_UPDATE', const {}), isNull);
      expect(service.accept('STREAM_DELETE', const {}), isNull);
      expect(service.streams, isEmpty);
    });

    test('closing twice is harmless', () async {
      final service = DiscordGoLiveService(_FakeGateway());

      await service.close();
      await service.close();

      expect(
        service.accept('STREAM_CREATE', const {'stream_key': 'call:c:u'}),
        isNotNull,
      );
      await service.endStream(
        const GoLiveStreamKey.call(channelId: 'c', userId: 'u'),
      );
      service.accept('STREAM_SERVER_UPDATE', const {
        'stream_key': 'call:c:u',
        'endpoint': 'e',
        'token': 't',
      });
    });
  });
}

final class _FakeGateway implements DiscordGoLiveGateway {
  _FakeGateway({this.userId = 'me'});

  final String? userId;
  final List<Map<String, Object?>> created = [];
  final List<String> watched = [];
  final List<String> pinged = [];
  final List<String> deleted = [];
  final List<(String, bool)> paused = [];

  @override
  String? get currentUserId => userId;

  @override
  void sendStreamCreate({
    required String type,
    required String channelId,
    String? guildId,
    String? preferredRegion,
  }) => created.add({
    'type': type,
    'channel_id': channelId,
    'guild_id': ?guildId,
    'preferred_region': ?preferredRegion,
  });

  @override
  void sendStreamDelete(String streamKey) => deleted.add(streamKey);

  @override
  void sendStreamWatch(String streamKey) => watched.add(streamKey);

  @override
  void sendStreamPing(String streamKey) => pinged.add(streamKey);

  @override
  void sendStreamSetPaused(String streamKey, {required bool paused}) =>
      this.paused.add((streamKey, paused));
}
