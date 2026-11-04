import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/discord_social_dm_controller.dart';
import '../../domain/discord_relationship.dart';
import '../../domain/discord_social_dm.dart';
import '../../theme/flucord_icons.dart';
import '../../theme/flucord_radius.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';
import 'accessibility_scope.dart';
import 'direct_message_views.dart';
import 'discord_relationship_avatar.dart';
import 'discord_social_dm_message_row.dart';
import 'flucord_icon_button.dart';
import 'recessed_field.dart';
import 'spell_check_scope.dart';

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

/// The DM's header, built like the chat header: the person's avatar with a
/// status dot, their name as a heading, and 28 px buttons on the right.
///
/// The native SDK has no calls or profile card here yet, so those buttons
/// show where they will be and stay disabled.
class _DmHeader extends StatelessWidget {
  const _DmHeader({required this.user});

  static const _height = 48.0;
  static const _avatarSize = 24.0;
  static const _gap = 8.0;
  static const _buttonGap = 4.0;

  final DiscordRelationshipUser user;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    return Container(
      key: const ValueKey('social-dm-header'),
      height: _height,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: surfaces.border)),
      ),
      child: Row(
        children: [
          DiscordRelationshipAvatar(
            user: user,
            size: _avatarSize,
            presenceBorderColor: surfaces.canvas,
          ),
          const SizedBox(width: _gap),
          Expanded(
            child: Text(
              user.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: FlucordTextRole.heading.style.copyWith(
                color: surfaces.text,
              ),
            ),
          ),
          const FlucordIconButton(
            icon: FlucordIcons.call,
            tooltip: 'Start call',
            onPressed: null,
          ),
          const SizedBox(width: _buttonGap),
          const FlucordIconButton(
            icon: FlucordIcons.camera,
            tooltip: 'Start video call',
            onPressed: null,
          ),
          const SizedBox(width: _buttonGap),
          const FlucordIconButton(
            icon: FlucordIcons.profile,
            tooltip: 'Profile',
            onPressed: null,
          ),
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
          dimension: FlucordIconButton.size,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (error != null && messages.isEmpty) {
      return _DmTimelineState(
        key: const ValueKey('social-dm-error'),
        icon: FlucordIcons.error,
        title: 'Messages could not be loaded',
        detail: 'The native Discord chat request failed ($error).',
        action: OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
      );
    }
    if (messages.isEmpty) {
      // The start sits on the composer, where the first message will appear.
      return Align(
        alignment: AlignmentDirectional.bottomStart,
        child: SingleChildScrollView(
          child: DirectMessageStart(
            key: const ValueKey('social-dm-empty'),
            avatar: DiscordRelationshipAvatar(
              user: user,
              size: DirectMessageStart.avatarSize,
            ),
            name: user.displayName,
          ),
        ),
      );
    }
    // The rows carry their own 16 px sides, like server messages.
    return ListView.builder(
      key: const ValueKey('social-dm-timeline'),
      padding: const EdgeInsets.only(top: 8, bottom: 16),
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

  /// The empty box's height, the same as the server composer's.
  static const _height = 44.0;

  /// Above and below one line of text, so one line makes [_height].
  static final _textInset = (_height - FlucordTextRole.body.lineHeight) / 2;
  static const _gutter = 16.0;
  static const _buttonInset = 8.0;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    final sending = widget.controller.isSending(widget.user.id);
    const buttonBox = BoxConstraints(
      minWidth: FlucordIconButton.size,
      minHeight: FlucordIconButton.size,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(_gutter, 0, _gutter, _gutter),
      child: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.enter): _submit},
        child: TextField(
          key: const ValueKey('social-dm-composer'),
          controller: _textController,
          focusNode: _focusNode,
          minLines: 1,
          maxLines: 5,
          maxLength: 2000,
          // Same local dictionary as the guild composer, so direct
          // messages underline the same way.
          spellCheckConfiguration: _spellCheckConfiguration(context),
          enabled: !sending,
          style: FlucordTextRole.body.style.copyWith(color: surfaces.text),
          decoration:
              recessedFieldDecoration(
                context,
                borderRadius: FlucordRadius.medium,
              ).copyWith(
                hintText: 'Message @${widget.user.displayName}',
                hintStyle: FlucordTextRole.body.style.copyWith(
                  color: surfaces.captionText,
                ),
                hintMaxLines: 1,
                counterText: '',
                contentPadding: EdgeInsetsDirectional.fromSTEB(
                  _gutter,
                  _textInset,
                  0,
                  _textInset,
                ),
                suffixIconConstraints: buttonBox,
                suffixIcon: Padding(
                  padding: const EdgeInsetsDirectional.only(end: _buttonInset),
                  child: sending
                      ? const SizedBox.square(
                          key: ValueKey('social-dm-send'),
                          dimension: FlucordIconButton.size,
                          child: Center(
                            child: SizedBox.square(
                              dimension: FlucordIconButton.iconSize,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        )
                      : FlucordIconButton(
                          key: const ValueKey('social-dm-send'),
                          tooltip: 'Send message',
                          icon: FlucordIcons.send,
                          color: _textController.text.trim().isEmpty
                              ? null
                              : surfaces.accentIcon,
                          onPressed: _textController.text.trim().isEmpty
                              ? null
                              : _submit,
                        ),
                ),
              ),
          onChanged: (_) => setState(() {}),
        ),
      ),
    );
  }

  /// The spell check configuration the composer runs with, or none where
  /// the switch is off or no service is installed. Same shape as the guild
  /// composer's, so both underlines read as one feature.
  SpellCheckConfiguration _spellCheckConfiguration(BuildContext context) {
    final spellcheck = AccessibilityScope.maybeOf(context)?.spellchecks ?? true;
    final service = SpellCheckScope.maybeOf(context);
    if (!spellcheck || service == null) {
      return const SpellCheckConfiguration.disabled();
    }
    return SpellCheckConfiguration(
      spellCheckService: service,
      misspelledTextStyle: TextField.materialMisspelledTextStyle,
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

  static const _iconSize = 32.0;

  final FlucordIconData icon;
  final String title;
  final String detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final surfaces = context.surfaces;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FlucordIcon(icon, size: _iconSize, color: surfaces.muted),
            const SizedBox(height: 12),
            Text(
              title,
              style: FlucordTextRole.heading.style.copyWith(
                color: surfaces.text,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: FlucordTextRole.caption.style.copyWith(
                color: surfaces.muted,
              ),
            ),
            if (action case final action?) ...[
              const SizedBox(height: 16),
              action,
            ],
          ],
        ),
      ),
    );
  }
}
