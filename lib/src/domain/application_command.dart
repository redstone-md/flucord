/// One slash command, as the channel's command index lists it.
final class ApplicationCommand {
  const ApplicationCommand({
    required this.id,
    required this.applicationId,
    required this.name,
    this.version = '',
    this.description = '',
    this.type = ApplicationCommandType.chatInput,
    this.options = const [],
    this.raw = const {},
  });

  final String id;
  final String applicationId;
  final String name;
  final String description;

  /// Discord bumps this whenever the command's shape changes, and rejects an
  /// invocation carrying a stale one.
  final String version;

  final ApplicationCommandType type;
  final List<ApplicationCommandOption> options;

  /// The command object exactly as Discord served it.
  ///
  /// A user-session invocation echoes the whole command back rather than
  /// naming it by id, so the payload has to be kept verbatim: re-serialising
  /// from the fields above would drop everything this client does not model
  /// and Discord would reject the difference.
  final Map<String, Object?> raw;

  /// The options a caller may fill in, in the order Discord lists them.
  List<ApplicationCommandOption> get inputs => options
      .where((option) => !option.isSubcommandLike)
      .toList(growable: false);

  bool get hasRequiredInputs => inputs.any((option) => option.isRequired);
}

/// `ApplicationCommandType`, as Discord numbers it.
enum ApplicationCommandType {
  chatInput(1),
  user(2),
  message(3),
  primaryEntryPoint(4);

  const ApplicationCommandType(this.wireValue);

  final int wireValue;

  static ApplicationCommandType fromWire(Object? value) => switch (value) {
    2 => ApplicationCommandType.user,
    3 => ApplicationCommandType.message,
    4 => ApplicationCommandType.primaryEntryPoint,
    _ => ApplicationCommandType.chatInput,
  };
}

/// One argument of a command.
final class ApplicationCommandOption {
  const ApplicationCommandOption({
    required this.name,
    required this.type,
    this.description = '',
    this.isRequired = false,
  });

  final String name;
  final int type;
  final String description;
  final bool isRequired;

  /// Types 1 and 2 are a subcommand and a subcommand group: they are not
  /// values a caller types, they are more command underneath.
  bool get isSubcommandLike => type == 1 || type == 2;

  /// Whether Discord expects a string rather than a number or a snowflake.
  bool get isText => type == 3;
}

/// A command invocation, before it is sent.
final class ApplicationCommandInvocation {
  const ApplicationCommandInvocation({
    required this.command,
    required this.channelId,
    this.guildId,
    this.values = const {},
    this.targetId,
  });

  final ApplicationCommand command;
  final String channelId;

  /// Absent in a DM, where Discord expects no guild at all.
  final String? guildId;

  /// Option name to value, for the options the caller filled in.
  final Map<String, Object?> values;

  /// The user or message a context-menu command was invoked on.
  ///
  /// Discord distinguishes the three command types by what they act on rather
  /// than by a different route: a chat-input command carries options, and the
  /// two context-menu kinds carry a target instead.
  final String? targetId;

  /// The `data.options` array Discord expects: only what was filled in, in
  /// the command's own order so the receiving application reads them the way
  /// it declared them.
  List<Map<String, Object?>> get optionPayload => [
    for (final option in command.inputs)
      if (values[option.name] case final value?)
        {'type': option.type, 'name': option.name, 'value': value},
  ];

  /// Whether every required option has a value.
  ///
  /// A context-menu command declares no options at all — its argument is the
  /// thing it was invoked on — so it is complete as soon as it has a target.
  bool get isComplete => command.type == ApplicationCommandType.chatInput
      ? command.inputs
            .where((option) => option.isRequired)
            .every((option) => values[option.name] != null)
      : targetId != null;
}

/// Slash commands in a channel, and running them.
abstract interface class ApplicationCommandRepository {
  /// Commands available in [channelId], optionally filtered by [query].
  ///
  /// [type] selects which of the three kinds are listed: chat-input commands
  /// for the composer, and the two context-menu kinds for the surfaces that
  /// act on a user or a message.
  Future<List<ApplicationCommand>> searchCommands(
    String channelId, {
    String query = '',
    ApplicationCommandType type = ApplicationCommandType.chatInput,
  });

  /// Runs [invocation]. Completes when Discord accepts it, not when the
  /// application answers — the reply arrives as a message.
  Future<void> invoke(ApplicationCommandInvocation invocation);
}
