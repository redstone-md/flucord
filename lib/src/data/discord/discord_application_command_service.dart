import '../../domain/application_command.dart';

/// The REST surface slash commands need.
abstract interface class DiscordApplicationCommandTransport {
  /// `GET /channels/{id}/application-commands/search`.
  Future<Map<String, Object?>> searchApplicationCommands(
    String channelId, {
    required String query,
  });

  /// `POST /interactions`.
  Future<void> postInteraction(Map<String, Object?> body);
}

/// Slash commands over the desktop-user transport.
///
/// A user session invokes differently from a bot: rather than naming a command
/// by id and letting Discord look it up, it echoes the command object back
/// inside `data`. That is why the search result is kept verbatim — anything
/// this client re-serialised from its own model would differ from what Discord
/// sent, and the invocation would be refused.
final class DiscordApplicationCommandService
    implements ApplicationCommandRepository {
  DiscordApplicationCommandService(
    this._transport, {
    required String? Function() sessionId,
    String Function()? nonce,
  }) : _sessionId = sessionId,
       _nonce = nonce;

  final DiscordApplicationCommandTransport _transport;

  /// The gateway session, read live: an interaction has to name it, and a
  /// reconnect replaces it without telling this service.
  final String? Function() _sessionId;
  final String Function()? _nonce;

  int _sequence = 0;

  @override
  Future<List<ApplicationCommand>> searchCommands(
    String channelId, {
    String query = '',
  }) async {
    final payload = await _transport.searchApplicationCommands(
      channelId,
      query: query.trim(),
    );
    return [
      for (final raw in _objects(payload['application_commands']))
        ?readCommand(raw),
    ];
  }

  @override
  Future<void> invoke(ApplicationCommandInvocation invocation) async {
    final sessionId = _sessionId();
    if (sessionId == null || sessionId.isEmpty) {
      throw StateError('The gateway session is not established');
    }
    if (!invocation.isComplete) {
      throw ArgumentError('The command is missing a required option');
    }
    final command = invocation.command;
    await _transport.postInteraction({
      'type': 2,
      'application_id': command.applicationId,
      'channel_id': invocation.channelId,
      'guild_id': ?invocation.guildId,
      'session_id': sessionId,
      'nonce': _nextNonce(),
      'data': {
        'version': command.version,
        'id': command.id,
        'name': command.name,
        'type': command.type.wireValue,
        'options': invocation.optionPayload,
        // Verbatim, for the reason on the class.
        'application_command': command.raw,
        'attachments': const <Object?>[],
      },
    });
  }

  /// Maps a command, skipping one that cannot be invoked.
  ///
  /// A command with no version is one Discord would refuse: the field is how
  /// it decides whether the caller is holding a current definition.
  static ApplicationCommand? readCommand(Map<String, Object?> payload) {
    final id = payload['id'];
    final applicationId = payload['application_id'];
    final name = payload['name'];
    if (id is! String || id.isEmpty) return null;
    if (applicationId is! String || applicationId.isEmpty) return null;
    if (name is! String || name.isEmpty) return null;
    final version = payload['version'];
    if (version is! String || version.isEmpty) return null;
    return ApplicationCommand(
      id: id,
      applicationId: applicationId,
      name: name,
      version: version,
      description: payload['description'] is String
          ? payload['description']! as String
          : '',
      type: ApplicationCommandType.fromWire(payload['type']),
      options: [
        for (final raw in _objects(payload['options'])) ?readOption(raw),
      ],
      raw: Map<String, Object?>.unmodifiable(payload),
    );
  }

  static ApplicationCommandOption? readOption(Map<String, Object?> payload) {
    final name = payload['name'];
    final type = payload['type'];
    if (name is! String || name.isEmpty || type is! int) return null;
    return ApplicationCommandOption(
      name: name,
      type: type,
      description: payload['description'] is String
          ? payload['description']! as String
          : '',
      isRequired: payload['required'] == true,
    );
  }

  /// A nonce per invocation, so a retry cannot be taken for a second call.
  String _nextNonce() =>
      _nonce?.call() ??
      '${DateTime.now().microsecondsSinceEpoch}${_sequence++}';

  static List<Map<String, Object?>> _objects(Object? value) => value is List
      ? value
            .whereType<Map>()
            .map((entry) => entry.cast<String, Object?>())
            .toList(growable: false)
      : const [];
}
