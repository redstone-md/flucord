import 'package:flutter/material.dart';

import '../../theme/flucord_icons.dart';
import '../../theme/flucord_radius.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';
import 'flucord_button.dart';
import 'flucord_controls.dart';
import 'user_settings_controls.dart';

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
    padding: const EdgeInsets.fromLTRB(40, 8, 40, 24),
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SettingsSectionHeader(title: title, subtitle: subtitle),
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
        FlucordFieldLabel(label),
        child,
        if (hint case final hint?) ...[
          const SizedBox(height: 4),
          Text(
            hint,
            style: FlucordTextRole.caption.style.copyWith(
              color: context.surfaces.muted,
            ),
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
        FlucordIcon(
          FlucordIcons.offline,
          size: 28,
          color: context.surfaces.muted,
        ),
        const SizedBox(height: 10),
        Text(
          message,
          textAlign: TextAlign.center,
          style: FlucordTextRole.label.style.copyWith(
            color: context.surfaces.text,
          ),
        ),
        const SizedBox(height: 10),
        FlucordButton(label: 'Retry', onPressed: onRetry),
      ],
    ),
  );
}

/// The inline banner a failed write leaves behind.
class GuildSettingsActionError extends StatelessWidget {
  const GuildSettingsActionError({
    required this.error,
    this.message,
    super.key,
  });

  final Object? error;

  /// The sentence this failure is explained with. The default covers every
  /// section; a surface whose refusals have reasons of their own, like a full
  /// server or an oversized file, passes them here so the person reads why
  /// and not just that.
  final String? message;

  @override
  Widget build(BuildContext context) {
    if (error == null) return const SizedBox.shrink();
    final surfaces = context.surfaces;
    return Container(
      key: const ValueKey('guild-settings-action-error'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: surfaces.inset,
        borderRadius: FlucordRadius.control,
        border: Border.all(color: surfaces.danger),
      ),
      child: Row(
        children: [
          FlucordIcon(FlucordIcons.error, size: 16, color: surfaces.errorText),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message ?? 'That change was not saved.',
              style: FlucordTextRole.caption.style.copyWith(
                color: surfaces.text,
              ),
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
      color: context.surfaces.surface,
      borderRadius: FlucordRadius.medium,
      border: Border.all(color: context.surfaces.border),
    ),
    child: Row(
      children: [
        if (leading case final leading?) ...[
          leading,
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: FlucordTextRole.label.style.copyWith(
                  fontWeight: FontWeight.w500,
                  color: context.surfaces.text,
                ),
              ),
              if (subtitle case final subtitle?)
                Text(
                  subtitle,
                  overflow: TextOverflow.ellipsis,
                  style: FlucordTextRole.caption.style.copyWith(
                    color: context.surfaces.muted,
                  ),
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
        style: FlucordTextRole.label.style.copyWith(
          color: context.surfaces.muted,
        ),
      ),
    ),
  );
}
