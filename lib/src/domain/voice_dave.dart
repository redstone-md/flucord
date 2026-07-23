enum DaveCommitStatus { applied, ignored, failed }

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
  void reset();
  void dispose();
}
