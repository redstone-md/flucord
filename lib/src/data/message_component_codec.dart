import 'dart:convert';

import '../domain/message_component.dart';
import 'discord/discord_message_component_service.dart';

/// Stores a message's components in the shape Discord sends them, so the mapper
/// that reads the wire also reads the cache.
abstract final class MessageComponentCodec {
  static String encode(List<MessageActionRow> rows) => jsonEncode([
    for (final row in rows)
      {
        'type': 1,
        'components': [
          for (final component in row.components) _encode(component),
        ],
      },
  ]);

  static List<MessageActionRow> decode(String source) =>
      DiscordMessageComponentMapper.readRows(jsonDecode(source));

  static Map<String, Object?> _encode(MessageComponent component) => {
    'type': component.type,
    'custom_id': component.customId,
    'label': component.label,
    'style': component.style.wireValue,
    'url': ?component.url,
    'disabled': component.isDisabled,
    if (component.emojiName case final name?) 'emoji': {'name': name},
    'placeholder': component.placeholder,
    'options': [
      for (final option in component.options)
        {
          'value': option.value,
          'label': option.label,
          'description': option.description,
          'default': option.isDefault,
        },
    ],
    'min_values': component.minValues,
    'max_values': component.maxValues,
  };
}
