import 'package:flucord/src/domain/chat_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// [ChatWorkspace.upsertMessage] places a message in its channel's timeline
/// without re-sorting every message the client has cached. These pin the
/// ordering that used to come from that sort.
void main() {
  test('a channel lookup answers with the same list every time', () {
    final workspace = _workspaceWith([
      _message('a-1', 'alpha', 1),
      _message('a-2', 'alpha', 3),
    ]);

    final first = workspace.messagesFor('alpha');
    final second = workspace.messagesFor('alpha');

    expect(identical(first, second), isTrue);
    expect(
      () => first.add(_message('a-3', 'alpha', 5)),
      throwsUnsupportedError,
    );
  });

  test('places an arriving message after the ones its channel already had', () {
    final workspace = _workspaceWith([
      _message('a-1', 'alpha', 1),
      _message('a-2', 'alpha', 3),
    ]);

    final next = workspace.upsertMessage(_message('a-3', 'alpha', 5));

    expect(_idsIn(next, 'alpha'), ['a-1', 'a-2', 'a-3']);
  });

  test('slots a late arrival into place rather than appending it', () {
    final workspace = _workspaceWith([
      _message('a-1', 'alpha', 1),
      _message('a-2', 'alpha', 5),
    ]);

    final next = workspace.upsertMessage(_message('a-3', 'alpha', 3));

    expect(_idsIn(next, 'alpha'), ['a-1', 'a-3', 'a-2']);
  });

  test('replaces an edited message in place', () {
    final workspace = _workspaceWith([
      _message('a-1', 'alpha', 1),
      _message('a-2', 'alpha', 3),
      _message('a-3', 'alpha', 5),
    ]);

    final next = workspace.upsertMessage(
      _message('a-2', 'alpha', 3, body: 'edited'),
    );

    expect(_idsIn(next, 'alpha'), ['a-1', 'a-2', 'a-3']);
    expect(next.messagesFor('alpha')[1].body, 'edited');
  });

  test('leaves another channel untouched', () {
    final workspace = _workspaceWith([
      _message('b-1', 'beta', 2),
      _message('a-1', 'alpha', 4),
      _message('b-2', 'beta', 6),
    ]);

    final next = workspace.upsertMessage(_message('a-2', 'alpha', 1));

    expect(_idsIn(next, 'beta'), ['b-1', 'b-2']);
    expect(_idsIn(next, 'alpha'), ['a-2', 'a-1']);
  });

  test('a new message does not build the list of another channel again', () {
    final workspace = _workspaceWith([
      _message('a-1', 'alpha', 1),
      _message('b-1', 'beta', 2),
    ]);
    final beta = workspace.messagesFor('beta');

    final next = workspace.upsertMessage(_message('a-2', 'alpha', 3));

    expect(identical(next.messagesFor('beta'), beta), isTrue);
  });

  test('a history page does not build the list of another channel again', () {
    final workspace = _workspaceWith([
      _message('a-1', 'alpha', 1),
      _message('b-1', 'beta', 2),
    ]);
    final beta = workspace.messagesFor('beta');

    final next = workspace.mergeHistory(
      ChannelHistory(
        channelId: 'alpha',
        messages: [_message('a-2', 'alpha', 3)],
        members: const [],
      ),
    );

    expect(identical(next.messagesFor('beta'), beta), isTrue);
  });

  test('an older page goes in front of what the channel held', () {
    final workspace = _workspaceWith([
      _message('a-3', 'alpha', 5),
      _message('b-1', 'beta', 2),
    ]);

    final next = workspace.mergeHistory(
      ChannelHistory(
        channelId: 'alpha',
        messages: [_message('a-2', 'alpha', 3), _message('a-1', 'alpha', 1)],
        members: const [],
      ),
      replaceChannel: false,
    );

    expect(_idsIn(next, 'alpha'), ['a-1', 'a-2', 'a-3']);
    expect(_idsIn(next, 'beta'), ['b-1']);
  });

  test('a replacing page drops only what its own channel held', () {
    final workspace = _workspaceWith([
      _message('a-1', 'alpha', 1),
      _message('b-1', 'beta', 2),
    ]);

    final next = workspace.mergeHistory(
      ChannelHistory(
        channelId: 'alpha',
        messages: [_message('a-9', 'alpha', 9)],
        members: const [],
      ),
    );

    expect(_idsIn(next, 'alpha'), ['a-9']);
    expect(_idsIn(next, 'beta'), ['b-1']);
  });

  test('messages with the same time keep their order through a merge', () {
    final page = [for (var i = 0; i < 64; i++) _message('a-$i', 'alpha', 1)];
    final workspace = _workspaceWith(const []);

    final next = workspace.mergeHistory(
      ChannelHistory(channelId: 'alpha', messages: page, members: const []),
    );

    expect(_idsIn(next, 'alpha'), [for (final m in page) m.id]);
  });

  test('the flat view lists every channel, oldest first, after a change', () {
    final workspace = _workspaceWith([
      _message('b-1', 'beta', 2),
      _message('a-1', 'alpha', 4),
    ]);

    final next = workspace
        .upsertMessage(_message('b-2', 'beta', 6))
        .upsertMessage(_message('a-0', 'alpha', 1));

    expect(
      [for (final message in next.messages) message.id],
      ['a-0', 'b-1', 'a-1', 'b-2'],
    );
  });

  test('an update and a removal reach a message in any channel', () {
    final workspace = _workspaceWith([
      _message('a-1', 'alpha', 1),
      _message('b-1', 'beta', 2),
      _message('b-2', 'beta', 3),
    ]);

    final updated = workspace.updateMessage(
      'b-1',
      (message) => message.copyWith(body: 'edited'),
    );
    final removed = updated.removeMessages({'a-1', 'b-2'});

    expect(updated.messagesFor('beta').first.body, 'edited');
    expect(_idsIn(updated, 'beta'), ['b-1', 'b-2']);
    expect(_idsIn(removed, 'alpha'), isEmpty);
    expect(_idsIn(removed, 'beta'), ['b-1']);
    expect(
      identical(workspace.updateMessage('nope', (m) => m), workspace),
      isTrue,
    );
  });

  test('removing a channel removes only its messages', () {
    final workspace = _workspaceWith([
      _message('a-1', 'alpha', 1),
      _message('b-1', 'beta', 2),
    ]);

    final next = workspace.removeChannel('alpha');

    expect([for (final message in next.messages) message.id], ['b-1']);
  });
}

List<String> _idsIn(ChatWorkspace workspace, String channelId) => [
  for (final message in workspace.messagesFor(channelId)) message.id,
];

ChatMessage _message(
  String id,
  String channelId,
  int minute, {
  String body = 'hello',
}) => ChatMessage(
  id: id,
  channelId: channelId,
  authorId: 'lena',
  body: body,
  sentAt: DateTime.utc(2026, 1, 1, 0, minute),
);

ChatWorkspace _workspaceWith(List<ChatMessage> messages) => ChatWorkspace(
  spaces: const [
    CommunitySpace(
      id: 'guild-1',
      name: 'Forge',
      monogram: 'F',
      colorValue: 0xFF5865F2,
    ),
  ],
  channels: const [
    ConversationChannel(
      id: 'alpha',
      spaceId: 'guild-1',
      name: 'alpha',
      topic: '',
      kind: ChannelKind.text,
    ),
    ConversationChannel(
      id: 'beta',
      spaceId: 'guild-1',
      name: 'beta',
      topic: '',
      kind: ChannelKind.text,
    ),
  ],
  members: const [],
  messages: messages,
  currentMemberId: 'lena',
);
