import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/theme_controller.dart';
import '../../domain/flucord_palette.dart';
import '../../theme/flucord_theme.dart';

/// Choosing a theme, and being told where to put one.
class ThemeSection extends StatefulWidget {
  const ThemeSection({required this.controller, super.key});

  final ThemeController controller;

  @override
  State<ThemeSection> createState() => _ThemeSectionState();
}

class _ThemeSectionState extends State<ThemeSection> {
  String? _folder;

  @override
  void initState() {
    super.initState();
    unawaited(_readFolder());
  }

  Future<void> _readFolder() async {
    final path = await widget.controller.themeFolderPath();
    if (mounted) setState(() => _folder = path);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      return Column(
        key: const ValueKey('theme-section'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Themes', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            // Said plainly, because a theme written for BetterDiscord will
            // look partly applied otherwise and read as a bug.
            'Drop a theme into the folder below. Flucord themes are JSON; a '
            'BetterDiscord .theme.css works too, but only its colours are '
            'read — the rest of it describes a web page Flucord does not have.',
            style: TextStyle(fontSize: 12, color: context.surfaces.muted),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  _folder ?? 'Reading…',
                  key: const ValueKey('theme-folder'),
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 11,
                    color: context.surfaces.muted,
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('theme-copy-folder'),
                tooltip: 'Copy the folder path',
                onPressed: _folder == null
                    ? null
                    : () => unawaited(
                        Clipboard.setData(ClipboardData(text: _folder!)),
                      ),
                icon: const Icon(Icons.copy, size: 16),
              ),
              IconButton(
                key: const ValueKey('theme-refresh'),
                tooltip: 'Look for new themes',
                onPressed: () => unawaited(controller.refresh()),
                icon: const Icon(Icons.refresh, size: 18),
              ),
            ],
          ),
          const Divider(height: 20),
          _ThemeTile(
            tileKey: const ValueKey('theme-builtin'),
            name: 'Flucord',
            subtitle: 'The built-in theme, following your light or dark '
                'setting.',
            palette: FlucordPalette.dark,
            selected: controller.selected == null,
            onSelected: () => unawaited(controller.select(null)),
          ),
          for (final theme in controller.themes)
            _ThemeTile(
              tileKey: ValueKey('theme-${theme.id}'),
              name: theme.name,
              subtitle: [
                if (theme.author.isNotEmpty) 'by ${theme.author}',
                if (theme.version.isNotEmpty) theme.version,
                if (theme.source == ThemeSource.betterDiscord)
                  'BetterDiscord — colours only',
              ].join(' · '),
              palette: theme.palette,
              selected: controller.selected?.id == theme.id,
              onSelected: () => unawaited(controller.select(theme.id)),
            ),
          if (controller.isLoaded && controller.themes.isEmpty)
            Padding(
              key: const ValueKey('theme-none-installed'),
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'No themes installed yet.',
                style: TextStyle(fontSize: 12, color: context.surfaces.muted),
              ),
            ),
        ],
      );
    },
  );
}

class _ThemeTile extends StatelessWidget {
  const _ThemeTile({
    required this.tileKey,
    required this.name,
    required this.subtitle,
    required this.palette,
    required this.selected,
    required this.onSelected,
  });

  final Key tileKey;
  final String name;
  final String subtitle;
  final FlucordPalette palette;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: InkWell(
      key: tileKey,
      onTap: onSelected,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : context.surfaces.border,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            // The colours themselves rather than a name: a theme is picked by
            // how it looks, and every list of names looks the same.
            _Swatch(palette: palette),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(name, style: const TextStyle(fontSize: 13)),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: context.surfaces.muted,
                      ),
                    ),
                ],
              ),
            ),
            if (selected)
              Icon(
                Icons.check_circle,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
          ],
        ),
      ),
    ),
  );
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.palette});

  final FlucordPalette palette;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 52,
    height: 34,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Row(
        children: [
          Expanded(child: ColoredBox(color: Color(palette.rail))),
          Expanded(child: ColoredBox(color: Color(palette.surface))),
          Expanded(
            flex: 2,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: Color(palette.canvas)),
                Align(
                  alignment: Alignment.bottomRight,
                  child: Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: Color(palette.brand),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
