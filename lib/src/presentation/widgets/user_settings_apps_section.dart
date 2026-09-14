import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/app_authorisation_controller.dart';
import '../../domain/app_authorisation.dart';
import '../../theme/flucord_theme.dart';
import 'user_settings_controls.dart';

/// Authorising a bot or app into a server this account manages.
///
/// The page states who is being let in and what they asked for before the
/// consent button does anything: an authorisation is a grant of power over a
/// server, and asking for it blind is how a server ends up with an app
/// nobody meant to add.
class AppAuthorisationSection extends StatefulWidget {
  const AppAuthorisationSection({required this.controller, super.key});

  final AppAuthorisationController controller;

  @override
  State<AppAuthorisationSection> createState() =>
      _AppAuthorisationSectionState();
}

class _AppAuthorisationSectionState extends State<AppAuthorisationSection> {
  final TextEditingController _link = TextEditingController();

  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.loadAuthorisedApplications());
  }

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Column(
        key: const ValueKey('settings-section-apps'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SettingsSectionHeader(
            title: 'App Authorisation',
            subtitle:
                'What this account has let in, and adding a bot or app to '
                'a server you manage.',
          ),
          ..._grants(context, controller),
          const SizedBox(height: 24),
          TextField(
            key: const ValueKey('app-invite-link'),
            controller: _link,
            onSubmitted: (value) => unawaited(controller.readInvite(value)),
            decoration: const InputDecoration(
              hintText: 'Paste a bot or app invite link',
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.tonal(
            key: const ValueKey('app-invite-read'),
            onPressed: controller.stage == AppAuthorisationStage.readingInvite
                ? null
                : () => unawaited(controller.readInvite(_link.text)),
            child: const Text('Read the invite'),
          ),
          const SizedBox(height: 12),
          if (controller.stage == AppAuthorisationStage.idle)
            const Text(
              'An invite link looks like '
              'discord.com/oauth2/authorize?... and names the app it adds.',
              key: ValueKey('app-invite-idle'),
              style: TextStyle(fontSize: 12),
            )
          else
            ..._stages(context, controller),
        ],
      ),
    );
  }

  /// The grants this account has already made, so a review needs no other
  /// page.
  List<Widget> _grants(
    BuildContext context,
    AppAuthorisationController controller,
  ) {
    if (!controller.isAvailable) return const [SizedBox.shrink()];
    return [
      Text(
        'Apps this account has authorised',
        style: Theme.of(context).textTheme.titleSmall,
      ),
      const SizedBox(height: 6),
      if (controller.areGrantsLoading && controller.grants.isEmpty)
        const Padding(
          key: ValueKey('app-grants-loading'),
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (controller.error != null && controller.grants.isEmpty)
        _GrantsError(
          onRetry: () =>
              unawaited(controller.loadAuthorisedApplications(refresh: true)),
        )
      else if (controller.grants.isEmpty)
        const Padding(
          key: ValueKey('app-grants-none'),
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('No apps have been authorised yet.'),
        )
      else ...[
        if (controller.revokeRefusal case final refused?)
          Padding(
            key: const ValueKey('app-grants-revoke-refused'),
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Discord refused to remove $refused. It may already be gone.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        for (final grant in controller.grants)
          _GrantRow(
            grant: grant,
            revoking: controller.isRevoking,
            onRevoke: () =>
                unawaited(controller.revokeAuthorisedApplication(grant)),
          ),
      ],
    ];
  }

  List<Widget> _stages(
    BuildContext context,
    AppAuthorisationController controller,
  ) {
    final invite = controller.invite;
    if (invite == null) {
      // The controller has already returned to idle and the page above says
      // what an invite looks like; there is nothing more to draw here.
      return const [SizedBox.shrink()];
    }
    // A refused read is the page's own answer, not a spinner: the error row
    // and the retry must be reachable whatever stage the controller stopped
    // in, or a failed load wedges the page.
    if (controller.error != null) {
      return [
        Padding(
          key: const ValueKey('app-invite-error'),
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Discord did not answer about this invite.',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                key: const ValueKey('app-invite-retry'),
                onPressed: () =>
                    unawaited(controller.readInvite(_linkFor(controller))),
                child: const Text('Read the invite again'),
              ),
            ],
          ),
        ),
      ];
    }
    return [
      if (controller.stage == AppAuthorisationStage.readingInvite)
        const Padding(
          key: ValueKey('app-invite-reading'),
          padding: EdgeInsets.symmetric(vertical: 12),
          child: CircularProgressIndicator(),
        )
      else ...[
        _InvitationCard(controller: controller, invite: invite),
        if (controller.guilds.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Add to', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          for (final guild in controller.guilds)
            _GuildChoice(
              guild: guild,
              groupValue: controller.selectedGuildId,
              onSelected: () => controller.selectGuild(guild.id),
            ),
        ] else
          const Padding(
            key: ValueKey('app-invite-no-guilds'),
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'You do not manage any server this app could be added to.',
            ),
          ),
        const SizedBox(height: 12),
        if (controller.refusal case final refusal?)
          Padding(
            key: const ValueKey('app-invite-refusal'),
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              switch (refusal.failure) {
                AppAuthorisationFailure.denied =>
                  'The authorisation was declined.',
                AppAuthorisationFailure.refused =>
                  'Discord refused to add it. Check that you manage the '
                      'server and that the app may be added.',
              },
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        if (controller.stage == AppAuthorisationStage.added)
          Padding(
            key: const ValueKey('app-invite-added'),
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Added. ${controller.application?.name ?? 'The app'} is now in '
              'the server.',
              style: TextStyle(fontSize: 12, color: FlucordColors.success),
            ),
          )
        else if (controller.selectedGuildId != null)
          // The button only appears when there is a server to add to: a
          // button that can never be pressed reads as broken.
          FilledButton(
            key: const ValueKey('app-invite-consent'),
            onPressed: controller.stage == AppAuthorisationStage.adding
                ? null
                : () => unawaited(controller.consent()),
            child: const Text('Authorise'),
          ),
      ],
    ];
  }

  /// The link the page is holding. Kept as a getter so the retry reads the
  /// same field the read button did.
  String _linkFor(AppAuthorisationController controller) => _link.text;
}

/// Who is asking in, and what they asked for.
class _InvitationCard extends StatelessWidget {
  const _InvitationCard({required this.controller, required this.invite});

  final AppAuthorisationController controller;
  final AppInvite invite;

  @override
  Widget build(BuildContext context) {
    final application = controller.application;
    return Container(
      key: const ValueKey('app-invite-application'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.surfaces.raised,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  application?.name ?? 'This app',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          if (application case final app? when app.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                app.description,
                style: TextStyle(fontSize: 12, color: context.surfaces.muted),
              ),
            ),
          if (application != null && !application.isPublic)
            Padding(
              key: const ValueKey('app-invite-private'),
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Only the app\'s own team can add it.',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            'Requested scopes',
            key: const ValueKey('app-invite-scopes-title'),
            style: TextStyle(fontSize: 11, color: context.surfaces.muted),
          ),
          const SizedBox(height: 4),
          Wrap(
            key: const ValueKey('app-invite-scopes'),
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final scope in invite.scopes)
                Container(
                  key: ValueKey('app-invite-scope-$scope'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: context.surfaces.inset,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    scope,
                    style: TextStyle(
                      fontSize: 11,
                      color: context.surfaces.muted,
                    ),
                  ),
                ),
            ],
          ),
          if (invite.addsBot) ...[
            const SizedBox(height: 10),
            Text(
              'Bot permissions',
              key: const ValueKey('app-invite-permissions-title'),
              style: TextStyle(fontSize: 11, color: context.surfaces.muted),
            ),
            const SizedBox(height: 4),
            for (final label in controller.requestedPermissionLabels)
              Padding(
                key: ValueKey('app-invite-permission-$label'),
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(label, style: const TextStyle(fontSize: 12)),
              ),
          ],
        ],
      ),
    );
  }
}

class _GuildChoice extends StatelessWidget {
  const _GuildChoice({
    required this.guild,
    required this.groupValue,
    required this.onSelected,
  });

  final AuthorisableGuild guild;
  final String? groupValue;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final selected = groupValue == guild.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        key: ValueKey('app-invite-guild-${guild.id}'),
        onTap: selected ? null : onSelected,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? context.surfaces.raised : Colors.transparent,
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : context.surfaces.border,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 16,
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : context.surfaces.muted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  guild.name,
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.w600 : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One grant, with what it was given and the removal beside it.
///
/// The scopes are shown as Discord names them: renaming them here would
/// tell somebody a grant says something it does not.
class _GrantRow extends StatelessWidget {
  const _GrantRow({
    required this.grant,
    required this.revoking,
    required this.onRevoke,
  });

  final AuthorisedApplication grant;
  final bool revoking;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('app-grant-${grant.applicationId}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.surfaces.raised,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  grant.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (grant.description.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      grant.description,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.surfaces.muted,
                      ),
                    ),
                  ),
                if (grant.scopes.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(
                      key: ValueKey('app-grant-scopes-${grant.applicationId}'),
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final scope in grant.scopes)
                          Container(
                            key: ValueKey('app-grant-scope-$scope'),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: context.surfaces.canvas,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              scope,
                              style: const TextStyle(fontSize: 10),
                            ),
                          ),
                      ],
                    ),
                  ),
                if (grant.authorizedAt != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'authorised ${grant.authorizedAt!.year}'
                      '-${grant.authorizedAt!.month.toString().padLeft(2, '0')}'
                      '-${grant.authorizedAt!.day.toString().padLeft(2, '0')}',
                      key: ValueKey('app-grant-when-${grant.applicationId}'),
                      style: TextStyle(
                        fontSize: 11,
                        color: context.surfaces.muted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          TextButton(
            key: ValueKey('app-grant-revoke-${grant.applicationId}'),
            onPressed: revoking ? null : onRevoke,
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
  }
}

class _GrantsError extends StatelessWidget {
  const _GrantsError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    key: const ValueKey('app-grants-error'),
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Discord did not return your authorisations.'),
        const SizedBox(height: 8),
        TextButton(
          key: const ValueKey('app-grants-retry'),
          onPressed: onRetry,
          child: const Text('Try again'),
        ),
      ],
    ),
  );
}
