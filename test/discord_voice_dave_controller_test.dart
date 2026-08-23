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

  test('passes audio through until the group key exists', () {
    final service = _FakeDaveService();
    final controller = _controller(service)..activate(1);
    controller.assignAudioSsrc(42);

    // Discord announces v1 on the session description; the MLS group is only
    // joined once the external sender, the key packages and a commit have been
    // through. Encrypting in between fails with missingKeyRatchet, which the
    // room reported as "voice ran into a problem" on every single frame.
    expect(service.encryptors.single.isPassthrough, isTrue);

    controller.acceptBinary(opcode: 29, payload: [0, 42, 7, 8]);

    expect(service.encryptors.single.isPassthrough, isFalse);
  });

  test('a rebuilt session goes back to passing through', () {
    final service = _FakeDaveService();
    final controller = _controller(service)..activate(1);
    controller.assignAudioSsrc(42);
    controller.acceptBinary(opcode: 29, payload: [0, 42, 7, 8]);
    expect(service.encryptors.single.isPassthrough, isFalse);

    // A failed commit rebuilds the session: this client is outside the group
    // again, and a key it still believed in is one nobody in the room has.
    service.sessions.single.commitResult = const DaveCommitResult(
      status: DaveCommitStatus.failed,
      rosterUserIds: [],
    );
    controller.acceptBinary(opcode: 29, payload: [0, 43, 1, 2]);
    controller.assignAudioSsrc(42);

    expect(service.encryptors.last.isPassthrough, isTrue);
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
    expect(service.encryptors.single.keyUserId, '100');
  });

  test('rotates roster ratchets and releases departed decryptors', () {
    final service = _FakeDaveService();
    final controller = _controller(service)..activate(1);
    controller.assignAudioSsrc(42);
    final session = service.sessions.single;
    session.commitResult = const DaveCommitResult(
      status: DaveCommitStatus.applied,
      rosterUserIds: ['100', '200'],
    );

    controller.acceptBinary(opcode: 29, payload: [0, 1, 7]);

    expect(service.encryptors.single.ssrc, 42);
    expect(service.encryptors.single.keyUserId, '100');
    expect(service.decryptors.single.keyUserId, '200');
    expect(session.ratchets.every((ratchet) => ratchet.disposed), isTrue);
    expect(controller.encryptAudioFrame([8, 9]), [8, 9]);
    expect(
      controller.decryptAudioFrame(userId: '200', encryptedFrame: [6, 7]),
      [6, 7],
    );

    session.commitResult = const DaveCommitResult(
      status: DaveCommitStatus.applied,
      rosterUserIds: ['100'],
    );
    controller.acceptBinary(opcode: 29, payload: [0, 2, 8]);

    expect(service.decryptors.single.disposed, isTrue);
    expect(
      () => controller.decryptAudioFrame(userId: '200', encryptedFrame: [6, 7]),
      throwsStateError,
    );
  });

  test('a roster transition without this account keeps the last epoch', () {
    final service = _FakeDaveService();
    final controller = _controller(service)..activate(1);
    controller.assignAudioSsrc(42);
    final session = service.sessions.single;
    session.commitResult = const DaveCommitResult(
      status: DaveCommitStatus.applied,
      rosterUserIds: ['100', '200'],
    );
    controller.acceptBinary(opcode: 29, payload: [0, 1, 7]);
    expect(service.encryptors.single.isPassthrough, isFalse);

    // Removal is ordinary protocol, not a failure: a re-add with a different
    // key package is usually already in flight, and the previous epoch's
    // ratchets stay valid until execute_transition says otherwise.
    session.commitResult = const DaveCommitResult(
      status: DaveCommitStatus.applied,
      rosterUserIds: ['200'],
    );
    final commands = controller.acceptBinary(opcode: 29, payload: [0, 2, 8]);

    expect(commands.single, isA<DiscordVoiceDaveJsonCommand>());
    expect(service.encryptors.single.isPassthrough, isFalse);

    // And the re-add re-keys as usual once the roster names this account
    // again.
    session.commitResult = const DaveCommitResult(
      status: DaveCommitStatus.applied,
      rosterUserIds: ['100'],
    );
    controller.acceptBinary(opcode: 29, payload: [0, 3, 9]);
    expect(service.encryptors.single.keyUserId, '100');
  });

  test('recovers from an invalid welcome with a fresh session', () {
    final service = _FakeDaveService();
    final controller = _controller(service)..activate(1);
    controller.assignAudioSsrc(42);
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
    expect(service.encryptors.single.disposed, isTrue);
    expect(service.sessions.last.externalSender, [1, 2, 3]);
    expect(commands, hasLength(2));
    expect((commands.first as DiscordVoiceDaveJsonCommand).opcode, 31);
    expect((commands.last as DiscordVoiceDaveBinaryCommand).opcode, 26);
  });

  test('tracks downgrade prepare and execute transitions', () {
    final service = _FakeDaveService();
    final controller = _controller(service)..activate(1);
    controller.assignAudioSsrc(42);

    final commands = controller.acceptJson(21, {
      'transition_id': 5,
      'protocol_version': 0,
    });
    controller.acceptJson(22, {'transition_id': 5});

    expect((commands.single as DiscordVoiceDaveJsonCommand).opcode, 23);
    expect(service.sessions.single.protocolVersion, 1);
    expect(service.encryptors.single.isPassthrough, isTrue);
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
  final List<_FakeDaveEncryptor> encryptors = [];
  final List<_FakeDaveDecryptor> decryptors = [];

  @override
  int get maxProtocolVersion => 1;

  @override
  VoiceDaveEncryptor createEncryptor() {
    final encryptor = _FakeDaveEncryptor();
    encryptors.add(encryptor);
    return encryptor;
  }

  @override
  VoiceDaveDecryptor createDecryptor() {
    final decryptor = _FakeDaveDecryptor();
    decryptors.add(decryptor);
    return decryptor;
  }

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
  final List<_FakeDaveKeyRatchet> ratchets = [];
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
  VoiceDaveKeyRatchet getKeyRatchet(String userId) {
    final ratchet = _FakeDaveKeyRatchet(userId);
    ratchets.add(ratchet);
    return ratchet;
  }

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

final class _FakeDaveKeyRatchet implements VoiceDaveKeyRatchet {
  _FakeDaveKeyRatchet(this.userId);

  final String userId;
  bool disposed = false;

  @override
  void dispose() => disposed = true;
}

final class _FakeDaveEncryptor implements VoiceDaveEncryptor {
  String? keyUserId;
  int? ssrc;
  bool _passthrough = false;
  bool disposed = false;

  @override
  int get protocolVersion => keyUserId == null ? 0 : 1;

  @override
  bool get hasKeyRatchet => keyUserId != null;

  @override
  bool get isPassthrough => _passthrough;

  @override
  void assignSsrcToCodec(int ssrc, DaveMediaCodec codec) {
    this.ssrc = ssrc;
  }

  @override
  List<int> encrypt({
    required DaveMediaType mediaType,
    required int ssrc,
    required List<int> frame,
  }) => List.of(frame);

  @override
  void setKeyRatchet(VoiceDaveKeyRatchet keyRatchet) {
    keyUserId = (keyRatchet as _FakeDaveKeyRatchet).userId;
  }

  @override
  void setPassthrough(bool enabled) => _passthrough = enabled;

  @override
  void dispose() => disposed = true;
}

final class _FakeDaveDecryptor implements VoiceDaveDecryptor {
  String? keyUserId;
  bool isPassthrough = false;
  bool disposed = false;

  @override
  List<int> decrypt({
    required DaveMediaType mediaType,
    required List<int> encryptedFrame,
  }) => List.of(encryptedFrame);

  @override
  void transitionToKeyRatchet(VoiceDaveKeyRatchet keyRatchet) {
    keyUserId = (keyRatchet as _FakeDaveKeyRatchet).userId;
  }

  @override
  void transitionToPassthrough(bool enabled) => isPassthrough = enabled;

  @override
  void dispose() => disposed = true;
}
