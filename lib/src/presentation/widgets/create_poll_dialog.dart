import 'package:flutter/material.dart';

import '../../domain/chat_models.dart';
import '../../theme/flucord_theme.dart';

typedef CreatePollCallback = Future<bool> Function(PendingPoll poll);

class CreatePollDialog extends StatefulWidget {
  const CreatePollDialog({required this.onCreate, super.key});

  final CreatePollCallback onCreate;

  static Future<bool> show(
    BuildContext context, {
    required CreatePollCallback onCreate,
  }) async =>
      await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => CreatePollDialog(onCreate: onCreate),
      ) ??
      false;

  @override
  State<CreatePollDialog> createState() => _CreatePollDialogState();
}

class _CreatePollDialogState extends State<CreatePollDialog> {
  final TextEditingController _questionController = TextEditingController();
  final List<TextEditingController> _answerControllers = [
    TextEditingController(),
    TextEditingController(),
  ];
  int _durationHours = 24;
  bool _allowMultiselect = false;
  bool _isCreating = false;
  String? _error;

  @override
  void dispose() {
    _questionController.dispose();
    for (final controller in _answerControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _addAnswer() {
    if (_isCreating || _answerControllers.length == PendingPoll.maxAnswers) {
      return;
    }
    setState(() => _answerControllers.add(TextEditingController()));
  }

  void _removeAnswer(int index) {
    if (_isCreating || _answerControllers.length == PendingPoll.minAnswers) {
      return;
    }
    final controller = _answerControllers.removeAt(index);
    controller.dispose();
    setState(() {});
  }

  Future<void> _submit() async {
    final poll = PendingPoll(
      question: _questionController.text,
      answers: _answerControllers.map((controller) => controller.text).toList(),
      durationHours: _durationHours,
      allowMultiselect: _allowMultiselect,
    ).normalized();
    final error = _validationError(poll);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _isCreating = true;
      _error = null;
    });
    final created = await widget.onCreate(poll);
    if (!mounted) return;
    if (created) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _isCreating = false;
      _error = 'Could not create the poll.';
    });
  }

  static String? _validationError(PendingPoll poll) {
    if (poll.question.isEmpty) return 'Enter a question.';
    if (poll.answers.any((answer) => answer.isEmpty)) {
      return 'Fill in every answer.';
    }
    return poll.isValid ? null : 'Review the poll fields.';
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(20),
    backgroundColor: context.surfaces.surface,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(6),
      side: BorderSide(color: context.surfaces.border),
    ),
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 540,
        maxHeight: MediaQuery.sizeOf(context).height - 40,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PollDialogHeader(
              onClose: _isCreating ? null : () => Navigator.pop(context),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('poll-question'),
              controller: _questionController,
              autofocus: true,
              enabled: !_isCreating,
              maxLength: PendingPoll.maxQuestionLength,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Question',
                hintText: 'What should the channel decide?',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 8),
            _PollFieldLabel(
              label: 'ANSWERS',
              detail: '${_answerControllers.length}/${PendingPoll.maxAnswers}',
            ),
            const SizedBox(height: 6),
            for (var index = 0; index < _answerControllers.length; index++) ...[
              _PollAnswerField(
                index: index,
                controller: _answerControllers[index],
                enabled: !_isCreating,
                canRemove: _answerControllers.length > PendingPoll.minAnswers,
                onRemove: () => _removeAnswer(index),
              ),
              if (index != _answerControllers.length - 1)
                const SizedBox(height: 8),
            ],
            const SizedBox(height: 8),
            TextButton.icon(
              key: const ValueKey('add-poll-answer'),
              onPressed:
                  _isCreating ||
                      _answerControllers.length == PendingPoll.maxAnswers
                  ? null
                  : _addAnswer,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add answer'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              key: const ValueKey('poll-duration'),
              initialValue: _durationHours,
              decoration: const InputDecoration(labelText: 'Duration'),
              items: const [
                DropdownMenuItem(value: 1, child: Text('1 hour')),
                DropdownMenuItem(value: 4, child: Text('4 hours')),
                DropdownMenuItem(value: 8, child: Text('8 hours')),
                DropdownMenuItem(value: 24, child: Text('1 day')),
                DropdownMenuItem(value: 72, child: Text('3 days')),
                DropdownMenuItem(value: 168, child: Text('1 week')),
                DropdownMenuItem(value: 336, child: Text('2 weeks')),
                DropdownMenuItem(value: 768, child: Text('32 days')),
              ],
              onChanged: _isCreating
                  ? null
                  : (value) {
                      if (value != null) setState(() => _durationHours = value);
                    },
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              key: const ValueKey('poll-multiselect'),
              value: _allowMultiselect,
              onChanged: _isCreating
                  ? null
                  : (value) => setState(() => _allowMultiselect = value),
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text(
                'Allow multiple answers',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
            if (_error case final error?) ...[
              const SizedBox(height: 8),
              Text(
                error,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 11,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _isCreating ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  key: const ValueKey('create-poll-confirm'),
                  onPressed: _isCreating ? null : _submit,
                  icon: _isCreating
                      ? const SizedBox.square(
                          dimension: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.poll_outlined, size: 16),
                  label: const Text('Create poll'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _PollDialogHeader extends StatelessWidget {
  const _PollDialogHeader({required this.onClose});

  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Icon(Icons.poll_outlined, size: 18),
      const SizedBox(width: 8),
      const Expanded(
        child: Text(
          'Create a poll',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      IconButton(
        onPressed: onClose,
        icon: const Icon(Icons.close, size: 18),
        tooltip: 'Close',
      ),
    ],
  );
}

class _PollAnswerField extends StatelessWidget {
  const _PollAnswerField({
    required this.index,
    required this.controller,
    required this.enabled,
    required this.canRemove,
    required this.onRemove,
  });

  final int index;
  final TextEditingController controller;
  final bool enabled;
  final bool canRemove;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: TextField(
          key: ValueKey('poll-answer-$index'),
          controller: controller,
          enabled: enabled,
          maxLength: PendingPoll.maxAnswerLength,
          decoration: InputDecoration(
            labelText: 'Answer ${index + 1}',
            counterText: '',
          ),
        ),
      ),
      const SizedBox(width: 4),
      SizedBox.square(
        dimension: 40,
        child: IconButton(
          onPressed: enabled && canRemove ? onRemove : null,
          icon: const Icon(Icons.close, size: 17),
          tooltip: 'Remove answer',
        ),
      ),
    ],
  );
}

class _PollFieldLabel extends StatelessWidget {
  const _PollFieldLabel({required this.label, required this.detail});

  final String label;
  final String detail;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(
        label,
        style: TextStyle(
          color: context.surfaces.muted,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
      const Spacer(),
      Text(
        detail,
        style: TextStyle(color: context.surfaces.muted, fontSize: 10),
      ),
    ],
  );
}
