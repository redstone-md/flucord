import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/chat_controller.dart';
import '../../domain/guild_join_gate.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';
import 'flucord_dialog.dart';

/// What Discord asks of somebody who just joined [spaceId]: its onboarding
/// questions first, then its rules while the membership is pending. A
/// server that asks neither shows nothing, and so does a session that
/// cannot answer.
Future<void> showGuildJoinSteps(
  BuildContext context, {
  required ChatController chat,
  required String spaceId,
}) async {
  if (!chat.canAnswerJoinGate) return;
  final onboarding = await _orNull(chat.loadOnboarding(spaceId));
  if (onboarding != null && context.mounted) {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => GuildOnboardingDialog(chat: chat, onboarding: onboarding),
    );
  }
  if (!context.mounted || !(chat.workspace?.isPendingIn(spaceId) ?? false)) {
    return;
  }
  await showGuildRulesDialog(context, chat: chat, spaceId: spaceId);
}

/// Opens [spaceId]'s rules, to be read and agreed to.
Future<void> showGuildRulesDialog(
  BuildContext context, {
  required ChatController chat,
  required String spaceId,
}) => showDialog<void>(
  context: context,
  builder: (_) => GuildRulesDialog(chat: chat, spaceId: spaceId),
);

/// A failed read of an optional step is the same as no step: the join
/// already worked, and the server can still be used.
Future<T?> _orNull<T>(Future<T?> load) async {
  try {
    return await load;
  } on Exception {
    return null;
  }
}

/// A server's rules screening: the rules, a box to agree, its written and
/// multiple-choice questions, and Submit.
class GuildRulesDialog extends StatefulWidget {
  const GuildRulesDialog({
    required this.chat,
    required this.spaceId,
    super.key,
  });

  final ChatController chat;
  final String spaceId;

  @override
  State<GuildRulesDialog> createState() => _GuildRulesDialogState();
}

class _GuildRulesDialogState extends State<GuildRulesDialog> {
  late final Future<RulesScreening?> _screening = widget.chat
      .loadRulesScreening(widget.spaceId);

  /// The screening with the answers given so far, once it has loaded.
  RulesScreening? _answered;
  bool _agreed = false;
  bool _sending = false;
  String? _message;

  Future<void> _accept(RulesScreening screening) async {
    setState(() {
      _sending = true;
      _message = null;
    });
    try {
      await widget.chat.acceptRules(widget.spaceId, screening);
    } on GuildJoinGateRefusal catch (refusal) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _message = refusal.message;
      });
      return;
    }
    if (!mounted) return;
    if (widget.chat.workspace?.isPendingIn(widget.spaceId) ?? false) {
      setState(() {
        _sending = false;
        _message =
            'Your answers were sent. The server will let you in once its '
            'moderators approve them.';
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<RulesScreening?>(
    future: _screening,
    builder: (context, snapshot) {
      final loaded = snapshot.data;
      final screening = _answered ?? loaded;
      final canAccept = screening != null && screening.canAccept;
      final hasRules = screening?.rules.isNotEmpty ?? false;
      return FlucordDialog(
        key: const ValueKey('guild-rules-dialog'),
        title: const Text('Read the server rules'),
        description: screening?.description,
        maxWidth: 480,
        content: switch (snapshot) {
          AsyncSnapshot(connectionState: ConnectionState.waiting) =>
            const Center(
              child: SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          AsyncSnapshot(hasError: true) => _note(
            context,
            'The rules could not be loaded. Try again in a moment.',
          ),
          _ when screening == null => _note(
            context,
            'This server has no rules to agree to.',
          ),
          _ => _rules(context, screening),
        },
        confirm: canAccept
            ? FlucordDialogConfirm(
                key: const ValueKey('guild-rules-submit'),
                label: _sending ? 'Submitting' : 'Submit',
                onPressed:
                    (_agreed || !hasRules) && screening.isAnswered && !_sending
                    ? () => unawaited(_accept(screening))
                    : null,
              )
            : null,
      );
    },
  );

  Widget _rules(BuildContext context, RulesScreening screening) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (index, rule) in screening.rules.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 24,
                child: Text(
                  '${index + 1}.',
                  style: FlucordTextRole.body.style.copyWith(
                    color: context.surfaces.muted,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  rule,
                  style: FlucordTextRole.body.style.copyWith(
                    color: context.surfaces.text,
                  ),
                ),
              ),
            ],
          ),
        ),
      if (screening.canAccept) ...[
        for (final (index, field) in screening.fields.indexed)
          if (field.isWritten || field.isMultipleChoice)
            _question(context, screening, index, field),
      ],
      if (screening.canAccept && screening.rules.isNotEmpty)
        CheckboxListTile(
          key: const ValueKey('guild-rules-agree'),
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _agreed,
          onChanged: _sending
              ? null
              : (value) => setState(() => _agreed = value ?? false),
          title: const Text('I have read and agree to the rules'),
        )
      else if (!screening.canAccept)
        _note(
          context,
          'This server asks you to verify your account first. '
          'Finish joining it in the Discord app.',
        ),
      if (_message case final message?) _note(context, message),
    ],
  );

  /// One written or multiple-choice question, with its label above it.
  Widget _question(
    BuildContext context,
    RulesScreening screening,
    int index,
    RulesScreeningField field,
  ) {
    // Read from the state, not this build: two answers can land before the
    // next frame.
    void answer(ScreeningAnswer? answer) => setState(
      () => _answered = (_answered ?? screening).answer(index, answer),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            field.label,
            style: FlucordTextRole.body.style.copyWith(
              color: context.surfaces.text,
            ),
          ),
          if (field.description case final description?)
            _note(context, description),
          const SizedBox(height: 6),
          if (field.isWritten)
            TextField(
              key: ValueKey('guild-rules-answer-$index'),
              enabled: !_sending,
              maxLength: field.maxLength,
              minLines: field.type == RulesScreeningField.paragraphType ? 3 : 1,
              maxLines: field.type == RulesScreeningField.paragraphType ? 6 : 1,
              decoration: InputDecoration(hintText: field.placeholder),
              onChanged: (text) => answer(ScreeningAnswer.text(text)),
            )
          else
            RadioGroup<int>(
              groupValue: switch (field.answer) {
                ScreeningChoice(:final index) => index,
                _ => null,
              },
              onChanged: (choice) => _sending || choice == null
                  ? null
                  : answer(ScreeningAnswer.choice(choice)),
              child: Column(
                children: [
                  for (final (choice, label) in field.choices.indexed)
                    RadioListTile<int>(
                      key: ValueKey('guild-rules-answer-$index-$choice'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(label),
                      value: choice,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A server's onboarding, one question at a time.
class GuildOnboardingDialog extends StatefulWidget {
  const GuildOnboardingDialog({
    required this.chat,
    required this.onboarding,
    super.key,
  });

  final ChatController chat;
  final GuildOnboarding onboarding;

  @override
  State<GuildOnboardingDialog> createState() => _GuildOnboardingDialogState();
}

class _GuildOnboardingDialogState extends State<GuildOnboardingDialog> {
  final Set<String> _chosen = {};
  int _index = 0;
  bool _sending = false;
  String? _message;

  List<OnboardingPrompt> get _prompts => widget.onboarding.prompts;
  OnboardingPrompt get _prompt => _prompts[_index];
  bool get _isLast => _index == _prompts.length - 1;

  bool get _answered =>
      !_prompt.required ||
      _prompt.options.any((option) => _chosen.contains(option.id));

  void _toggle(OnboardingOption option) => setState(() {
    if (_chosen.remove(option.id)) return;
    if (_prompt.singleSelect) {
      _chosen.removeAll(_prompt.options.map((other) => other.id));
    }
    _chosen.add(option.id);
  });

  Future<void> _next() async {
    if (!_isLast) {
      setState(() => _index++);
      return;
    }
    setState(() {
      _sending = true;
      _message = null;
    });
    try {
      await widget.chat.answerOnboarding(widget.onboarding, {..._chosen});
    } on GuildJoinGateRefusal catch (refusal) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _message = refusal.message;
      });
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => FlucordDialog(
    key: const ValueKey('guild-onboarding-dialog'),
    title: Text(_prompt.title),
    description: _prompts.length > 1
        ? 'Question ${_index + 1} of ${_prompts.length}'
        : null,
    maxWidth: 480,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final option in _prompt.options)
          CheckboxListTile(
            key: ValueKey('onboarding-${option.id}'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _chosen.contains(option.id),
            onChanged: _sending ? null : (_) => _toggle(option),
            title: Text(
              [?option.emoji, option.title].join(' '),
              style: FlucordTextRole.body.style.copyWith(
                color: context.surfaces.text,
              ),
            ),
            subtitle: switch (option.description) {
              final description? => Text(description),
              null => null,
            },
          ),
        if (_message case final message?) _note(context, message),
      ],
    ),
    actions: [
      if (_index > 0)
        TextButton(
          key: const ValueKey('guild-onboarding-back'),
          onPressed: _sending ? null : () => setState(() => _index--),
          child: const Text('Back'),
        ),
    ],
    cancelEnabled: !_sending,
    confirm: FlucordDialogConfirm(
      key: const ValueKey('guild-onboarding-next'),
      label: _isLast ? 'Finish' : 'Next',
      onPressed: _answered && !_sending ? () => unawaited(_next()) : null,
    ),
  );
}

Widget _note(BuildContext context, String text) => Padding(
  padding: const EdgeInsets.only(top: 8),
  child: Text(
    text,
    style: FlucordTextRole.caption.style.copyWith(
      color: context.surfaces.muted,
    ),
  ),
);
