import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/guild_settings_controller.dart';
import '../../domain/chat_models.dart';
import '../../domain/guild_management.dart';
import 'guild_settings_controls.dart';

/// The overview page: name, description, the moderation levels, and the two
/// channels a guild routes its own noise through.
///
/// The form builds a *partial* patch — only fields the user actually changed
/// are sent. Discord's route merges what it is given, so a form that posted
/// every field it could read would overwrite settings this client does not even
/// render, with whatever it happened to parse them as.
class GuildSettingsOverviewSection extends StatefulWidget {
  const GuildSettingsOverviewSection({
    required this.controller,
    required this.workspace,
    required this.spaceId,
    super.key,
  });

  final GuildSettingsController controller;
  final ChatWorkspace workspace;
  final String spaceId;

  @override
  State<GuildSettingsOverviewSection> createState() =>
      _GuildSettingsOverviewSectionState();
}

class _GuildSettingsOverviewSectionState
    extends State<GuildSettingsOverviewSection> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  GuildVerificationLevel? _verification;
  GuildExplicitContentFilter? _contentFilter;
  GuildNotificationLevel? _notifications;
  // Null is a real value for these two — "no AFK channel", "no system
  // channel" — so it cannot also mean "the user has not touched this field".
  // Conflating them made an untouched form clear the guild's channels on any
  // unrelated save.
  bool _afkChannelEdited = false;
  String? _afkChannelId;
  int? _afkTimeout;
  bool _systemChannelEdited = false;
  String? _systemChannelId;
  bool? _suppressJoins;
  bool? _boostBar;

  GuildOverviewSettings? get _settings => widget.controller.overview;

  @override
  void initState() {
    super.initState();
    final settings = _settings;
    _name = TextEditingController(text: settings?.name ?? '');
    _description = TextEditingController(text: settings?.description ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    if (settings == null) {
      return const GuildSettingsEmpty(
        message: 'These settings are not available.',
      );
    }
    final channels = widget.workspace
        .channelsFor(widget.spaceId)
        .where((channel) => !channel.isThread)
        .toList(growable: false);
    return GuildSettingsPanel(
      title: 'Overview',
      subtitle: 'Server name, moderation levels and system channels.',
      children: [
        GuildSettingsActionError(error: widget.controller.actionError),
        GuildSettingsField(
          label: 'Server name',
          child: TextField(
            key: const ValueKey('guild-overview-name'),
            controller: _name,
            decoration: const InputDecoration(isDense: true),
          ),
        ),
        GuildSettingsField(
          label: 'Description',
          child: TextField(
            key: const ValueKey('guild-overview-description'),
            controller: _description,
            maxLines: 2,
            decoration: const InputDecoration(isDense: true),
          ),
        ),
        GuildSettingsField(
          label: 'Verification level',
          hint: 'How much an account must prove before it can talk here.',
          child: DropdownButtonFormField<GuildVerificationLevel>(
            key: const ValueKey('guild-overview-verification'),
            initialValue: _verification ?? settings.verificationLevel,
            isExpanded: true,
            decoration: const InputDecoration(isDense: true),
            items: [
              for (final level in GuildVerificationLevel.values)
                DropdownMenuItem(
                  value: level,
                  child: Text(_verificationLabel(level)),
                ),
            ],
            onChanged: (value) => setState(() => _verification = value),
          ),
        ),
        GuildSettingsField(
          label: 'Explicit media filter',
          child: DropdownButtonFormField<GuildExplicitContentFilter>(
            key: const ValueKey('guild-overview-content-filter'),
            initialValue: _contentFilter ?? settings.explicitContentFilter,
            isExpanded: true,
            decoration: const InputDecoration(isDense: true),
            items: [
              for (final filter in GuildExplicitContentFilter.values)
                DropdownMenuItem(
                  value: filter,
                  child: Text(_filterLabel(filter)),
                ),
            ],
            onChanged: (value) => setState(() => _contentFilter = value),
          ),
        ),
        GuildSettingsField(
          label: 'Default notifications',
          child: DropdownButtonFormField<GuildNotificationLevel>(
            key: const ValueKey('guild-overview-notifications'),
            initialValue:
                _notifications ?? settings.defaultMessageNotifications,
            isExpanded: true,
            decoration: const InputDecoration(isDense: true),
            items: [
              for (final level in GuildNotificationLevel.selectable)
                DropdownMenuItem(
                  value: level,
                  child: Text(_notificationLabel(level)),
                ),
            ],
            onChanged: (value) => setState(() => _notifications = value),
          ),
        ),
        GuildSettingsField(
          label: 'Inactive channel',
          child: _channelPicker(
            valueKey: 'guild-overview-afk-channel',
            channels: channels.where(
              (channel) => channel.kind == ChannelKind.voice,
            ),
            selected: _afkChannelEdited ? _afkChannelId : settings.afkChannelId,
            onChanged: (value) => setState(() {
              _afkChannelEdited = true;
              _afkChannelId = value;
            }),
          ),
        ),
        GuildSettingsField(
          label: 'Inactive timeout',
          child: DropdownButtonFormField<int>(
            key: const ValueKey('guild-overview-afk-timeout'),
            initialValue: _timeoutValue(settings),
            isExpanded: true,
            decoration: const InputDecoration(isDense: true),
            items: [
              for (final seconds in GuildOverviewSettings.afkTimeoutChoices)
                DropdownMenuItem(
                  value: seconds,
                  child: Text(_timeoutLabel(seconds)),
                ),
            ],
            onChanged: (value) => setState(() => _afkTimeout = value),
          ),
        ),
        GuildSettingsField(
          label: 'System messages channel',
          child: _channelPicker(
            valueKey: 'guild-overview-system-channel',
            channels: channels.where(
              (channel) => channel.kind == ChannelKind.text,
            ),
            selected: _systemChannelEdited
                ? _systemChannelId
                : settings.systemChannelId,
            onChanged: (value) => setState(() {
              _systemChannelEdited = true;
              _systemChannelId = value;
            }),
          ),
        ),
        SwitchListTile(
          key: const ValueKey('guild-overview-suppress-joins'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Send a message when somebody joins'),
          value: !(_suppressJoins ?? _joinsSuppressed(settings)),
          onChanged: (value) => setState(() => _suppressJoins = !value),
        ),
        SwitchListTile(
          key: const ValueKey('guild-overview-boost-bar'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Show the boost progress bar'),
          value: _boostBar ?? settings.premiumProgressBarEnabled,
          onChanged: (value) => setState(() => _boostBar = value),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            key: const ValueKey('guild-overview-save'),
            onPressed: widget.controller.isBusy ? null : _save,
            child: const Text('Save changes'),
          ),
        ),
      ],
    );
  }

  Widget _channelPicker({
    required String valueKey,
    required Iterable<ConversationChannel> channels,
    required String? selected,
    required ValueChanged<String?> onChanged,
  }) {
    final options = channels.toList(growable: false);
    final known = options.any((channel) => channel.id == selected);
    return DropdownButtonFormField<String?>(
      key: ValueKey(valueKey),
      initialValue: known ? selected : null,
      isExpanded: true,
      decoration: const InputDecoration(isDense: true),
      items: [
        const DropdownMenuItem<String?>(child: Text('No channel')),
        for (final channel in options)
          DropdownMenuItem<String?>(
            value: channel.id,
            child: Text(channel.name, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged,
    );
  }

  int _timeoutValue(GuildOverviewSettings settings) {
    final current = _afkTimeout ?? settings.afkTimeoutSeconds;
    return GuildOverviewSettings.afkTimeoutChoices.contains(current)
        ? current
        : GuildOverviewSettings.afkTimeoutChoices.first;
  }

  static bool _joinsSuppressed(GuildOverviewSettings settings) =>
      GuildSystemChannelFlags.has(
        settings.systemChannelFlags,
        GuildSystemChannelFlags.suppressJoinNotifications,
      );

  void _save() {
    final settings = _settings;
    if (settings == null) return;
    final patch = GuildOverviewPatch();
    final name = _name.text.trim();
    if (name.isNotEmpty && name != settings.name) patch.name = name;
    final description = _description.text.trim();
    if (description != (settings.description ?? '')) {
      patch.description = description.isEmpty ? null : description;
    }
    if (_verification != null && _verification != settings.verificationLevel) {
      patch.verificationLevel = _verification!;
    }
    if (_contentFilter != null &&
        _contentFilter != settings.explicitContentFilter) {
      patch.explicitContentFilter = _contentFilter!;
    }
    if (_notifications != null &&
        _notifications != settings.defaultMessageNotifications) {
      patch.defaultMessageNotifications = _notifications!;
    }
    if (_afkChannelEdited && _afkChannelId != settings.afkChannelId) {
      patch.afkChannelId = _afkChannelId;
    }
    if (_afkTimeout != null && _afkTimeout != settings.afkTimeoutSeconds) {
      patch.afkTimeoutSeconds = _afkTimeout!;
    }
    if (_systemChannelEdited && _systemChannelId != settings.systemChannelId) {
      patch.systemChannelId = _systemChannelId;
    }
    if (_suppressJoins != null &&
        _suppressJoins != _joinsSuppressed(settings)) {
      // Only the one bit is touched. A guild may carry suppression flags this
      // build has no control for, and rewriting the whole field would clear
      // them.
      patch.systemChannelFlags = GuildSystemChannelFlags.withFlag(
        settings.systemChannelFlags,
        GuildSystemChannelFlags.suppressJoinNotifications,
        enabled: _suppressJoins!,
      );
    }
    if (_boostBar != null && _boostBar != settings.premiumProgressBarEnabled) {
      patch.premiumProgressBarEnabled = _boostBar!;
    }
    unawaited(widget.controller.saveOverview(patch));
  }

  static String _verificationLabel(GuildVerificationLevel level) =>
      switch (level) {
        GuildVerificationLevel.none => 'None',
        GuildVerificationLevel.low => 'Low - verified email',
        GuildVerificationLevel.medium => 'Medium - registered 5 minutes',
        GuildVerificationLevel.high => 'High - a member for 10 minutes',
        GuildVerificationLevel.veryHigh => 'Highest - verified phone',
      };

  static String _filterLabel(GuildExplicitContentFilter filter) =>
      switch (filter) {
        GuildExplicitContentFilter.disabled => 'Do not scan',
        GuildExplicitContentFilter.membersWithoutRoles =>
          'Scan members without a role',
        GuildExplicitContentFilter.allMembers => 'Scan everybody',
      };

  static String _notificationLabel(GuildNotificationLevel level) =>
      switch (level) {
        GuildNotificationLevel.allMessages => 'All messages',
        GuildNotificationLevel.onlyMentions => 'Only @mentions',
        GuildNotificationLevel.noMessages => 'Nothing',
      };

  static String _timeoutLabel(int seconds) => switch (seconds) {
    60 => '1 minute',
    300 => '5 minutes',
    900 => '15 minutes',
    1800 => '30 minutes',
    _ => '1 hour',
  };
}
