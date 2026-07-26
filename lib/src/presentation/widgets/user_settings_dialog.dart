import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/user_settings_controller.dart';
import '../../domain/user_settings.dart';
import '../../domain/user_settings_repository.dart';
import '../../theme/flucord_theme.dart';
import 'user_settings_account_sections.dart';
import 'user_settings_sections.dart';

/// The left-hand categories, in the order Discord lists the comparable ones.
enum UserSettingsCategory {
  appearance('Appearance', Icons.palette_outlined),
  chat('Chat', Icons.chat_bubble_outline),
  notifications('Notifications', Icons.notifications_none),
  privacy('Privacy', Icons.shield_outlined),
  language('Language', Icons.translate),
  status('Status', Icons.mood_outlined);

  const UserSettingsCategory(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Discord's user settings screen, for the settings Flucord can speak for.
class UserSettingsDialog extends StatefulWidget {
  const UserSettingsDialog({required this.controller, super.key});

  /// Below this width the category rail becomes a scrolling strip so the pane
  /// keeps its full width for the controls.
  static const railBreakpoint = 720.0;

  final UserSettingsController controller;

  static Future<void> show(
    BuildContext context, {
    required UserSettingsController controller,
  }) => showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.58),
    builder: (_) => UserSettingsDialog(controller: controller),
  );

  @override
  State<UserSettingsDialog> createState() => _UserSettingsDialogState();
}

class _UserSettingsDialogState extends State<UserSettingsDialog> {
  UserSettingsCategory _category = UserSettingsCategory.appearance;

  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.load());
  }

  @override
  Widget build(BuildContext context) => Dialog(
    key: const ValueKey('user-settings-dialog'),
    insetPadding: const EdgeInsets.all(24),
    backgroundColor: context.surfaces.canvas,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 940, maxHeight: 720),
      child: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) => LayoutBuilder(
          builder: (context, constraints) {
            final wide =
                constraints.maxWidth >= UserSettingsDialog.railBreakpoint;
            final navigation = _Navigation(
              selected: _category,
              horizontal: !wide,
              onSelected: (category) => setState(() => _category = category),
            );
            final body = _Body(
              controller: widget.controller,
              category: _category,
            );
            return wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: 232, child: navigation),
                      VerticalDivider(width: 1, color: context.surfaces.border),
                      Expanded(child: body),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      navigation,
                      Divider(height: 1, color: context.surfaces.border),
                      Expanded(child: body),
                    ],
                  );
          },
        ),
      ),
    ),
  );
}

class _Navigation extends StatelessWidget {
  const _Navigation({
    required this.selected,
    required this.horizontal,
    required this.onSelected,
  });

  final UserSettingsCategory selected;
  final bool horizontal;
  final ValueChanged<UserSettingsCategory> onSelected;

  @override
  Widget build(BuildContext context) {
    final tiles = [
      for (final category in UserSettingsCategory.values)
        _NavigationTile(
          category: category,
          selected: category == selected,
          compact: horizontal,
          onPressed: () => onSelected(category),
        ),
    ];
    if (!horizontal) {
      return ColoredBox(
        color: context.surfaces.surface,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Text(
                'User settings',
                style: TextStyle(
                  color: context.surfaces.muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            ...tiles,
          ],
        ),
      );
    }
    return ColoredBox(
      color: context.surfaces.surface,
      child: SizedBox(
        height: 52,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          children: [
            for (final tile in tiles)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: tile,
              ),
          ],
        ),
      ),
    );
  }
}

class _NavigationTile extends StatelessWidget {
  const _NavigationTile({
    required this.category,
    required this.selected,
    required this.compact,
    required this.onPressed,
  });

  final UserSettingsCategory category;
  final bool selected;
  final bool compact;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final foreground = selected
        ? Theme.of(context).colorScheme.onSurface
        : context.surfaces.muted;
    final label = Text(
      category.label,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: foreground,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 0 : 1),
      child: Material(
        color: selected ? context.surfaces.raised : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          key: ValueKey('settings-nav-${category.name}'),
          borderRadius: BorderRadius.circular(4),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(category.icon, size: 15, color: foreground),
                const SizedBox(width: 8),
                // The horizontal strip hands its children unbounded width, so
                // only the rail's column can hand the label a flex factor.
                if (compact) label else Flexible(child: label),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.controller, required this.category});

  final UserSettingsController controller;
  final UserSettingsCategory category;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
        child: Row(
          children: [
            Expanded(
              child: Text(
                category.label,
                style: TextStyle(
                  color: context.surfaces.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              key: const ValueKey('user-settings-close'),
              tooltip: 'Close',
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.close, size: 18),
            ),
          ],
        ),
      ),
      if (controller.writeError != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
          child: Text(
            key: const ValueKey('user-settings-write-error'),
            'Discord did not accept the last change.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontSize: 11,
            ),
          ),
        ),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: _content(context),
        ),
      ),
    ],
  );

  Widget _content(BuildContext context) {
    if (!controller.isAvailable) {
      return _Notice(
        key: const ValueKey('user-settings-unavailable'),
        icon: Icons.cloud_off_outlined,
        message:
            'Connect a Discord account to read and change its settings. '
            'The demo and bot transports have no account behind them.',
      );
    }
    final settings = controller.settings;
    if (settings == null) {
      if (controller.isLoading) {
        return const Center(
          key: ValueKey('user-settings-loading'),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      }
      return Column(
        key: const ValueKey('user-settings-error'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Notice(
            icon: Icons.error_outline,
            message: 'Discord did not return your settings.',
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => unawaited(controller.load()),
            child: const Text('Try again'),
          ),
        ],
      );
    }
    return _section(settings);
  }

  Widget _section(UserSettings settings) => switch (category) {
    UserSettingsCategory.appearance => AppearanceSettingsSection(
      settings: settings,
      onEdit: _edit,
    ),
    UserSettingsCategory.chat => ChatSettingsSection(
      settings: settings,
      onEdit: _edit,
    ),
    UserSettingsCategory.notifications => NotificationSettingsSection(
      settings: settings,
      onEdit: _edit,
    ),
    UserSettingsCategory.privacy => PrivacySettingsSection(
      settings: settings,
      onEdit: _edit,
    ),
    UserSettingsCategory.language => LanguageSettingsSection(
      settings: settings,
    ),
    UserSettingsCategory.status => StatusSettingsSection(
      settings: settings,
      onEdit: _edit,
    ),
  };

  void _edit(UserSettingsPatch patch) => unawaited(controller.apply(patch));
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.message, super.key});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 18, color: context.surfaces.muted),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          message,
          style: TextStyle(color: context.surfaces.muted, fontSize: 12),
        ),
      ),
    ],
  );
}
