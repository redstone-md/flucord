import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';
import '../../theme/flucord_theme.dart';
import 'remote_identity_image.dart';

part 'emoji_picker_data.dart';

enum EmojiPickerPurpose { message, reaction }

class EmojiPickerButton extends StatefulWidget {
  const EmojiPickerButton({
    required this.spaceName,
    required this.customEmojis,
    required this.onSelected,
    this.purpose = EmojiPickerPurpose.message,
    this.dimension = 48,
    this.iconSize = 19,
    this.buttonKey,
    this.onMenuStateChanged,
    super.key,
  });

  final String spaceName;
  final List<GuildEmoji> customEmojis;
  final ValueChanged<String> onSelected;
  final EmojiPickerPurpose purpose;
  final double dimension;
  final double iconSize;
  final Key? buttonKey;
  final ValueChanged<bool>? onMenuStateChanged;

  @override
  State<EmojiPickerButton> createState() => _EmojiPickerButtonState();
}

class _EmojiPickerButtonState extends State<EmojiPickerButton> {
  final MenuController _menuController = MenuController();

  @override
  Widget build(BuildContext context) => MenuAnchor(
    controller: _menuController,
    onOpen: () => widget.onMenuStateChanged?.call(true),
    onClose: () => widget.onMenuStateChanged?.call(false),
    style: MenuStyle(
      padding: const WidgetStatePropertyAll(EdgeInsets.zero),
      backgroundColor: WidgetStatePropertyAll(context.surfaces.surface),
      elevation: const WidgetStatePropertyAll(14),
      shadowColor: WidgetStatePropertyAll(Colors.black.withValues(alpha: 0.42)),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: context.surfaces.border),
        ),
      ),
    ),
    menuChildren: [
      EmojiPickerPanel(
        spaceName: widget.spaceName,
        customEmojis: widget.customEmojis,
        purpose: widget.purpose,
        onSelected: (value) {
          widget.onSelected(value);
          _menuController.close();
        },
      ),
    ],
    builder: (context, controller, _) => IconButton(
      key: widget.buttonKey ?? const ValueKey('open-emoji-picker'),
      onPressed: controller.isOpen ? controller.close : controller.open,
      constraints: BoxConstraints.tightFor(
        width: widget.dimension,
        height: widget.dimension,
      ),
      padding: EdgeInsets.zero,
      tooltip: controller.isOpen
          ? widget.purpose.closeTooltip
          : widget.purpose.openTooltip,
      icon: Icon(
        widget.purpose == EmojiPickerPurpose.reaction
            ? Icons.add_reaction_outlined
            : controller.isOpen
            ? Icons.emoji_emotions
            : Icons.emoji_emotions_outlined,
        size: widget.iconSize,
        color: controller.isOpen ? FlucordColors.brand : null,
      ),
    ),
  );
}

class EmojiPickerPanel extends StatefulWidget {
  const EmojiPickerPanel({
    required this.spaceName,
    required this.customEmojis,
    required this.onSelected,
    this.purpose = EmojiPickerPurpose.message,
    super.key,
  });

  final String spaceName;
  final List<GuildEmoji> customEmojis;
  final ValueChanged<String> onSelected;
  final EmojiPickerPurpose purpose;

  @override
  State<EmojiPickerPanel> createState() => _EmojiPickerPanelState();
}

class _EmojiPickerPanelState extends State<EmojiPickerPanel> {
  String _query = '';

  List<_EmojiChoice> get _unicodeChoices => _unicodeEmojis
      .where((emoji) => emoji.matches(_query))
      .map(_EmojiChoice.unicode)
      .toList(growable: false);

  List<_EmojiChoice> get _customChoices => widget.customEmojis
      .where(
        (emoji) =>
            emoji.available &&
            (_query.isEmpty ||
                emoji.name.toLowerCase().replaceAll('_', ' ').contains(_query)),
      )
      .map(_EmojiChoice.custom)
      .toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final unicode = _unicodeChoices;
    final custom = _customChoices;
    return SizedBox(
      key: const ValueKey('emoji-picker'),
      width: 360,
      height: 420,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PickerHeader(
            title: widget.purpose.panelTitle,
            spaceName: widget.spaceName,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              key: const ValueKey('emoji-search'),
              autofocus: true,
              onChanged: (value) =>
                  setState(() => _query = value.trim().toLowerCase()),
              style: const TextStyle(fontSize: 12),
              decoration: const InputDecoration(
                hintText: 'Find emoji',
                prefixIcon: Icon(Icons.search, size: 16),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 9),
              ),
            ),
          ),
          Divider(height: 1, color: context.surfaces.border),
          Expanded(
            child: unicode.isEmpty && custom.isEmpty
                ? const _EmojiEmptyState()
                : ListView(
                    primary: false,
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
                    children: [
                      if (unicode.isNotEmpty) ...[
                        _SectionLabel(
                          label: _query.isEmpty ? 'FREQUENT' : 'UNICODE',
                        ),
                        _EmojiGrid(choices: unicode, onSelected: _select),
                      ],
                      if (custom.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _SectionLabel(label: widget.spaceName.toUpperCase()),
                        _EmojiGrid(choices: custom, onSelected: _select),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  void _select(_EmojiChoice choice) =>
      widget.onSelected(choice.valueFor(widget.purpose));
}

class _PickerHeader extends StatelessWidget {
  const _PickerHeader({required this.title, required this.spaceName});

  final String title;
  final String spaceName;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 48,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              spaceName,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: context.surfaces.muted, fontSize: 10),
            ),
          ),
        ],
      ),
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: context.surfaces.muted,
        fontSize: 9,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _EmojiGrid extends StatelessWidget {
  const _EmojiGrid({required this.choices, required this.onSelected});

  final List<_EmojiChoice> choices;
  final ValueChanged<_EmojiChoice> onSelected;

  @override
  Widget build(BuildContext context) => GridView.builder(
    primary: false,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 8,
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
    ),
    itemCount: choices.length,
    itemBuilder: (context, index) {
      final choice = choices[index];
      return Semantics(
        label: choice.semanticLabel,
        button: true,
        onTap: () => onSelected(choice),
        excludeSemantics: true,
        child: Tooltip(
          message: choice.tooltip,
          child: InkWell(
            key: ValueKey('emoji-choice-${choice.key}'),
            borderRadius: BorderRadius.circular(4),
            onTap: () => onSelected(choice),
            child: Center(child: _EmojiGlyph(choice: choice)),
          ),
        ),
      );
    },
  );
}

class _EmojiGlyph extends StatelessWidget {
  const _EmojiGlyph({required this.choice});

  final _EmojiChoice choice;

  @override
  Widget build(BuildContext context) {
    if (choice.unicodeGlyph case final String glyph) {
      return Text(glyph, style: const TextStyle(fontSize: 22));
    }
    return SizedBox.square(
      dimension: 27,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: RemoteIdentityImage(
          url: choice.imageUrl,
          fallback: ColoredBox(
            color: context.surfaces.inset,
            child: Center(
              child: Text(
                choice.fallback,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmojiEmptyState extends StatelessWidget {
  const _EmojiEmptyState();

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.search_off, size: 26, color: context.surfaces.muted),
        const SizedBox(height: 8),
        const Text('No emoji found', style: TextStyle(fontSize: 12)),
      ],
    ),
  );
}

final class _EmojiChoice {
  const _EmojiChoice({
    required this.key,
    required this.messageToken,
    required this.reactionKey,
    required this.tooltip,
    required this.semanticLabel,
    required this.fallback,
    this.unicodeGlyph,
    this.imageUrl,
  });

  factory _EmojiChoice.unicode(_UnicodeEmoji emoji) => _EmojiChoice(
    key: 'unicode-${emoji.name}',
    messageToken: emoji.glyph,
    reactionKey: emoji.glyph,
    tooltip: ':${emoji.name}:',
    semanticLabel: '${emoji.name} emoji',
    fallback: emoji.glyph,
    unicodeGlyph: emoji.glyph,
  );

  factory _EmojiChoice.custom(GuildEmoji emoji) => _EmojiChoice(
    key: 'custom-${emoji.id}',
    messageToken: emoji.messageSyntax,
    reactionKey: emoji.reactionKey,
    tooltip: ':${emoji.name}:',
    semanticLabel: '${emoji.name} guild emoji',
    fallback: emoji.name.substring(0, 1).toUpperCase(),
    imageUrl: emoji.imageUrl,
  );

  final String key;
  final String messageToken;
  final String reactionKey;
  final String tooltip;
  final String semanticLabel;
  final String fallback;
  final String? unicodeGlyph;
  final String? imageUrl;

  String valueFor(EmojiPickerPurpose purpose) => switch (purpose) {
    EmojiPickerPurpose.message => messageToken,
    EmojiPickerPurpose.reaction => reactionKey,
  };
}

extension on EmojiPickerPurpose {
  String get panelTitle => switch (this) {
    EmojiPickerPurpose.message => 'Emoji',
    EmojiPickerPurpose.reaction => 'Add reaction',
  };

  String get openTooltip => switch (this) {
    EmojiPickerPurpose.message => 'Choose emoji',
    EmojiPickerPurpose.reaction => 'Add reaction',
  };

  String get closeTooltip => switch (this) {
    EmojiPickerPurpose.message => 'Close emoji picker',
    EmojiPickerPurpose.reaction => 'Close reaction picker',
  };
}
