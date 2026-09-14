/// One interactive row under a message.
///
/// Discord nests components: an action row (type 1) holds buttons and selects,
/// and the message holds rows. Only the two kinds that can be acted on are
/// modelled — a text input exists solely inside a modal, and the layout
/// containers of Components V2 carry no interaction of their own.
final class MessageActionRow {
  const MessageActionRow({required this.components});

  final List<MessageComponent> components;

  bool get isEmpty => components.isEmpty;
}

/// A button or a select menu.
final class MessageComponent {
  const MessageComponent({
    required this.type,
    required this.customId,
    this.label = '',
    this.style = MessageButtonStyle.secondary,
    this.url,
    this.isDisabled = false,
    this.emojiName,
    this.placeholder = '',
    this.options = const [],
    this.minValues = 1,
    this.maxValues = 1,
  });

  /// `ComponentType`: 2 is a button, and 3 plus 5–8 are the select menus.
  /// Type 4 sits in the middle of that range and is a text input, which only
  /// ever appears inside a modal.
  final int type;

  /// What identifies the component to the application. Empty on a link
  /// button, which is a hyperlink Discord never hears about.
  final String customId;

  final String label;
  final MessageButtonStyle style;

  /// Set only on a link button.
  final String? url;

  final bool isDisabled;
  final String? emojiName;

  /// Select menus only.
  final String placeholder;
  final List<MessageSelectOption> options;
  final int minValues;
  final int maxValues;

  bool get isButton => type == 2;

  /// Every select flavour: string, user, role, mentionable, channel. Type 4
  /// is deliberately not among them — it is a modal's text input.
  bool get isSelect => type == 3 || (type >= 5 && type <= 8);

  /// A link button opens a browser rather than talking to the application, so
  /// it carries no custom id and produces no interaction.
  bool get isLink => style == MessageButtonStyle.link;

  /// Whether pressing this does anything at all.
  bool get isActionable =>
      !isDisabled && (isLink ? url != null : customId.isNotEmpty);
}

/// `ButtonStyle`, as Discord numbers it.
enum MessageButtonStyle {
  primary(1),
  secondary(2),
  success(3),
  danger(4),
  link(5),
  premium(6);

  const MessageButtonStyle(this.wireValue);

  final int wireValue;

  static MessageButtonStyle fromWire(Object? value) => switch (value) {
    1 => MessageButtonStyle.primary,
    3 => MessageButtonStyle.success,
    4 => MessageButtonStyle.danger,
    5 => MessageButtonStyle.link,
    6 => MessageButtonStyle.premium,
    _ => MessageButtonStyle.secondary,
  };
}

/// One choice in a string select.
final class MessageSelectOption {
  const MessageSelectOption({
    required this.value,
    this.label = '',
    this.description = '',
    this.isDefault = false,
  });

  final String value;
  final String label;
  final String description;
  final bool isDefault;

  String get displayLabel => label.isEmpty ? value : label;
}

/// A modal an application asked this client to show.
final class ModalDefinition {
  const ModalDefinition({
    required this.customId,
    required this.title,
    required this.fields,
    required this.applicationId,
    required this.nonce,
  });

  final String customId;
  final String title;
  final List<ModalField> fields;
  final String applicationId;

  /// The nonce of the interaction that opened it. The submission has to carry
  /// the same one, or Discord cannot tie the two together.
  final String nonce;
}

/// One text input inside a modal.
final class ModalField {
  const ModalField({
    required this.customId,
    this.label = '',
    this.placeholder = '',
    this.value = '',
    this.isRequired = false,
    this.isParagraph = false,
    this.minLength = 0,
    this.maxLength = 0,
  });

  final String customId;
  final String label;
  final String placeholder;

  /// What the application prefilled, if anything.
  final String value;

  final bool isRequired;

  /// `TextInputStyle` 2, which is a multi-line box rather than a single line.
  final bool isParagraph;

  final int minLength;
  final int maxLength;
}

/// Pressing a component and submitting a modal.
abstract interface class MessageComponentRepository {
  /// Modals applications ask this client to open.
  Stream<ModalDefinition> get modals;

  /// Presses [component] on [messageId].
  ///
  /// [values] carries a select's chosen values and is empty for a button.
  Future<void> activate({
    required String channelId,
    required String messageId,
    required String applicationId,
    required MessageComponent component,
    String? guildId,
    int messageFlags = 0,
    List<String> values = const [],
  });

  /// Submits [modal] with the text that was typed into it.
  Future<void> submitModal(
    ModalDefinition modal, {
    required String channelId,
    required Map<String, String> values,
    String? guildId,
  });
}
