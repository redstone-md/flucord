enum DaveCommitStatus { applied, ignored, failed }

enum DaveMediaType { audio, video }

enum DaveMediaCodec { unknown, opus, vp8, vp9, h264, h265, av1 }

enum DaveFrameFailure {
  encryptionFailure,
  decryptionFailure,
  missingKeyRatchet,
  missingCryptor,
  tooManyAttempts,
  invalidNonce,
  unknown,
}

final class DaveFrameException implements Exception {
  const DaveFrameException(this.failure, {required this.operation});

  final DaveFrameFailure failure;
  final String operation;

  @override
  String toString() => 'DAVE $operation failed: ${failure.name}';
}

final class DaveCommitResult {
  const DaveCommitResult({required this.status, required this.rosterUserIds});

  final DaveCommitStatus status;
  final List<String> rosterUserIds;
}

abstract interface class VoiceDaveService {
  int get maxProtocolVersion;

  VoiceDaveSession createSession({
    required int protocolVersion,
    required String channelId,
    required String selfUserId,
  });
  VoiceDaveEncryptor createEncryptor();
  VoiceDaveDecryptor createDecryptor();
}

abstract interface class VoiceDaveSession {
  int get protocolVersion;

  void setProtocolVersion(int version);
  void setExternalSender(List<int> package);
  List<int> createKeyPackage();
  List<int> processProposals({
    required List<int> proposals,
    required List<String> recognizedUserIds,
  });
  DaveCommitResult processCommit(List<int> commit);
  DaveCommitResult processWelcome({
    required List<int> welcome,
    required List<String> recognizedUserIds,
  });
  VoiceDaveKeyRatchet getKeyRatchet(String userId);
  void reset();
  void dispose();
}

abstract interface class VoiceDaveKeyRatchet {
  void dispose();
}

abstract interface class VoiceDaveEncryptor {
  int get protocolVersion;
  bool get hasKeyRatchet;
  bool get isPassthrough;

  void setKeyRatchet(VoiceDaveKeyRatchet keyRatchet);
  void setPassthrough(bool enabled);
  void assignSsrcToCodec(int ssrc, DaveMediaCodec codec);
  List<int> encrypt({
    required DaveMediaType mediaType,
    required int ssrc,
    required List<int> frame,
  });
  void dispose();
}

abstract interface class VoiceDaveDecryptor {
  void transitionToKeyRatchet(VoiceDaveKeyRatchet keyRatchet);
  void transitionToPassthrough(bool enabled);
  List<int> decrypt({
    required DaveMediaType mediaType,
    required List<int> encryptedFrame,
  });
  void dispose();
}
