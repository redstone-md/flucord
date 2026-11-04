import 'package:flutter/material.dart';

import '../../domain/channel_link.dart';
import '../../domain/guild_management.dart';
import '../../theme/flucord_icons.dart';
import '../../theme/flucord_radius.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';
import 'guild_access_scope.dart';
import 'message_embed_view.dart';
import 'remote_identity_image.dart';
import 'streamer_mode_scope.dart';

/// The invite cards under a message's text, one per invite it links.
///
/// Each card asks [GuildAccessScope.previewInvite] for its server. An invite
/// Discord refuses shows the invalid card. Nothing is drawn when the host
/// cannot look invites up, and a lookup that fails in transit leaves only the
/// link in the text until the message is drawn again, when the card asks
/// again.
class MessageInviteCards extends StatelessWidget {
  const MessageInviteCards({
    required this.body,
    required this.sentByMe,
    super.key,
  });

  final String body;

  /// Whether this account wrote the message, which words the invalid card.
  final bool sentByMe;

  @override
  Widget build(BuildContext context) {
    final access = GuildAccessScope.maybeOf(context);
    final lookup = access?.previewInvite;
    if (access == null || lookup == null) return const SizedBox.shrink();
    // Streamer mode hides invite links in the text, so it links none here.
    final codes = InviteLink.codesIn(StreamerModeScope.redact(context, body));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final code in codes)
          _InviteCard(
            key: ValueKey('invite-$code'),
            code: code,
            lookup: lookup,
            sentByMe: sentByMe,
            onJoin: () => access.onOpenInvite(context, code),
          ),
      ],
    );
  }
}

/// One invite, drawn once its lookup answers.
class _InviteCard extends StatefulWidget {
  const _InviteCard({
    required this.code,
    required this.lookup,
    required this.sentByMe,
    required this.onJoin,
    super.key,
  });

  final String code;
  final Future<InvitePreview> Function(String code) lookup;
  final bool sentByMe;
  final VoidCallback onJoin;

  @override
  State<_InviteCard> createState() => _InviteCardState();
}

class _InviteCardState extends State<_InviteCard> {
  /// Asked once per card while it has an answer. The cards are keyed by
  /// code, so a new code is a new card rather than a change to this one.
  late Future<InvitePreview> _preview = _ask();

  /// Whether the last ask failed without an answer about the invite.
  bool _failedInTransit = false;

  Future<InvitePreview> _ask() =>
      widget.lookup(widget.code).catchError((Object error) {
        if (error is! GuildAccessException || !error.isAboutTheInvite) {
          _failedInTransit = true;
        }
        throw error;
      });

  @override
  void didUpdateWidget(_InviteCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_failedInTransit) return;
    _failedInTransit = false;
    _preview = _ask();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _preview,
    builder: (context, snapshot) => switch ((snapshot.data, snapshot.error)) {
      (final preview?, _) => _InviteFrame(
        child: _ValidInvite(preview: preview, onJoin: widget.onJoin),
      ),
      (_, GuildAccessException(isAboutTheInvite: true)) => _InviteFrame(
        child: _InvalidInvite(sentByMe: widget.sentByMe),
      ),
      _ => const SizedBox.shrink(),
    },
  );
}

/// The embed card every invite sits on, with its caption line on top.
class _InviteFrame extends StatelessWidget {
  const _InviteFrame({required this.child});

  /// Discord's invite card width.
  static const _maxWidth = 432.0;
  static const _gapAbove = 8.0;
  static const _padding = 16.0;

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: _gapAbove),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _maxWidth),
      child: Container(
        key: const ValueKey('invite-card'),
        padding: const EdgeInsets.all(_padding),
        decoration: MessageEmbedView.cardDecoration(context.surfaces),
        child: child,
      ),
    ),
  );
}

/// The caption, an icon tile and two lines of text beside it.
class _InviteLayout extends StatelessWidget {
  const _InviteLayout({
    required this.caption,
    required this.tile,
    required this.title,
    required this.detail,
    this.action,
  });

  static const tileSize = 48.0;
  static const _gap = 12.0;

  final String caption;
  final Widget tile;
  final Widget title;
  final Widget detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        caption,
        style: FlucordTextRole.caption.style.copyWith(
          color: context.surfaces.captionText,
          fontWeight: FontWeight.w500,
        ),
      ),
      const SizedBox(height: _gap),
      Row(
        children: [
          SizedBox.square(dimension: tileSize, child: tile),
          const SizedBox(width: _gap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [title, detail],
            ),
          ),
          if (action case final action?) ...[
            const SizedBox(width: _gap),
            action,
          ],
        ],
      ),
    ],
  );
}

class _ValidInvite extends StatelessWidget {
  const _ValidInvite({required this.preview, required this.onJoin});

  final InvitePreview preview;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    final localizations = MaterialLocalizations.of(context);
    final name = preview.name.trim();
    return _InviteLayout(
      caption: "You've been invited to join a server",
      tile: ClipRRect(
        borderRadius: FlucordRadius.large,
        child: RemoteIdentityImage(
          url: preview.iconUrl,
          fallback: ColoredBox(
            color: surfaces.control,
            child: Center(
              child: Text(
                name.isEmpty ? '?' : name.characters.first.toUpperCase(),
                style: FlucordTextRole.heading.style.copyWith(
                  color: surfaces.text,
                ),
              ),
            ),
          ),
        ),
      ),
      title: Text(
        preview.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: FlucordTextRole.heading.style.copyWith(color: surfaces.text),
      ),
      detail: Wrap(
        spacing: _Count.spacing,
        children: [
          if (preview.approximatePresenceCount case final online?)
            _Count(
              dot: surfaces.success,
              label: '${localizations.formatDecimal(online)} Online',
            ),
          if (preview.approximateMemberCount case final members?)
            _Count(
              dot: surfaces.offline,
              label: '${localizations.formatDecimal(members)} Members',
            ),
        ],
      ),
      action: FilledButton(onPressed: onJoin, child: const Text('Join')),
    );
  }
}

/// An invite Discord refused. Danger marks only the icon tile and the title.
class _InvalidInvite extends StatelessWidget {
  const _InvalidInvite({required this.sentByMe});

  /// The tile's danger tint, as the account standing section uses.
  static const _tileAlpha = 0.12;

  final bool sentByMe;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    return _InviteLayout(
      caption: sentByMe
          ? 'You sent an invite, but…'
          : 'You received an invite, but…',
      tile: DecoratedBox(
        decoration: BoxDecoration(
          color: surfaces.danger.withValues(alpha: _tileAlpha),
          borderRadius: FlucordRadius.large,
        ),
        child: FlucordIcon(FlucordIcons.mail, color: surfaces.danger),
      ),
      title: Text(
        'Invalid invite',
        style: FlucordTextRole.heading.style.copyWith(color: surfaces.danger),
      ),
      detail: Text(
        'Try sending a new invite',
        style: FlucordTextRole.caption.style.copyWith(
          color: surfaces.captionText,
        ),
      ),
    );
  }
}

/// A count beside a small coloured dot, as Discord draws online and members.
class _Count extends StatelessWidget {
  const _Count({required this.dot, required this.label});

  /// The space between two counts on one line.
  static const spacing = 12.0;
  static const _dotSize = 8.0;
  static const _gap = 4.0;

  final Color dot;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      DecoratedBox(
        decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
        child: const SizedBox.square(dimension: _dotSize),
      ),
      const SizedBox(width: _gap),
      Text(
        label,
        style: FlucordTextRole.caption.style.copyWith(
          color: context.surfaces.captionText,
        ),
      ),
    ],
  );
}
