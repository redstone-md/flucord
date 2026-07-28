import 'dart:async';

import '../../domain/message_component.dart';

/// Reads the component tree Discord hangs off a message.
abstract final class DiscordMessageComponentMapper {
  /// Every actionable row in [payload], flattened out of whatever nesting the
  /// message uses.
  ///
  /// Components V2 wraps rows in containers and sections, so the tree is
  /// walked rather than assumed two deep: a message whose buttons sit inside a
  /// container would otherwise render as having none.
  static List<MessageActionRow> readRows(Object? payload) {
    final rows = <MessageActionRow>[];
    _walk(payload, rows);
    return rows;
  }

  static void _walk(Object? node, List<MessageActionRow> rows) {
    for (final entry in _objects(node)) {
      final type = entry['type'];
      if (type == 1) {
        final row = MessageActionRow(
          components: [
            for (final raw in _objects(entry['components']))
              ?readComponent(raw),
          ],
        );
        if (!row.isEmpty) rows.add(row);
        continue;
      }
      // Anything else that holds components is a layout container.
      _walk(entry['components'], rows);
    }
  }

  /// Maps a button or select, skipping anything else.
  static MessageComponent? readComponent(Map<String, Object?> payload) {
    final type = payload['type'];
    if (type is! int) return null;
    final isButton = type == 2;
    // Type 4 falls inside the select range but is a modal's text input.
    final isSelect = type == 3 || (type >= 5 && type <= 8);
    if (!isButton && !isSelect) return null;
    final customId = payload['custom_id'];
    final url = payload['url'];
    final style = MessageButtonStyle.fromWire(payload['style']);
    // A link button carries a url instead of a custom id; anything else with
    // neither cannot be acted on and is not worth a row.
    if (style == MessageButtonStyle.link) {
      if (url is! String || url.isEmpty) return null;
    } else if (customId is! String || customId.isEmpty) {
      return null;
    }
    final emoji = payload['emoji'];
    return MessageComponent(
      type: type,
      customId: customId is String ? customId : '',
      label: payload['label'] is String ? payload['label']! as String : '',
      style: style,
      url: url is String ? url : null,
      isDisabled: payload['disabled'] == true,
      emojiName: emoji is Map && emoji['name'] is String
          ? emoji['name']! as String
          : null,
      placeholder: payload['placeholder'] is String
          ? payload['placeholder']! as String
          : '',
      options: [
        for (final raw in _objects(payload['options'])) ?readOption(raw),
      ],
      minValues: _int(payload['min_values'], 1),
      maxValues: _int(payload['max_values'], 1),
    );
  }

  static MessageSelectOption? readOption(Map<String, Object?> payload) {
    final value = payload['value'];
    if (value is! String || value.isEmpty) return null;
    return MessageSelectOption(
      value: value,
      label: payload['label'] is String ? payload['label']! as String : '',
      description: payload['description'] is String
          ? payload['description']! as String
          : '',
      isDefault: payload['default'] == true,
    );
  }

  /// Reads an `INTERACTION_MODAL_CREATE`, or `null` when it carries no fields
  /// this client can render.
  static ModalDefinition? readModal(Map<String, Object?> payload) {
    final customId = payload['custom_id'];
    if (customId is! String || customId.isEmpty) return null;
    final fields = <ModalField>[];
    for (final row in _objects(payload['components'])) {
      for (final raw in _objects(row['components'])) {
        final field = readField(raw);
        if (field != null) fields.add(field);
      }
    }
    if (fields.isEmpty) return null;
    return ModalDefinition(
      customId: customId,
      title: payload['title'] is String ? payload['title']! as String : '',
      fields: fields,
      applicationId: payload['application_id'] is String
          ? payload['application_id']! as String
          : '',
      nonce: payload['nonce'] is String ? payload['nonce']! as String : '',
    );
  }

  static ModalField? readField(Map<String, Object?> payload) {
    // Type 4 is the only input a modal may hold.
    if (payload['type'] != 4) return null;
    final customId = payload['custom_id'];
    if (customId is! String || customId.isEmpty) return null;
    return ModalField(
      customId: customId,
      label: payload['label'] is String ? payload['label']! as String : '',
      placeholder: payload['placeholder'] is String
          ? payload['placeholder']! as String
          : '',
      value: payload['value'] is String ? payload['value']! as String : '',
      isRequired: payload['required'] == true,
      isParagraph: payload['style'] == 2,
      minLength: _int(payload['min_length'], 0),
      maxLength: _int(payload['max_length'], 0),
    );
  }

  static int _int(Object? value, int fallback) =>
      value is int ? value : fallback;

  static List<Map<String, Object?>> _objects(Object? value) => value is List
      ? value
            .whereType<Map>()
            .map((entry) => entry.cast<String, Object?>())
            .toList(growable: false)
      : const [];
}

/// The REST surface component interactions need.
abstract interface class DiscordComponentTransport {
  /// `POST /interactions`.
  Future<void> postInteraction(Map<String, Object?> body);
}

/// Pressing components and submitting modals.
final class DiscordMessageComponentService
    implements MessageComponentRepository {
  DiscordMessageComponentService(
    this._transport, {
    required String? Function() sessionId,
    String Function()? nonce,
  }) : _sessionId = sessionId,
       _nonce = nonce;

  final DiscordComponentTransport _transport;
  final String? Function() _sessionId;
  final String Function()? _nonce;
  final StreamController<ModalDefinition> _modals =
      StreamController.broadcast();

  int _sequence = 0;

  @override
  Stream<ModalDefinition> get modals => _modals.stream;

  @override
  Future<void> activate({
    required String channelId,
    required String messageId,
    required String applicationId,
    required MessageComponent component,
    String? guildId,
    int messageFlags = 0,
    List<String> values = const [],
  }) async {
    // A link button is a hyperlink: Discord is never told it was pressed.
    if (component.isLink || !component.isActionable) {
      throw ArgumentError('That component cannot be activated');
    }
    await _transport.postInteraction({
      'type': 3,
      'application_id': applicationId,
      'channel_id': channelId,
      'guild_id': ?guildId,
      'message_id': messageId,
      'message_flags': messageFlags,
      'session_id': _requireSession(),
      'nonce': _nextNonce(),
      'data': {
        'component_type': component.type,
        'custom_id': component.customId,
        if (component.isSelect) 'values': values,
      },
    });
  }

  @override
  Future<void> submitModal(
    ModalDefinition modal, {
    required String channelId,
    required Map<String, String> values,
    String? guildId,
  }) async {
    final missing = modal.fields
        .where((field) => field.isRequired)
        .where((field) => (values[field.customId] ?? '').trim().isEmpty);
    if (missing.isNotEmpty) {
      throw ArgumentError('The modal is missing a required field');
    }
    await _transport.postInteraction({
      'type': 5,
      'application_id': modal.applicationId,
      'channel_id': channelId,
      'guild_id': ?guildId,
      'session_id': _requireSession(),
      // The submission reuses the nonce the modal was opened with: it is how
      // Discord ties the answer to the interaction that asked.
      'nonce': modal.nonce.isEmpty ? _nextNonce() : modal.nonce,
      'data': {
        'custom_id': modal.customId,
        'components': [
          for (final field in modal.fields)
            {
              'type': 1,
              'components': [
                {
                  'type': 4,
                  'custom_id': field.customId,
                  'value': values[field.customId] ?? '',
                },
              ],
            },
        ],
      },
    });
  }

  /// Folds a gateway dispatch in, publishing any modal it opens.
  ModalDefinition? accept(String eventName, Map<String, Object?> data) {
    if (eventName != 'INTERACTION_MODAL_CREATE') return null;
    final modal = DiscordMessageComponentMapper.readModal(data);
    if (modal == null) return null;
    if (!_modals.isClosed) _modals.add(modal);
    return modal;
  }

  Future<void> close() async {
    if (!_modals.isClosed) await _modals.close();
  }

  String _requireSession() {
    final sessionId = _sessionId();
    if (sessionId == null || sessionId.isEmpty) {
      throw StateError('The gateway session is not established');
    }
    return sessionId;
  }

  String _nextNonce() =>
      _nonce?.call() ??
      '${DateTime.now().microsecondsSinceEpoch}${_sequence++}';
}
