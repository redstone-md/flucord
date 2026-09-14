import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/expression_favorites_controller.dart';
import '../../domain/chat_models.dart';
import '../../domain/unicode_emoji.dart';
import '../../theme/flucord_theme.dart';
import 'remote_identity_image.dart';
import 'user_settings_scope.dart';

part 'emoji_picker_chrome.dart';

enum EmojiPickerPurpose { message, reaction }

/// The emoji of one server, to be listed under the server's own name.
final class EmojiServerSection {
  const EmojiServerSection({required this.spaceName, required this.emoji});

  final String spaceName;
  final List<GuildEmoji> emoji;
}

/// The servers' emoji grouped for the picker, the space the composer sits in
/// first.
///
/// Discord lists every server the account is in, each under its own name, and
/// it is the server that accepts or refuses a pick: the client adds no gate
/// of its own.
List<EmojiServerSection> emojiSectionsFromWorkspace(
  ChatWorkspace workspace,
  String currentSpaceId,
) {
  final sections = <EmojiServerSection>[];
  for (final space in [
    ...workspace.spaces.where((space) => space.id == currentSpaceId),
    ...workspace.spaces.where((space) => space.id != currentSpaceId),
  ]) {
    final emoji = workspace.emojisFor(space.id);
    if (emoji.isNotEmpty) {
      sections.add(EmojiServerSection(spaceName: space.name, emoji: emoji));
    }
  }
  return sections;
}

class EmojiPickerButton extends StatefulWidget {
  const EmojiPickerButton({
    required this.spaceName,
    required this.emojiSections,
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
  final List<EmojiServerSection> emojiSections;
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
        emojiSections: widget.emojiSections,
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
    required this.emojiSections,
    required this.onSelected,
    this.purpose = EmojiPickerPurpose.message,
    this.favorites,
    super.key,
  });

  final String spaceName;
  final List<EmojiServerSection> emojiSections;
  final ValueChanged<String> onSelected;
  final EmojiPickerPurpose purpose;
  final ExpressionFavoritesController? favorites;

  @override
  State<EmojiPickerPanel> createState() => _EmojiPickerPanelState();
}

/// How many the FREQUENT section holds. Discord caps its own recent list;
/// without a cap the section would grow without end as the account uses
/// more of the catalogue.
const int _frequentLimit = 32;

class _EmojiPickerPanelState extends State<EmojiPickerPanel> {
  String _query = '';
  int _tone = 0;

  /// The selected category tab, or -1 for the leading view that gathers
  /// favourites, the frequent set and every server's emoji.
  int _category = -1;

  Map<String, _EmojiChoice> get _choicesByKey => {
    for (final emoji in UnicodeEmojiCatalog.all)
      emoji.name: _EmojiChoice.unicode(emoji, tone: _tone),
    for (final section in widget.emojiSections)
      for (final emoji in section.emoji) emoji.id: _EmojiChoice.custom(emoji),
  };

  /// The starred emoji, in the order the account starred them.
  ///
  /// An entry naming an emoji this session cannot see, a custom one from a
  /// server the account has since left, is skipped rather than drawn as a
  /// gap: the blob outlives membership, and Discord's own client filters the
  /// same way instead of rewriting the list.
  List<_EmojiChoice> get _favoriteChoices {
    final held = widget.favorites?.favorites.emojis ?? const <String>[];
    if (held.isEmpty) return const [];
    final byKey = _choicesByKey;
    return [
      for (final key in held)
        if (byKey[key] case final _EmojiChoice choice) choice,
    ];
  }

  /// What the FREQUENT section shows: the emoji the account actually reaches
  /// for, ranked by the use table over the catalogue and the servers' own
  /// emoji together. The table is keyed the way the favourites are: custom
  /// ones by id, unicode ones by name, so both kinds rank in one list,
  /// which is what Discord's own recent row is made of. A fresh account gets
  /// the catalogue's own order rather than an empty panel.
  List<_EmojiChoice> get _frequentChoices {
    final frecency = widget.favorites?.favorites.emojiFrecency;
    if (frecency == null) {
      return [
        for (final emoji in UnicodeEmojiCatalog.all.take(_frequentLimit))
          _EmojiChoice.unicode(emoji, tone: _tone),
      ];
    }
    final rankable = <String, _EmojiChoice>{
      for (final emoji in UnicodeEmojiCatalog.all)
        emoji.name: _EmojiChoice.unicode(emoji, tone: _tone),
      for (final section in widget.emojiSections)
        for (final emoji in section.emoji) emoji.id: _EmojiChoice.custom(emoji),
    };
    return [
      for (final key in frecency.rank(rankable.keys))
        if (rankable[key] case final _EmojiChoice choice) choice,
    ].take(_frequentLimit).toList(growable: false);
  }

  List<(String, List<_EmojiChoice>)> get _customSections {
    final sections = <(String, List<_EmojiChoice>)>[];
    for (final section in widget.emojiSections) {
      final matches = section.emoji
          .where((emoji) => _query.isEmpty || _customMatches(emoji))
          .map(_EmojiChoice.custom)
          .toList(growable: false);
      if (matches.isNotEmpty) {
        sections.add((section.spaceName, matches));
      }
    }
    return sections;
  }

  bool _customMatches(GuildEmoji emoji) =>
      emoji.name.toLowerCase().replaceAll('_', ' ').contains(_query);

  /// The category tab's own group. Tab 0 is the leading view, so the
  /// catalogue's groups start one tab later.
  UnicodeEmojiGroup get _selectedGroup =>
      UnicodeEmojiGroup.values[_category - 1];

  List<_EmojiChoice> get _unicodeChoices {
    final matches = UnicodeEmojiCatalog.search(_query);
    if (_category >= 1) {
      final group = _selectedGroup;
      return [
        for (final emoji in matches.where((emoji) => emoji.group == group))
          _EmojiChoice.unicode(emoji, tone: _tone),
      ];
    }
    if (_query.isEmpty) return const [];
    return [
      for (final emoji in matches) _EmojiChoice.unicode(emoji, tone: _tone),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final favourites = _query.isEmpty
        ? _favoriteChoices
        : const <_EmojiChoice>[];
    final frequent = _category < 0 && _query.isEmpty
        ? _frequentChoices
        : const <_EmojiChoice>[];
    final customSections = _customSections;
    final unicode = _unicodeChoices;
    final nothing =
        favourites.isEmpty &&
        frequent.isEmpty &&
        customSections.isEmpty &&
        unicode.isEmpty;
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
          _CategoryBar(
            categories: const [
              (Icons.history, 'Frequently used'),
              (Icons.emoji_emotions, 'Smileys & Emotion'),
              (Icons.emoji_people, 'People & Body'),
              (Icons.pets, 'Animals & Nature'),
              (Icons.restaurant, 'Food & Drink'),
              (Icons.flight_takeoff, 'Travel & Places'),
              (Icons.celebration, 'Activities'),
              (Icons.emoji_objects, 'Objects'),
              (Icons.favorite, 'Symbols'),
              (Icons.flag, 'Flags'),
            ],
            selected: _category,
            onSelect: (index) => setState(() => _category = index),
          ),
          Expanded(
            child: nothing
                ? const _EmojiEmptyState()
                : CustomScrollView(
                    key: const ValueKey('emoji-grid-scroll'),
                    primary: false,
                    slivers: [
                      if (favourites.isNotEmpty) ...[
                        const _SliverSectionLabel(label: 'FAVOURITES'),
                        _EmojiGridSliver(
                          choices: favourites,
                          favorites: widget.favorites,
                          onSelected: _select,
                        ),
                      ],
                      if (frequent.isNotEmpty) ...[
                        const _SliverSectionLabel(label: 'FREQUENT'),
                        _EmojiGridSliver(
                          choices: frequent,
                          favorites: widget.favorites,
                          onSelected: _select,
                        ),
                      ],
                      for (final (spaceName, choices) in customSections) ...[
                        _SliverSectionLabel(label: spaceName.toUpperCase()),
                        _EmojiGridSliver(
                          choices: choices,
                          favorites: widget.favorites,
                          onSelected: _select,
                        ),
                      ],
                      if (unicode.isNotEmpty) ...[
                        _SliverSectionLabel(
                          label: _category >= 1
                              ? _selectedGroup.label.toUpperCase()
                              : 'UNICODE',
                        ),
                        _EmojiGridSliver(
                          choices: unicode,
                          favorites: widget.favorites,
                          onSelected: _select,
                        ),
                      ],
                    ],
                  ),
          ),
          Divider(height: 1, color: context.surfaces.border),
          _ToneBar(
            tone: _tone,
            onSelect: (tone) => setState(() => _tone = tone),
          ),
        ],
      ),
    );
  }

  void _select(_EmojiChoice choice) =>
      widget.onSelected(choice.valueFor(widget.purpose));
}

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({
    required this.categories,
    required this.selected,
    required this.onSelect,
  });

  final List<(IconData, String)> categories;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('emoji-category-bar'),
      height: 34,
      child: Row(
        children: [
          for (var index = 0; index < categories.length; index++)
            Tooltip(
              message: categories[index].$2,
              child: InkWell(
                key: ValueKey('emoji-category-$index'),
                onTap: () => onSelect(index == selected ? -1 : index),
                child: SizedBox.square(
                  dimension: 34,
                  child: Icon(
                    categories[index].$1,
                    size: 15,
                    color: index == selected
                        ? FlucordColors.brand
                        : context.surfaces.muted,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ToneBar extends StatelessWidget {
  const _ToneBar({required this.tone, required this.onSelect});

  final int tone;
  final ValueChanged<int> onSelect;

  static const _swatches = ['✋', '✋🏻', '✋🏼', '✋🏽', '✋🏾', '✋🏿'];
  static const _names = [
    'Default skin tone',
    'Light skin tone',
    'Medium-light skin tone',
    'Medium skin tone',
    'Medium-dark skin tone',
    'Dark skin tone',
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('emoji-tone-bar'),
      height: 36,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          for (var index = 0; index < _swatches.length; index++)
            IconButton(
              key: ValueKey('emoji-tone-$index'),
              onPressed: () => onSelect(index),
              icon: Text(
                _swatches[index],
                style: TextStyle(
                  fontSize: 16,
                  color: index == tone
                      ? null
                      : context.surfaces.muted.withValues(alpha: 0.6),
                ),
              ),
              tooltip: _names[index],
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
              padding: EdgeInsets.zero,
            ),
        ],
      ),
    );
  }
}

class _SliverSectionLabel extends StatelessWidget {
  const _SliverSectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => SliverPadding(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
    sliver: SliverToBoxAdapter(child: _SectionLabel(label: label)),
  );
}

class _EmojiGridSliver extends StatelessWidget {
  const _EmojiGridSliver({
    required this.choices,
    required this.favorites,
    required this.onSelected,
  });

  final List<_EmojiChoice> choices;
  final ExpressionFavoritesController? favorites;
  final ValueChanged<_EmojiChoice> onSelected;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      sliver: SliverGrid.builder(
        itemCount: choices.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 8,
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
        ),
        itemBuilder: (context, index) => _EmojiTile(
          choice: choices[index],
          favorites: favorites,
          onSelected: onSelected,
        ),
      ),
    );
  }
}

class _EmojiTile extends StatelessWidget {
  const _EmojiTile({
    required this.choice,
    required this.favorites,
    required this.onSelected,
  });

  final _EmojiChoice choice;
  final ExpressionFavoritesController? favorites;
  final ValueChanged<_EmojiChoice> onSelected;

  @override
  Widget build(BuildContext context) {
    final store = favorites;
    final starred = store?.isFavoriteEmoji(choice.favoriteKey) ?? false;
    // Starring is the second gesture rather than a control drawn on the
    // tile: these are 27 pixels across, and a star pinned to one would sit
    // on top of the emoji it is meant to describe.
    final star = store == null
        ? null
        : () => unawaited(store.toggleEmoji(choice.favoriteKey));
    return Semantics(
      label: starred
          ? '${choice.semanticLabel}, favourite'
          : choice.semanticLabel,
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
  }
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
          // The account's animate-emoji answer, read here so the flag from
          // any device redraws the picker.
          playsAnimations: UserSettingsScope.displayOf(
            context,
          ).playsAnimatedEmoji,
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

  factory _EmojiChoice.unicode(UnicodeEmoji emoji, {required int tone}) {
    final name = emoji.nameForTone(tone);
    final glyph = emoji.glyphForTone(tone);
    return _EmojiChoice(
      key: 'unicode-$name',
      // Discord stores a unicode emoji by name and a custom one by id, so this
      // is what goes in the blob, not the surrogates, which its own other
      // sessions would fail to look up.
      favoriteKey: name,
      messageToken: glyph,
      reactionKey: glyph,
      tooltip: ':$name:',
      semanticLabel: '$name emoji',
      fallback: glyph,
      unicodeGlyph: glyph,
    );
  }

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
