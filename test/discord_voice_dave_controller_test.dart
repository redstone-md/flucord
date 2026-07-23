import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord/discord_voice_dave_controller.dart';
import 'package:flucord/src/domain/voice_dave.dart';

void main() {
  test('builds a key package after receiving the external sender', () {
    final service = _FakeDaveService();
    final controller = _controller(service)..activate(1);

    final commands = controller.acceptBinary(opcode: 25, payload: [1, 2, 3]);

    expect(service.sessions, hasLength(1));
    expect(service.sessions.single.externalSender, [1, 2, 3]);
    final keyPackage = commands.single as DiscordVoiceDaveBinaryCommand;
    expect(keyPackage.opcode, 26);
    expect(keyPackage.payload, [9, 8, 7]);
  });

  test('processes proposals using only connected recognized users', () {
    final service = _FakeDaveService();
    final controller = _controller(service)..activate(1);
    controller.acceptJson(11, {
      'user_ids': ['300', '200'],
    });

    final commands = controller.acceptBinary(opcode: 27, payload: [4, 5]);

    final session = service.sessions.single;
    expect(session.proposals, [4, 5]);
    expect(session.recognizedUsers, ['100', '200', '300']);
    final commit = commands.single as DiscordVoiceDaveBinaryCommand;
    expect(commit.opcode, 28);
    expect(commit.payload, [6, 6]);
  });

  test('acknowledges a valid commit transition', () {
    final service = _FakeDaveService();
    final controller = _controller(service)..activate(1);

    final commands = controller.acceptBinary(
      opcode: 29,
      payload: [0, 42, 7, 8],
    );

    expect(service.sessions.single.commit, [7, 8]);
    final ready = commands.single as DiscordVoiceDaveJsonCommand;
    expect(ready.opcode, 23);
    expect(ready.data, {'transition_id': 42});
  });

  test('recovers from an invalid welcome with a fresh session', () {
    final service = _FakeDaveService();
    final controller = _controller(service)..activate(1);
    controller.acceptBinary(opcode: 25, payload: [1, 2, 3]);
    service.sessions.single.welcomeResult = const DaveCommitResult(
      status: DaveCommitStatus.failed,
      rosterUserIds: [],
    );

    final commands = controller.acceptBinary(
      opcode: 30,
      payload: [0, 12, 3, 4],
    );

    expect(service.sessions, hasLength(2));
    expect(service.sessions.first.disposed, isTrue);
    expect(service.sessions.last.externalSender, [1, 2, 3]);
    expect(commands, hasLength(2));
    expect((commands.first as DiscordVoiceDaveJsonCommand).opcode, 31);
    expect((commands.last as DiscordVoiceDaveBinaryCommand).opcode, 26);
  });

  test('tracks downgrade prepare and execute transitions', () {
    final service = _FakeDaveService();
    final controller = _controller(service)..activate(1);

    final commands = controller.acceptJson(21, {
      'transition_id': 5,
      'protocol_version': 0,
    });
    controller.acceptJson(22, {'transition_id': 5});

    expect((commands.single as DiscordVoiceDaveJsonCommand).opcode, 23);
    expect(service.sessions.single.protocolVersion, 1);
  });
}

DiscordVoiceDaveController _controller(_FakeDaveService service) =>
    DiscordVoiceDaveController(
      daveService: service,
      channelId: '999',
      selfUserId: '100',
    );

final class _FakeDaveService implements VoiceDaveService {
  final List<_FakeDaveSession> sessions = [];

  @override
  int get maxProtocolVersion => 1;

  @override
  VoiceDaveSession createSession({
    required int protocolVersion,
    required String channelId,
    required String selfUserId,
  }) {
    final session = _FakeDaveSession(protocolVersion);
    sessions.add(session);
    return session;
  }
}

final class _FakeDaveSession implements VoiceDaveSession {
  _FakeDaveSession(this._protocolVersion);

  int _protocolVersion;
  List<int>? externalSender;
  List<int>? proposals;
  List<int>? commit;
  List<String>? recognizedUsers;
  bool disposed = false;
  DaveCommitResult commitResult = const DaveCommitResult(
    status: DaveCommitStatus.applied,
    rosterUserIds: ['100'],
  );
  DaveCommitResult welcomeResult = const DaveCommitResult(
    status: DaveCommitStatus.applied,
    rosterUserIds: ['100'],
  );

  @override
  int get protocolVersion => _protocolVersion;

  @override
  void setProtocolVersion(int version) => _protocolVersion = version;

  @override
  void setExternalSender(List<int> package) {
    externalSender = List.of(package);
  }

  @override
  List<int> createKeyPackage() => [9, 8, 7];

  @override
  List<int> processProposals({
    required List<int> proposals,
    required List<String> recognizedUserIds,
  }) {
    this.proposals = List.of(proposals);
    recognizedUsers = List.of(recognizedUserIds);
    return [6, 6];
  }

  @override
  DaveCommitResult processCommit(List<int> commit) {
    this.commit = List.of(commit);
    return commitResult;
  }

  @override
  DaveCommitResult processWelcome({
    required List<int> welcome,
    required List<String> recognizedUserIds,
  }) {
    recognizedUsers = List.of(recognizedUserIds);
    return welcomeResult;
  }

  @override
  void reset() => _protocolVersion = 0;

  @override
  void dispose() => disposed = true;
}
