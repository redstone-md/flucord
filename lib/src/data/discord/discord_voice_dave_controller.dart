import 'dart:typed_data';

import '../../domain/voice_dave.dart';

sealed class DiscordVoiceDaveCommand {
  const DiscordVoiceDaveCommand();
}

final class DiscordVoiceDaveJsonCommand extends DiscordVoiceDaveCommand {
  const DiscordVoiceDaveJsonCommand({required this.opcode, required this.data});

  final int opcode;
  final Map<String, Object?> data;
}

final class DiscordVoiceDaveBinaryCommand extends DiscordVoiceDaveCommand {
  const DiscordVoiceDaveBinaryCommand({
    required this.opcode,
    required this.payload,
  });

  final int opcode;
  final List<int> payload;
}

final class DiscordVoiceDaveController {
  DiscordVoiceDaveController({
    required VoiceDaveService daveService,
    required this.channelId,
    required this.selfUserId,
  }) : _service = daveService,
       _recognizedUserIds = {selfUserId};

  final VoiceDaveService _service;
  final String channelId;
  final String selfUserId;
  final Set<String> _recognizedUserIds;
  VoiceDaveSession? _session;
  List<int>? _externalSender;
  int _protocolVersion = 0;
  int? _pendingTransitionId;
  int? _pendingProtocolVersion;

  void activate(int protocolVersion) {
    if (protocolVersion < 0 || protocolVersion > _service.maxProtocolVersion) {
      throw StateError('Discord selected an unsupported DAVE version');
    }
    _protocolVersion = protocolVersion;
    if (protocolVersion > 0) {
      _ensureSession(protocolVersion).setProtocolVersion(protocolVersion);
    }
  }

  List<DiscordVoiceDaveCommand> acceptJson(
    int opcode,
    Map<String, Object?> data,
  ) {
    switch (opcode) {
      case 11:
        final userIds = data['user_ids'];
        if (userIds is List) {
          _recognizedUserIds.addAll(userIds.whereType<String>());
        }
      case 13:
        final userId = data['user_id'];
        if (userId is String && userId != selfUserId) {
          _recognizedUserIds.remove(userId);
        }
      case 21:
        return _prepareTransition(data);
      case 22:
        _executeTransition(data);
      case 24:
        return _prepareEpoch(data);
    }
    return const [];
  }

  List<DiscordVoiceDaveCommand> acceptBinary({
    required int opcode,
    required List<int> payload,
  }) {
    switch (opcode) {
      case 25:
        return _acceptExternalSender(payload);
      case 27:
        return _acceptProposals(payload);
      case 29:
        return _acceptCommit(payload);
      case 30:
        return _acceptWelcome(payload);
      default:
        return const [];
    }
  }

  List<DiscordVoiceDaveCommand> _prepareTransition(Map<String, Object?> data) {
    final transitionId = data['transition_id'];
    final protocolVersion = data['protocol_version'];
    if (transitionId is! int || protocolVersion is! int) return const [];
    _pendingTransitionId = transitionId;
    _pendingProtocolVersion = protocolVersion;
    return [
      DiscordVoiceDaveJsonCommand(
        opcode: 23,
        data: {'transition_id': transitionId},
      ),
    ];
  }

  void _executeTransition(Map<String, Object?> data) {
    final transitionId = data['transition_id'];
    if (transitionId is! int || transitionId != _pendingTransitionId) return;
    final protocolVersion = _pendingProtocolVersion;
    if (protocolVersion != null) {
      _protocolVersion = protocolVersion;
    }
    _pendingTransitionId = null;
    _pendingProtocolVersion = null;
  }

  List<DiscordVoiceDaveCommand> _prepareEpoch(Map<String, Object?> data) {
    final protocolVersion = data['protocol_version'];
    final epoch = data['epoch'];
    if (protocolVersion is! int || epoch is! int || protocolVersion <= 0) {
      return const [];
    }
    _protocolVersion = protocolVersion;
    _ensureSession(protocolVersion).setProtocolVersion(protocolVersion);
    return epoch == 1 ? _keyPackageCommands() : const [];
  }

  List<DiscordVoiceDaveCommand> _acceptExternalSender(List<int> payload) {
    _externalSender = List<int>.unmodifiable(payload);
    final version = _protocolVersion > 0
        ? _protocolVersion
        : _service.maxProtocolVersion;
    _ensureSession(version).setExternalSender(payload);
    return _keyPackageCommands();
  }

  List<DiscordVoiceDaveCommand> _acceptProposals(List<int> payload) {
    final output = _requiredSession().processProposals(
      proposals: payload,
      recognizedUserIds: _recognizedUsers,
    );
    if (output.isEmpty) return const [];
    return [DiscordVoiceDaveBinaryCommand(opcode: 28, payload: output)];
  }

  List<DiscordVoiceDaveCommand> _acceptCommit(List<int> payload) {
    if (payload.length < 2) return const [];
    final transitionId = _transitionId(payload);
    final result = _requiredSession().processCommit(payload.sublist(2));
    if (result.status == DaveCommitStatus.failed) {
      return _recoverFromInvalid(transitionId);
    }
    _pendingTransitionId = transitionId;
    _pendingProtocolVersion = _protocolVersion;
    return [_readyCommand(transitionId)];
  }

  List<DiscordVoiceDaveCommand> _acceptWelcome(List<int> payload) {
    if (payload.length < 2) return const [];
    final transitionId = _transitionId(payload);
    final result = _requiredSession().processWelcome(
      welcome: payload.sublist(2),
      recognizedUserIds: _recognizedUsers,
    );
    if (result.status == DaveCommitStatus.failed) {
      return _recoverFromInvalid(transitionId);
    }
    _pendingTransitionId = transitionId;
    _pendingProtocolVersion = _protocolVersion;
    return [_readyCommand(transitionId)];
  }

  List<DiscordVoiceDaveCommand> _recoverFromInvalid(int transitionId) {
    if (_protocolVersion > 0) _replaceSession(_protocolVersion);
    return [
      DiscordVoiceDaveJsonCommand(
        opcode: 31,
        data: {'transition_id': transitionId},
      ),
      ..._keyPackageCommands(),
    ];
  }

  List<DiscordVoiceDaveCommand> _keyPackageCommands() {
    final sender = _externalSender;
    final session = _session;
    if (sender == null || session == null) return const [];
    final keyPackage = session.createKeyPackage();
    if (keyPackage.isEmpty) return const [];
    return [DiscordVoiceDaveBinaryCommand(opcode: 26, payload: keyPackage)];
  }

  DiscordVoiceDaveJsonCommand _readyCommand(int transitionId) =>
      DiscordVoiceDaveJsonCommand(
        opcode: 23,
        data: {'transition_id': transitionId},
      );

  int _transitionId(List<int> payload) => ByteData.sublistView(
    Uint8List.fromList(payload),
  ).getUint16(0, Endian.big);

  List<String> get _recognizedUsers {
    final users = _recognizedUserIds.toList(growable: false)..sort();
    return users;
  }

  VoiceDaveSession _requiredSession() {
    final session = _session;
    if (session == null) throw StateError('DAVE session is not initialized');
    return session;
  }

  VoiceDaveSession _ensureSession(int protocolVersion) =>
      _session ??= _createSession(protocolVersion);

  void _replaceSession(int protocolVersion) {
    _session?.dispose();
    _session = _createSession(protocolVersion);
    final sender = _externalSender;
    if (sender != null) _session!.setExternalSender(sender);
  }

  VoiceDaveSession _createSession(int protocolVersion) =>
      _service.createSession(
        protocolVersion: protocolVersion,
        channelId: channelId,
        selfUserId: selfUserId,
      );

  void dispose() {
    _session?.dispose();
    _session = null;
  }
}
