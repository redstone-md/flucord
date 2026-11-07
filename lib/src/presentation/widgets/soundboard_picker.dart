import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/expression_favorites_controller.dart';
import '../../application/soundboard_controller.dart';
import '../../domain/soundboard.dart';
import '../../theme/flucord_icons.dart';
import '../../theme/flucord_radius.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';
import 'expression_favorite_star.dart';

/// Names a server for a section heading.
typedef SoundboardGuildName = String Function(String guildId);

/// The soundboard button a voice room or a call carries, and the sheet
/// behind it.
class SoundboardButton extends StatelessWidget {
  const SoundboardButton({
    required this.controller,
    required this.channelId,
    required this.guildName,
    this.favorites,
    super.key,
  });

  final SoundboardController controller;

  /// The voice channel or call a sound would play into.
  final String channelId;
  final SoundboardGuildName guildName;

  /// Where stars are kept, or null on a transport that holds none.
  final ExpressionFavoritesController? favorites;

  @override
  Widget build(BuildContext context) {
    if (!controller.isOffered) return const SizedBox.shrink();
    return IconButton(
      key: const ValueKey('soundboard-open'),
      tooltip: 'Soundboard',
      onPressed: () => unawaited(
        SoundboardSheet.show(
          context,
          controller: controller,
          channelId: channelId,
          guildName: guildName,
          favorites: favorites,
        ),
      ),
      icon: const FlucordIcon(FlucordIcons.music),
    );
  }
}

/// Every sound the session holds, grouped by server, with search and
/// favourites. Sounds this account may not play here are shown locked.
class SoundboardSheet extends StatefulWidget {
  const SoundboardSheet({
    required this.controller,
    required this.channelId,
    required this.guildName,
    this.favorites,
    super.key,
  });

  final SoundboardController controller;
  final String channelId;
  final SoundboardGuildName guildName;
  final ExpressionFavoritesController? favorites;

  static Future<void> show(
    BuildContext context, {
    required SoundboardController controller,
    required String channelId,
    required SoundboardGuildName guildName,
    ExpressionFavoritesController? favorites,
  }) {
    // Stars live in a blob that is not part of READY.
    if (favorites != null) unawaited(favorites.load());
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.surfaces.canvas,
      builder: (_) => SoundboardSheet(
        controller: controller,
        channelId: channelId,
        guildName: guildName,
        favorites: favorites,
      ),
    );
  }

  @override
  State<SoundboardSheet> createState() => _SoundboardSheetState();
}

class _SoundboardSheetState extends State<SoundboardSheet> {
  final TextEditingController _query = TextEditingController();

  SoundboardController get _controller => widget.controller;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_controller, ?widget.favorites, _query]),
    builder: (context, _) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Soundboard',
                    style: FlucordTextRole.heading.style,
                  ),
                ),
                if (_controller.isSending)
                  const SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            _body(context),
          ],
        ),
      ),
    ),
  );

  Widget _body(BuildContext context) {
    final favoriteIds = widget.favorites?.favorites.soundIds ?? const [];
    final everything = _controller.sections(favoriteIds: favoriteIds);
    if (_controller.isLoading && everything.isEmpty) {
      return const Padding(
        key: ValueKey('soundboard-loading'),
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (everything.isEmpty) return _empty(context);
    final sections = _query.text.trim().isEmpty
        ? everything
        : _controller.sections(favoriteIds: favoriteIds, query: _query.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const ValueKey('soundboard-search'),
          controller: _query,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search sounds',
            prefixIcon: FlucordIcon(FlucordIcons.search, size: 18),
          ),
        ),
        const SizedBox(height: 8),
        if (_controller.loadFailed)
          Row(
            children: [
              Expanded(
                child: Text(
                  'Discord did not return every sound.',
                  key: const ValueKey('soundboard-error'),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: FlucordType.caption,
                  ),
                ),
              ),
              TextButton(
                key: const ValueKey('soundboard-retry'),
                onPressed: () => unawaited(_controller.load()),
                child: const Text('Try again'),
              ),
            ],
          )
        else if (_controller.error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'That sound could not be played.',
              key: const ValueKey('soundboard-error'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: FlucordType.caption,
              ),
            ),
          ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 360),
          child: sections.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    'No sounds match.',
                    style: TextStyle(
                      color: context.surfaces.muted,
                      fontSize: FlucordType.caption,
                    ),
                  ),
                )
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _sections(context, sections),
                  ),
                ),
        ),
      ],
    );
  }

  /// One heading and a wrap of tiles per section. The Nitro hint goes once,
  /// under the first heading whose sounds are locked.
  List<Widget> _sections(
    BuildContext context,
    List<SoundboardSection> sections,
  ) {
    final hintAt = sections.indexWhere(
      (section) =>
          section is GuildSoundsSection &&
          section.sounds.any(_controller.isLocked),
    );
    return [
      for (final (index, section) in sections.indexed) ...[
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 6),
          child: Text(
            _title(section).toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: FlucordTextRole.caption.strong.copyWith(
              color: context.surfaces.muted,
            ),
          ),
        ),
        if (index == hintAt)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              'Sounds from other servers need Nitro.',
              key: const ValueKey('soundboard-nitro-hint'),
              style: TextStyle(
                color: context.surfaces.muted,
                fontSize: FlucordType.caption,
              ),
            ),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final sound in section.sounds)
              _SoundTile(
                sound: sound,
                inFavorites: section is FavoriteSoundsSection,
                isLocked: _controller.isLocked(sound),
                favorites: widget.favorites,
                onPressed: () =>
                    unawaited(_controller.play(widget.channelId, sound)),
              ),
          ],
        ),
      ],
    ];
  }

  String _title(SoundboardSection section) => switch (section) {
    FavoriteSoundsSection() => 'Favourites',
    GuildSoundsSection(:final guildId) => widget.guildName(guildId),
    DefaultSoundsSection() => 'Default sounds',
  };

  Widget _empty(BuildContext context) => Column(
    key: const ValueKey('soundboard-empty'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        _controller.error == null
            ? 'This server has no sounds yet.'
            : 'Discord did not return the soundboard.',
        style: TextStyle(
          color: context.surfaces.muted,
          fontSize: FlucordType.caption,
        ),
      ),
      const SizedBox(height: 10),
      FilledButton(
        key: const ValueKey('soundboard-retry'),
        onPressed: () => unawaited(_controller.load()),
        child: const Text('Try again'),
      ),
    ],
  );
}

class _SoundTile extends StatelessWidget {
  const _SoundTile({
    required this.sound,
    required this.inFavorites,
    required this.isLocked,
    required this.favorites,
    required this.onPressed,
  });

  final SoundboardSound sound;

  /// The copy in the favourites section, which also sits under its server.
  final bool inFavorites;

  /// Out of reach until the account has Nitro.
  final bool isLocked;
  final ExpressionFavoritesController? favorites;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label = sound.name.isEmpty ? 'Sound' : sound.name;
    final playable = sound.isAvailable && !isLocked;
    final star = favorites;
    final place = inFavorites ? 'favourite' : 'sound';
    return Tooltip(
      message: switch ((sound.isAvailable, isLocked)) {
        (false, _) =>
          '$label is unavailable while the server is below the boost level '
              'that unlocked it.',
        (_, true) => '$label is from another server. Using it needs Nitro.',
        _ => label,
      },
      child: Stack(
        children: [
          Material(
            color: context.surfaces.raised,
            borderRadius: FlucordRadius.medium,
            child: InkWell(
              key: ValueKey('soundboard-$place-${sound.id}'),
              borderRadius: FlucordRadius.medium,
              onTap: playable ? onPressed : null,
              child: Opacity(
                opacity: playable ? 1 : 0.45,
                child: Container(
                  width: 92,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 10,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isLocked)
                        const FlucordIcon(FlucordIcons.lock, size: 22)
                      else
                        Text(
                          sound.emojiName ?? '🔊',
                          style: const TextStyle(fontSize: FlucordType.title),
                        ),
                      const SizedBox(height: 4),
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: FlucordType.caption),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (star != null)
            Positioned(
              top: 2,
              right: 2,
              child: ExpressionFavoriteStar(
                key: ValueKey('soundboard-$place-star-${sound.id}'),
                controller: star,
                isFavorite: star.isFavoriteSound(sound.id),
                onPressed: () => star.toggleSound(sound.id),
              ),
            ),
        ],
      ),
    );
  }
}
