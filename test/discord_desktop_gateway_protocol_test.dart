import 'dart:convert';

import 'package:flucord/src/data/discord/discord_desktop_gateway_protocol.dart';
import 'package:flucord/src/data/discord/discord_desktop_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DiscordDesktopGatewayProtocol protocol({
    DiscordDesktopProtocolProfile profile =
        DiscordDesktopProtocolProfile.installedStable20260725,
  }) => DiscordDesktopGatewayProtocol(
    token: 'secret-value',
    properties: const {'os': 'Windows'},
    profile: profile,
    presence: const {'status': 'online'},
  );

  test('normal identify carries capabilities, presence, and client state', () {
    final gateway = protocol();
    final identify = gateway.identify();
    final data = identify.data! as Map<String, Object?>;

    expect(identify.opcode, DiscordDesktopGatewayOpcode.identify);
    expect(data['capabilities'], 1734653);
    expect(data['presence'], {'status': 'online'});
    expect(data['compress'], isFalse);
    expect(data['client_state'], {'guild_versions': <String, Object?>{}});
    expect(data['properties'], {'os': 'Windows', 'is_fast_connect': false});
    expect(gateway.toString(), isNot(contains('secret-value')));
  });

  test('identify asks the session caches for client_state each time', () {
    final gateway = protocol();
    var version = 4;
    gateway.clientStateProvider = () => {
      'guild_versions': const <String, Object?>{},
      'read_state_version': version,
    };

    expect((gateway.identify().data! as Map<String, Object?>)['client_state'], {
      'guild_versions': <String, Object?>{},
      'read_state_version': 4,
    });

    version = 9;
    expect((gateway.identify().data! as Map<String, Object?>)['client_state'], {
      'guild_versions': <String, Object?>{},
      'read_state_version': 9,
    });

    // A fast connect never vouches for a cache, whatever the provider says.
    expect(
      (gateway.identify(fastConnect: true).data!
          as Map<String, Object?>)['client_state'],
      {'guild_versions': <String, Object?>{}},
    );
  });

  test('fast connect identify uses the minimal observed payload', () {
    final data =
        protocol().identify(fastConnect: true).data! as Map<String, Object?>;

    expect(data, isNot(contains('presence')));
    expect(data, isNot(contains('compress')));
    expect(data['properties'], {'os': 'Windows', 'is_fast_connect': true});
  });

  test('READY establishes a resumable session', () {
    final gateway = protocol()..identify();
    final actions = gateway.accept({
      'op': DiscordDesktopGatewayOpcode.dispatch,
      's': 42,
      't': 'READY',
      'd': {
        'session_id': 'session',
        'resume_gateway_url': 'wss://gateway-resume.discord.gg',
      },
    });
    final resume = gateway.resume();

    expect(actions.single, isA<DiscordDesktopGatewayDispatch>());
    expect(gateway.state, DiscordDesktopGatewayState.resuming);
    expect(gateway.resumeGatewayUri?.host, 'gateway-resume.discord.gg');
    expect(resume.opcode, DiscordDesktopGatewayOpcode.resume);
    expect(resume.data, {
      'token': 'secret-value',
      'session_id': 'session',
      'seq': 42,
    });
  });

  test('HELLO and ACK drive the QoS heartbeat watchdog', () {
    final gateway = protocol();
    final hello = gateway.accept({
      'op': DiscordDesktopGatewayOpcode.hello,
      'd': {'heartbeat_interval': 41250},
    });
    final first =
        gateway.heartbeatDue(
              qos: const {
                'reasons': ['foregrounded'],
              },
            )
            as DiscordDesktopGatewaySend;
    // One unanswered heartbeat is a slow network, not a dead socket: dropping
    // the session here ends every voice connection identified with its id.
    final tolerated = gateway.heartbeatDue();
    final timeout = gateway.heartbeatDue();

    expect(
      (hello.single as DiscordDesktopGatewayScheduleHeartbeat).interval,
      const Duration(milliseconds: 41250),
    );
    expect(first.frame.opcode, DiscordDesktopGatewayOpcode.qosHeartbeat);
    expect(first.frame.data, {
      'seq': null,
      'qos': {
        'reasons': ['foregrounded'],
      },
    });
    expect(tolerated, isA<DiscordDesktopGatewaySend>());
    expect(timeout, isA<DiscordDesktopGatewayReconnect>());

    gateway.accept({'op': DiscordDesktopGatewayOpcode.heartbeatAck, 'd': null});
    expect(gateway.heartbeatDue(), isA<DiscordDesktopGatewaySend>());
  });

  test('guild subscriptions use opcode 37 and split at the byte limit', () {
    final gateway = protocol(
      profile: const DiscordDesktopProtocolProfile(
        clientBuildNumber: 582977,
        maxGuildSubscriptionBytes: 80,
      ),
    );
    final frames = gateway.guildSubscriptionFrames({
      '100': {'typing': true, 'threads': true, 'activities': true},
      '200': {'typing': true, 'threads': true, 'activities': true},
    });

    expect(frames, hasLength(2));
    expect(
      frames.every(
        (frame) =>
            frame.opcode == DiscordDesktopGatewayOpcode.guildSubscriptionsBulk,
      ),
      isTrue,
    );
    for (final frame in frames) {
      expect(utf8.encode(jsonEncode(frame.toJson())).length, greaterThan(0));
    }
  });

  test('copies caller-owned protocol properties', () {
    final source = <String, Object?>{'os': 'Windows'};
    final gateway = DiscordDesktopGatewayProtocol(
      token: 'secret-value',
      properties: source,
      profile: DiscordDesktopProtocolProfile.installedStable20260725,
    );
    source['os'] = 'changed';

    final data = gateway.identify().data! as Map<String, Object?>;
    expect(data['properties'], {'os': 'Windows', 'is_fast_connect': false});
  });
}
