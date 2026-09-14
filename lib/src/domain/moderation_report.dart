part 'moderation_report_elements.dart';
part 'moderation_report_flow.dart';

/// The authenticated in-app report types, by their wire name.
///
/// The type is a name string on the wire, never a number, and it appears twice
/// in a submission: once in the path and once as `name` in the body.
enum ReportType {
  message('message'),
  user('user'),
  guild('guild'),
  firstDm('first_dm'),
  stageChannel('stage_channel'),
  guildScheduledEvent('guild_scheduled_event'),
  guildDirectoryEntry('guild_directory_entry'),
  guildDiscovery('guild_discovery'),
  application('application'),
  widget('widget');

  const ReportType(this.wireName);

  final String wireName;
}

/// What is being reported, and the entity keys that identify it.
///
/// The renderer spreads a "reset" object that sets every entity key to
/// `undefined` and then overwrites the relevant ones. `JSON.stringify` drops
/// `undefined`, so omitting the irrelevant keys — which is all a Dart map can
/// do — produces the identical body.
sealed class ReportTarget {
  const ReportTarget();

  ReportType get type;

  Map<String, Object?> toEntityKeys();
}

final class MessageReportTarget extends ReportTarget {
  const MessageReportTarget({
    required this.channelId,
    required this.messageId,
    this.isFirstDirectMessage = false,
  });

  final String channelId;
  final String messageId;

  /// A first DM from a stranger has its own report type with its own menu.
  final bool isFirstDirectMessage;

  @override
  ReportType get type =>
      isFirstDirectMessage ? ReportType.firstDm : ReportType.message;

  @override
  Map<String, Object?> toEntityKeys() => {
    'channel_id': channelId,
    'message_id': messageId,
  };
}

final class UserReportTarget extends ReportTarget {
  const UserReportTarget({required this.userId, this.guildId});

  final String userId;

  /// The guild the report was raised from. Optional, and omitted rather than
  /// nulled when the report came from a DM.
  final String? guildId;

  @override
  ReportType get type => ReportType.user;

  @override
  Map<String, Object?> toEntityKeys() => {
    'user_id': userId,
    if (guildId != null) 'guild_id': guildId,
  };
}

final class GuildReportTarget extends ReportTarget {
  const GuildReportTarget(this.guildId);

  final String guildId;

  @override
  ReportType get type => ReportType.guild;

  @override
  Map<String, Object?> toEntityKeys() => {'guild_id': guildId};
}

/// What a node's primary button does.
enum ReportButtonType {
  submit('submit'),
  next('next'),
  done('done'),
  cancel('cancel'),
  unknown('');

  const ReportButtonType(this.wireName);

  final String wireName;

  static ReportButtonType fromWire(Object? value) {
    for (final candidate in values) {
      if (candidate != unknown && candidate.wireName == value) return candidate;
    }
    return unknown;
  }
}

final class ReportButton {
  const ReportButton({required this.type, this.target});

  final ReportButtonType type;

  /// The node id a `next` button leads to.
  final String? target;
}

/// A branch offered by a node: a label and the node it leads to.
final class ReportChoice {
  const ReportChoice({required this.label, required this.nodeId});

  final String label;
  final String nodeId;
}

/// One node of the server-supplied form graph.
final class ReportNode {
  const ReportNode({
    required this.id,
    this.key,
    this.header,
    this.subheader,
    this.info,
    this.reportSubtype,
    this.isAutoSubmit = false,
    this.button,
    this.choices = const [],
    this.elements = const [],
  });

  final String id;

  /// A stable symbolic name. A key ending in `_SUBMIT` marks a terminal-ish
  /// node.
  final String? key;

  final String? header;
  final String? subheader;
  final String? info;

  /// The report subtype this node attributes the report to, e.g. `sub_spam`.
  final String? reportSubtype;

  /// The node submits on arrival, with no button press.
  final bool isAutoSubmit;

  final ReportButton? button;
  final List<ReportChoice> choices;
  final List<ReportElement> elements;

  /// The one multi-select this node carries, or `null`. The submit fold writes
  /// at most one checkbox bag per history entry, so more than one would be
  /// unrepresentable on the wire anyway.
  ReportElement? get multiSelect => elements
      .where((element) => element.type == ReportElementType.checkbox)
      .firstOrNull;

  /// Inputs whose value goes into the flat `elements` bag as a string.
  Iterable<ReportElement> get textInputs =>
      elements.where((element) => element.type.isTextInput);

  /// A node whose only job is to forward to another one.
  ReportElement? get skip => elements
      .where((element) => element.type == ReportElementType.skip)
      .firstOrNull;
}

/// The menu `GET /reporting/menu/{type}` returns.
final class ReportMenu {
  const ReportMenu({
    required this.nodes,
    required this.rootNodeId,
    required this.successNodeId,
    required this.failNodeId,
    this.version,
    this.variant,
    this.language,
  });

  final Map<String, ReportNode> nodes;
  final String rootNodeId;
  final String successNodeId;
  final String failNodeId;

  /// Echoed verbatim in the submit body, whatever type it arrived as.
  final Object? version;

  final String? variant;
  final String? language;

  ReportNode? operator [](String nodeId) => nodes[nodeId];
}
