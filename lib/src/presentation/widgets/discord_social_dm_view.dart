import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/discord_social_dm_controller.dart';
import '../../domain/chat_models.dart';
import '../../domain/discord_relationship.dart';
import '../../domain/discord_snowflake.dart';
import '../../domain/discord_social_dm.dart';
import '../../theme/flucord_icons.dart';
import '../../theme/flucord_radius.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';
import 'accessibility_scope.dart';
import 'chat_header.dart';
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
  /// The narrowest the conversation gets beside the profile panel. Below it
  /// the panel and its button stay out.
  static const _minChatWidth = 480.0;

  late final AppLifecycleListener _lifecycleListener;
  late bool _foreground;
  bool _showProfile = true;

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
    final user = widget.user;
    return LayoutBuilder(
      builder: (context, constraints) {
        final profileFits =
            constraints.maxWidth >=
            _minChatWidth + DirectMessageProfilePanel.width;
        final showProfile = profileFits && _showProfile;
        return ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) => Row(
            key: ValueKey('social-dm-view-${user.id}'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Column(
                  children: [
                    ChatHeader(
                      key: const ValueKey('social-dm-header'),
                      channel: _headerChannel(user),
                      leading: DiscordRelationshipAvatar(
                        user: user,
                        size: DirectMessageHeaderAvatar.size,
                        presenceBorderColor: context.surfaces.canvas,
                      ),
                      // The SDK has no calls, pins, search or inbox, so the
                      // profile is the header's only action.
                      showMembers: showProfile,
                      onToggleMembers: profileFits
                          ? () => setState(() => _showProfile = !_showProfile)
                          : null,
                    ),
                    Expanded(
                      child: _DmTimeline(
                        controller: widget.controller,
                        user: user,
                        messages: widget.controller.messagesFor(user.id),
                        loading: widget.controller.isLoadingMessages(user.id),
                        error: widget.controller.messageErrorFor(user.id),
                        onRetry: () => unawaited(
                          widget.controller.loadMessages(
                            user.id,
                            refresh: true,
                          ),
                        ),
                      ),
                    ),
                    _DmComposer(controller: widget.controller, user: user),
                  ],
                ),
              ),
              if (showProfile)
                DirectMessageProfilePanel(
                  avatar: DiscordRelationshipAvatar(
                    user: user,
                    size: DirectMessageProfilePanel.avatarSize,
                    presenceBorderColor: context.surfaces.surface,
                  ),
                  name: user.displayName,
                  username: user.username,
                  status: user.status.presence,
                  memberSince: DiscordSnowflake.createdAt(user.id),
                ),
            ],
          ),
        );
      },
    );
  }

  /// The DM as the chat header reads it: a channel named after the person.
  static ConversationChannel _headerChannel(DiscordRelationshipUser user) =>
      ConversationChannel(
        id: 'social-dm-${user.id}',
        spaceId: CommunitySpace.directMessagesId,
        name: user.displayName,
        topic: '',
        kind: ChannelKind.text,
        recipientIds: [user.id],
      );
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
            username: user.username,
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
