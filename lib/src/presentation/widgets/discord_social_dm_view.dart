import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/discord_social_dm_controller.dart';
import '../../domain/discord_relationship.dart';
import '../../domain/discord_social_dm.dart';
import '../../theme/flucord_theme.dart';
import 'discord_social_dm_message_row.dart';

class DiscordSocialDmView extends StatefulWidget {
  const DiscordSocialDmView({
    required this.controller,
    required this.user,
    super.key,
  });

  final DiscordSocialDmController controller;
  final DiscordRelationshipUser user;

  @override
  State<DiscordSocialDmView> createState() => _DiscordSocialDmViewState();
}

class _DiscordSocialDmViewState extends State<DiscordSocialDmView> {
  late final AppLifecycleListener _lifecycleListener;
  late bool _foreground;

  @override
  void initState() {
    super.initState();
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    _foreground =
        lifecycleState == null || lifecycleState == AppLifecycleState.resumed;
    _lifecycleListener = AppLifecycleListener(
      onStateChange: _handleLifecycleState,
    );
    _scheduleViewSynchronization(loadMessages: true);
  }

  @override
  void didUpdateWidget(DiscordSocialDmView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(oldWidget.controller.setShowingChat(false));
      });
    }
    if (oldWidget.controller != widget.controller ||
        oldWidget.user.id != widget.user.id) {
      _scheduleViewSynchronization(loadMessages: true);
    }
  }

  void _scheduleViewSynchronization({required bool loadMessages}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (loadMessages) {
        unawaited(widget.controller.loadMessages(widget.user.id));
      }
      unawaited(widget.controller.setShowingChat(_foreground));
    });
  }

  void _handleLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (_foreground == foreground) return;
    _foreground = foreground;
    unawaited(widget.controller.setShowingChat(foreground));
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    unawaited(widget.controller.setShowingChat(false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => Column(
        key: ValueKey('social-dm-view-${widget.user.id}'),
        children: [
          _DmHeader(user: widget.user),
          Expanded(
            child: _DmTimeline(
              controller: widget.controller,
              user: widget.user,
              messages: widget.controller.messagesFor(widget.user.id),
              loading: widget.controller.isLoadingMessages(widget.user.id),
              error: widget.controller.messageErrorFor(widget.user.id),
              onRetry: () => unawaited(
                widget.controller.loadMessages(widget.user.id, refresh: true),
              ),
            ),
          ),
          _DmComposer(controller: widget.controller, user: widget.user),
        ],
      ),
    );
  }
}

class _DmHeader extends StatelessWidget {
  const _DmHeader({required this.user});

  final DiscordRelationshipUser user;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.surfaces.border)),
      ),
      child: Row(
        children: [
          const Icon(Icons.alternate_email, size: 18),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              user.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          Icon(Icons.phone_outlined, size: 18, color: context.surfaces.muted),
          const SizedBox(width: 16),
          Icon(
            Icons.videocam_outlined,
            size: 19,
            color: context.surfaces.muted,
          ),
          const SizedBox(width: 16),
          Icon(Icons.person_outline, size: 19, color: context.surfaces.muted),
        ],
      ),
    );
  }
}

class _DmTimeline extends StatelessWidget {
  const _DmTimeline({
    required this.controller,
    required this.user,
    required this.messages,
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  final DiscordSocialDmController controller;
  final DiscordRelationshipUser user;
  final List<DiscordSocialDmMessage> messages;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (loading && messages.isEmpty) {
      return const Center(
        child: SizedBox.square(
          key: ValueKey('social-dm-loading'),
          dimension: 26,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (error != null && messages.isEmpty) {
      return _DmTimelineState(
        key: const ValueKey('social-dm-error'),
        icon: Icons.error_outline,
        title: 'Messages could not be loaded',
        detail: 'The native Discord chat request failed ($error).',
        action: OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
      );
    }
    if (messages.isEmpty) {
      return _DmTimelineState(
        key: const ValueKey('social-dm-empty'),
        icon: Icons.waving_hand_outlined,
        title: 'This is the beginning of your conversation',
        detail: 'Send a message to ${user.displayName}.',
      );
    }
    return ListView.builder(
      key: const ValueKey('social-dm-timeline'),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
      itemCount: messages.length,
      itemBuilder: (context, index) => DiscordSocialDmMessageRow(
        key: ValueKey('social-dm-message-${messages[index].id}'),
        controller: controller,
        message: messages[index],
      ),
    );
  }
}

class _DmComposer extends StatefulWidget {
  const _DmComposer({required this.controller, required this.user});

  final DiscordSocialDmController controller;
  final DiscordRelationshipUser user;

  @override
  State<_DmComposer> createState() => _DmComposerState();
}

class _DmComposerState extends State<_DmComposer> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final content = _textController.text;
    if (content.trim().isEmpty || widget.controller.isSending(widget.user.id)) {
      return;
    }
    final sent = await widget.controller.sendMessage(widget.user.id, content);
    if (sent && mounted) {
      _textController.clear();
      _focusNode.requestFocus();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final sending = widget.controller.isSending(widget.user.id);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
      child: Container(
        decoration: BoxDecoration(
          color: context.surfaces.raised,
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.only(left: 12, right: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.enter): _submit,
                },
                child: TextField(
                  key: const ValueKey('social-dm-composer'),
                  controller: _textController,
                  focusNode: _focusNode,
                  minLines: 1,
                  maxLines: 5,
                  maxLength: 2000,
                  enabled: !sending,
                  decoration: InputDecoration(
                    hintText: 'Message @${widget.user.displayName}',
                    border: InputBorder.none,
                    counterText: '',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ),
            IconButton(
              key: const ValueKey('social-dm-send'),
              tooltip: 'Send message',
              onPressed: sending || _textController.text.trim().isEmpty
                  ? null
                  : _submit,
              icon: sending
                  ? const SizedBox.square(
                      dimension: 17,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded, size: 19),
            ),
          ],
        ),
      ),
    );
  }
}

class _DmTimelineState extends StatelessWidget {
  const _DmTimelineState({
    required this.icon,
    required this.title,
    required this.detail,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: context.surfaces.muted),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 5),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.surfaces.muted, fontSize: 12),
            ),
            if (action case final action?) ...[
              const SizedBox(height: 14),
              action,
            ],
          ],
        ),
      ),
    );
  }
}
