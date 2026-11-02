// Times each core ChatWorkspace fold at one scale after another, the way one
// gateway event pays for it. README.md says how to run it.
//
// The imports reach into lib/ by relative path, because a dependency on the
// app would stop this package from compiling. README.md says why.
// ignore_for_file: avoid_relative_lib_imports
import 'dart:io';

import '../../lib/src/domain/chat_models.dart';
import '../../lib/src/domain/read_state.dart';

const _spaces = 100;
const _channelsPerSpace = 50;
const _members = 20000;
const _heldMessages = [1000, 10000, 100000, 300000];

/// A large scale gets fewer runs, since each run takes longer.
int _runsAt(int heldMessages) => heldMessages >= 100000 ? 15 : 41;

/// Fixture ids count up from a value the repository's privacy audit allows.
String _snowflake(int index) => (100000000000000000 + index).toString();

ChatWorkspace _workspaceHolding(int messageCount) {
  final channels = [
    for (var space = 0; space < _spaces; space++)
      for (var channel = 0; channel < _channelsPerSpace; channel++)
        ConversationChannel(
          id: _snowflake(space * _channelsPerSpace + channel),
          spaceId: 'g$space',
          name: 'channel-$channel',
          topic: '',
          kind: ChannelKind.text,
          lastMessageId: _snowflake(5000000),
        ),
  ];
  final start = DateTime(2026);
  return ChatWorkspace(
    spaces: [
      for (var space = 0; space < _spaces; space++)
        CommunitySpace(
          id: 'g$space',
          name: 'Guild $space',
          monogram: 'G',
          colorValue: 0,
        ),
    ],
    channels: channels,
    members: [
      for (var member = 0; member < _members; member++)
        Member(
          id: 'u$member',
          displayName: 'User $member',
          initials: 'U',
          role: '',
          presence: Presence.online,
          colorValue: 0,
        ),
    ],
    messages: [
      for (var i = 0; i < messageCount; i++)
        ChatMessage(
          id: _snowflake(1000000 + i),
          channelId: channels[i % channels.length].id,
          authorId: 'u${i % _members}',
          body: 'message $i',
          sentAt: start.add(Duration(seconds: i)),
        ),
    ],
    currentMemberId: 'u0',
  );
}

/// Prints the median and worst time of [body] over [runs] runs.
void _report(String fold, int runs, void Function(int run) body) {
  final samples = <int>[];
  final stopwatch = Stopwatch();
  for (var run = 0; run < runs; run++) {
    stopwatch
      ..reset()
      ..start();
    body(run);
    stopwatch.stop();
    samples.add(stopwatch.elapsedMicroseconds);
  }
  samples.sort();
  String ms(int micros) => (micros / 1000).toStringAsFixed(2).padLeft(9);
  stdout.writeln(
    '  ${fold.padRight(44)} '
    'p50 ${ms(samples[runs ~/ 2])} ms   max ${ms(samples.last)} ms',
  );
}

void _benchAt(int heldMessages) {
  final workspace = _workspaceHolding(heldMessages);
  stdout.writeln(
    'channels=${workspace.channels.length} '
    'members=${workspace.members.length} messages=$heldMessages',
  );
  final runs = _runsAt(heldMessages);
  final activeChannel = workspace.channels[7].id;
  final sentAt = DateTime(2027);
  ChatMessage newMessage(int run, {int base = 4000000}) => ChatMessage(
    id: _snowflake(base + run),
    channelId: activeChannel,
    authorId: 'u1',
    body: 'hi',
    sentAt: sentAt,
  );

  _report('upsertMessage', runs, (run) {
    workspace.upsertMessage(newMessage(run));
  });
  _report('upsertMessage + member merge', runs, (run) {
    workspace.upsertMessage(newMessage(run), member: workspace.members[run]);
  });

  final snapshot = ReadStateSnapshot(
    readStates: {
      for (final channel in workspace.channels)
        channel.id: ReadState(
          entityId: channel.id,
          lastAckedId: _snowflake(1000000),
        ),
    },
  );
  _report('applyReadState', runs, (_) => workspace.applyReadState(snapshot));

  // The member lookup is what makes a new member list pay for its index.
  _report('applyPresences (one user)', runs, (run) {
    workspace
        .applyPresences({
          'u${run + 5}': const UserPresence(status: Presence.idle),
        })
        .memberOrNull('u1');
  });

  final page = [for (var k = 0; k < 50; k++) newMessage(k, base: 4500000)];
  _report('mergeHistory (50-message page)', runs, (_) {
    workspace.mergeHistory(
      ChannelHistory(
        channelId: activeChannel,
        messages: page,
        members: const [],
      ),
    );
  });

  // A new message followed by a read of its channel. The name is from when this
  // read had to group every held message again.
  _report('upsertMessage + messagesFor (regroup)', runs, (run) {
    workspace.upsertMessage(newMessage(run)).messagesFor(activeChannel);
  });
}

void main() => _heldMessages.forEach(_benchAt);
