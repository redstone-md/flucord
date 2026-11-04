import 'package:flutter/material.dart';

import '../../theme/flucord_icons.dart';
import '../../theme/flucord_theme.dart';
import '../../theme/flucord_type.dart';
import 'flucord_dialog.dart';

typedef CreateThreadCallback =
    Future<bool> Function(String name, int autoArchiveDurationMinutes);

class CreateThreadDialog extends StatefulWidget {
  const CreateThreadDialog({required this.onCreate, super.key});

  final CreateThreadCallback onCreate;

  static Future<bool> show(
    BuildContext context, {
    required CreateThreadCallback onCreate,
  }) async =>
      await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => CreateThreadDialog(onCreate: onCreate),
      ) ??
      false;

  @override
  State<CreateThreadDialog> createState() => _CreateThreadDialogState();
}

class _CreateThreadDialogState extends State<CreateThreadDialog> {
  final TextEditingController _nameController = TextEditingController();
  int _autoArchiveDurationMinutes = 1440;
  bool _isCreating = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a thread name.');
      return;
    }
    setState(() {
      _isCreating = true;
      _error = null;
    });
    final created = await widget.onCreate(name, _autoArchiveDurationMinutes);
    if (!mounted) return;
    if (created) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _isCreating = false;
      _error = 'Could not create the thread.';
    });
  }

  @override
  Widget build(BuildContext context) => FlucordDialog(
    title: const Text('Create thread'),
    cancelEnabled: !_isCreating,
    confirm: FlucordDialogConfirm(
      key: const ValueKey('create-thread-confirm'),
      label: _isCreating ? 'Creating' : 'Create thread',
      onPressed: _isCreating ? null : _submit,
    ),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const ValueKey('thread-name'),
          controller: _nameController,
          autofocus: true,
          enabled: !_isCreating,
          maxLength: 100,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) {
            if (!_isCreating) _submit();
          },
          decoration: const InputDecoration(
            labelText: 'Thread name',
            hintText: 'New discussion',
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'AUTO-ARCHIVE',
          style: TextStyle(
            color: context.surfaces.muted,
            fontSize: FlucordType.caption,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<int>(
            key: const ValueKey('thread-auto-archive'),
            segments: const [
              ButtonSegment(value: 60, label: Text('1 hour')),
              ButtonSegment(value: 1440, label: Text('24 hours')),
              ButtonSegment(value: 4320, label: Text('3 days')),
              ButtonSegment(value: 10080, label: Text('1 week')),
            ],
            selected: {_autoArchiveDurationMinutes},
            showSelectedIcon: false,
            onSelectionChanged: _isCreating
                ? null
                : (selection) => setState(
                    () => _autoArchiveDurationMinutes = selection.single,
                  ),
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              padding: WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 8),
              ),
              textStyle: WidgetStatePropertyAll(
                TextStyle(fontSize: FlucordType.caption),
              ),
            ),
          ),
        ),
        if (_error case final error?) ...[
          const SizedBox(height: 12),
          _DialogError(message: error),
        ],
      ],
    ),
  );
}

class _DialogError extends StatelessWidget {
  const _DialogError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      FlucordIcon(
        FlucordIcons.error,
        size: 15,
        color: Theme.of(context).colorScheme.error,
      ),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          message,
          style: TextStyle(
            color: Theme.of(context).colorScheme.error,
            fontSize: FlucordType.caption,
          ),
        ),
      ),
    ],
  );
}
