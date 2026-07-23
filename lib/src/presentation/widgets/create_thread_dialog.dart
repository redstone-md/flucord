import 'package:flutter/material.dart';

import '../../theme/flucord_theme.dart';

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
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(20),
    backgroundColor: context.surfaces.surface,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(6),
      side: BorderSide(color: context.surfaces.border),
    ),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DialogHeader(
              onClose: _isCreating ? null : () => Navigator.pop(context),
            ),
            const SizedBox(height: 16),
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
                fontSize: 10,
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
                  textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 10)),
                ),
              ),
            ),
            if (_error case final error?) ...[
              const SizedBox(height: 12),
              _DialogError(message: error),
            ],
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _isCreating ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  key: const ValueKey('create-thread-confirm'),
                  onPressed: _isCreating ? null : _submit,
                  icon: _isCreating
                      ? const SizedBox.square(
                          dimension: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.forum_outlined, size: 16),
                  label: const Text('Create thread'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _DialogHeader extends StatelessWidget {
  const _DialogHeader({required this.onClose});

  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Icon(Icons.forum_outlined, size: 18),
      const SizedBox(width: 8),
      const Expanded(
        child: Text(
          'Create thread',
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

class _DialogError extends StatelessWidget {
  const _DialogError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(
        Icons.error_outline,
        size: 15,
        color: Theme.of(context).colorScheme.error,
      ),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          message,
          style: TextStyle(
            color: Theme.of(context).colorScheme.error,
            fontSize: 11,
          ),
        ),
      ),
    ],
  );
}
