import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/expression_favorites_controller.dart';

import '../../domain/chat_models.dart';
import '../../theme/flucord_theme.dart';
import 'remote_identity_image.dart';

part 'emoji_picker_data.dart';
part 'emoji_picker_chrome.dart';

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
    this.favorites,
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

  /// The starred expressions, when the transport holds any.
  final ExpressionFavoritesController? favorites;

  @override
  State<EmojiPickerButton> createState() => _EmojiPickerButtonState();
}

class _EmojiPickerButtonState extends State<EmojiPickerButton> {
  final MenuController _menuController = MenuController();

  @override
  Widget build(BuildContext context) => MenuAnchor(
    controller: _menuController,
    onOpen: () {
      widget.onMenuStateChanged?.call(true);
      // Read on opening: the blob costs a request, and a composer whose
      // picker is never opened should not spend one.
      unawaited(widget.favorites?.load());
    },
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
        favorites: widget.favorites,
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
    this.favorites,
    super.key,
  });

  final String spaceName;
  final List<GuildEmoji> customEmojis;
  final ValueChanged<String> onSelected;
  final EmojiPickerPurpose purpose;
  final ExpressionFavoritesController? favorites;

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

  /// The starred emoji, in the order the account starred them.
  ///
  /// An entry naming an emoji this session cannot see — a custom one from a
  /// server the account has since left — is skipped rather than drawn as a
  /// gap: the blob outlives membership, and Discord's own client filters the
  /// same way instead of rewriting the list.
  List<_EmojiChoice> get _favoriteChoices {
    final held = widget.favorites?.favorites.emojis ?? const <String>[];
    if (held.isEmpty) return const [];
    final byKey = {
      for (final emoji in _unicodeEmojis) emoji.name: _EmojiChoice.unicode(emoji),
      for (final emoji in widget.customEmojis)
        if (emoji.available) emoji.id: _EmojiChoice.custom(emoji),
    };
    return [
      for (final key in held)
        if (byKey[key] case final _EmojiChoice choice) choice,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final unicode = _unicodeChoices;
    final custom = _customChoices;
    // Only on the idle picker: a search asks about names, and putting the
    // starred ones above the match would hide it.
    final favorites = _query.isEmpty ? _favoriteChoices : const <_EmojiChoice>[];
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
                      if (favorites.isNotEmpty) ...[
                        const _SectionLabel(label: 'FAVOURITES'),
                        _EmojiGrid(
                          choices: favorites,
                          favorites: widget.favorites,
                          onSelected: _select,
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (unicode.isNotEmpty) ...[
                        _SectionLabel(
                          label: _query.isEmpty ? 'FREQUENT' : 'UNICODE',
                        ),
                        _EmojiGrid(
                          choices: unicode,
                          favorites: widget.favorites,
                          onSelected: _select,
                        ),
                      ],
                      if (custom.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _SectionLabel(label: widget.spaceName.toUpperCase()),
                        _EmojiGrid(
                          choices: custom,
                          favorites: widget.favorites,
                          onSelected: _select,
                        ),
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

class _EmojiGrid extends StatelessWidget {
  const _EmojiGrid({
    required this.choices,
    required this.favorites,
    required this.onSelected,
  });

  final List<_EmojiChoice> choices;
  final ExpressionFavoritesController? favorites;
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
      final store = favorites;
      final starred = store?.isFavoriteEmoji(choice.favoriteKey) ?? false;
      // Starring is the second gesture rather than a control drawn on the
      // tile: these are 27 pixels across, and a star pinned to one would sit
      // on top of the emoji it is meant to describe.
      final star = store == null
          ? null
          : () => unawaited(store.toggleEmoji(choice.favoriteKey));
      return Semantics(
        label: starred ? '${choice.semanticLabel}, favourite' : choice.semanticLabel,
        button: true,
        onTap: () => onSelected(choice),
        onLongPress: star,
        excludeSemantics: true,
        child: Tooltip(
          message: store == null
              ? choice.tooltip
              : '${choice.tooltip}\nRight-click to '
                    '${starred ? 'unfavourite' : 'favourite'}',
          child: InkWell(
            key: ValueKey('emoji-choice-${choice.key}'),
            borderRadius: BorderRadius.circular(4),
            onTap: () => onSelected(choice),
            onSecondaryTap: star,
            onLongPress: star,
            child: Stack(
              children: [
                Center(child: _EmojiGlyph(choice: choice)),
                if (starred)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Icon(
                      Icons.star,
                      key: ValueKey('emoji-starred-${choice.key}'),
                      size: 9,
                      color: Colors.amber,
                    ),
                  ),
              ],
            ),
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
    required this.favoriteKey,
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
    // Discord stores a unicode emoji by name and a custom one by id, so this
    // is what goes in the blob — not the surrogates, which its own other
    // sessions would fail to look up.
    favoriteKey: emoji.name,
    messageToken: emoji.glyph,
    reactionKey: emoji.glyph,
    tooltip: ':${emoji.name}:',
    semanticLabel: '${emoji.name} emoji',
    fallback: emoji.glyph,
    unicodeGlyph: emoji.glyph,
  );

  factory _EmojiChoice.custom(GuildEmoji emoji) => _EmojiChoice(
    key: 'custom-${emoji.id}',
    favoriteKey: emoji.id,
    messageToken: emoji.messageSyntax,
    reactionKey: emoji.reactionKey,
    tooltip: ':${emoji.name}:',
    semanticLabel: '${emoji.name} guild emoji',
    fallback: emoji.name.substring(0, 1).toUpperCase(),
    imageUrl: emoji.imageUrl,
  );

  final String key;

  /// How the favourites blob names this emoji.
  final String favoriteKey;
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
