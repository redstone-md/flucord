import 'package:flutter/material.dart';

import '../../theme/flucord_theme.dart';

/// A section's scrollable body, with its heading.
///
/// Every section scrolls on its own rather than the dialog scrolling as a
/// whole: the roles list and the audit log are unbounded, and a dialog that
/// grew with them would push its own close button off the screen.
class GuildSettingsPanel extends StatelessWidget {
  const GuildSettingsPanel({
    required this.title,
    required this.children,
    this.subtitle,
    this.trailing,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.surfaces.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
      const SizedBox(height: 16),
      ...children,
    ],
  );
}

/// A labelled form row.
class GuildSettingsField extends StatelessWidget {
  const GuildSettingsField({
    required this.label,
    required this.child,
    this.hint,
    super.key,
  });

  final String label;
  final String? hint;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 0.5,
            fontWeight: FontWeight.w700,
            color: context.surfaces.muted,
          ),
        ),
        const SizedBox(height: 6),
        child,
        if (hint != null) ...[
          const SizedBox(height: 4),
          Text(
            hint!,
            style: TextStyle(fontSize: 11, color: context.surfaces.muted),
          ),
        ],
      ],
    ),
  );
}

/// The "this failed, try again" state a section shows in place of its content.
class GuildSettingsRetry extends StatelessWidget {
  const GuildSettingsRetry({
    required this.message,
    required this.onRetry,
    super.key,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    key: const ValueKey('guild-settings-retry'),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.cloud_off, size: 28, color: context.surfaces.muted),
        const SizedBox(height: 10),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 10),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    ),
  );
}

/// The inline banner a failed write leaves behind.
class GuildSettingsActionError extends StatelessWidget {
  const GuildSettingsActionError({required this.error, super.key});

  final Object? error;

  @override
  Widget build(BuildContext context) {
    if (error == null) return const SizedBox.shrink();
    return Container(
      key: const ValueKey('guild-settings-action-error'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: context.surfaces.inset,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Theme.of(context).colorScheme.error),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            size: 16,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'That change was not saved.',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// A row of the lists these sections are mostly made of.
class GuildSettingsRow extends StatelessWidget {
  const GuildSettingsRow({
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: context.surfaces.raised,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Row(
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: 10)],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: context.surfaces.muted),
                ),
            ],
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// The empty state a list shows when the server returned nothing.
class GuildSettingsEmpty extends StatelessWidget {
  const GuildSettingsEmpty({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 26),
    child: Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(color: context.surfaces.muted),
      ),
    ),
  );
}
