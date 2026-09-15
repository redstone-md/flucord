part of 'message_search_panel.dart';

/// The filter controls of the search panel.
///
/// Each control writes one token into the bar text and submits it, so a
/// filter chosen here runs through the exact grammar a typed line runs
/// through. The members and channels the pickers offer are the ones the
/// session can resolve, and the date fields answer in the shapes the bar
/// accepts.
class MessageSearchFilterControls extends StatelessWidget {
  const MessageSearchFilterControls({
    required this.query,
    required this.members,
    required this.channels,
    required this.showChannelFilter,
    required this.onSubmit,
    super.key,
  });

  /// The search bar's text, the line a control edits.
  final String query;

  final List<Member> members;

  /// The channels an `in:` answer may name: exactly the ones the session
  /// allowed the running search to resolve.
  final List<ConversationChannel> channels;

  /// False in a private conversation, whose whole corpus is the channel on
  /// screen; narrowing inside one channel is a question the server cannot
  /// answer.
  final bool showChannelFilter;

  /// Runs the edited line against the corpus and moves the bar text to it.
  final ValueChanged<String> onSubmit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const ValueKey('search-filter-controls'),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _memberFilterButton(context, label: 'from', filter: 'from'),
            _memberFilterButton(context, label: 'mentions', filter: 'mentions'),
            _hasFilterButton(context),
            if (showChannelFilter) _channelFilterButton(context),
            _dateFilterButton(
              context,
              key: const ValueKey('search-filter-before'),
              label: 'before',
              filter: 'before',
            ),
            _dateFilterButton(
              context,
              key: const ValueKey('search-filter-after'),
              label: 'after',
              filter: 'after',
            ),
            _pinnedFilterChip(context),
          ],
        ),
      ),
    );
  }

  Widget _memberFilterButton(
    BuildContext context, {
    required String label,
    required String filter,
  }) => PopupMenuButton<String>(
    key: ValueKey('search-filter-$filter'),
    tooltip: 'Filter by $label',
    icon: const Icon(Icons.person_search_outlined, size: 17),
    position: PopupMenuPosition.under,
    constraints: const BoxConstraints(maxHeight: 260),
    onSelected: (value) => _submit(
      MessageSearchTokenEditor.withToken(query, filter: filter, value: value),
    ),
    itemBuilder: (context) => [
      CheckedPopupMenuItem(
        key: const ValueKey('search-filter-self'),
        value: MessageSearchGrammar.selfToken,
        checked: _filterAnswers(filter, MessageSearchGrammar.selfToken),
        child: const Text('Me'),
      ),
      for (final member in members)
        PopupMenuItem(
          key: ValueKey('search-filter-member-${member.id}'),
          value: member.displayName,
          child: Text(member.displayName),
        ),
    ],
  );

  Widget _hasFilterButton(BuildContext context) => PopupMenuButton<String>(
    key: const ValueKey('search-filter-has'),
    tooltip: 'Filter by content',
    icon: const Icon(Icons.attach_file, size: 17),
    position: PopupMenuPosition.under,
    onSelected: (value) => _submit(
      MessageSearchTokenEditor.withToken(query, filter: 'has', value: value),
    ),
    itemBuilder: (context) => [
      for (final kind in MessageSearchHasKind.values)
        PopupMenuItem(
          key: ValueKey('search-filter-has-${kind.wireValue}'),
          value: kind.wireValue,
          child: Text(kind.wireValue),
        ),
    ],
  );

  Widget _channelFilterButton(BuildContext context) => PopupMenuButton<String>(
    key: const ValueKey('search-filter-in'),
    tooltip: 'Filter by channel',
    icon: const Icon(Icons.tag, size: 17),
    position: PopupMenuPosition.under,
    constraints: const BoxConstraints(maxHeight: 260),
    onSelected: (value) => _submit(
      MessageSearchTokenEditor.withToken(query, filter: 'in', value: value),
    ),
    itemBuilder: (context) => [
      for (final channel in channels)
        PopupMenuItem(
          key: ValueKey('search-filter-channel-${channel.id}'),
          value: channel.name,
          child: Text(channel.name),
        ),
    ],
  );

  Widget _dateFilterButton(
    BuildContext context, {
    required Key key,
    required String label,
    required String filter,
  }) => IconButton(
    key: key,
    tooltip: 'Filter by date $label',
    icon: Icon(
      filter == 'before' ? Icons.calendar_today : Icons.update,
      size: 17,
    ),
    onPressed: () => _showDateDialog(context, filter: filter),
  );

  Widget _pinnedFilterChip(BuildContext context) {
    final selected = MessageSearchTokenEditor.hasFilter(query, 'pinned');
    return FilterChip(
      key: const ValueKey('search-filter-pinned'),
      label: const Text('Pinned', style: TextStyle(fontSize: 11)),
      avatar: const Icon(Icons.push_pin_outlined, size: 13),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => _submit(
        selected
            ? MessageSearchTokenEditor.withoutFilter(query, 'pinned')
            : MessageSearchTokenEditor.withToken(
                query,
                filter: 'pinned',
                value: 'true',
              ),
      ),
    );
  }

  void _showDateDialog(BuildContext context, {required String filter}) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => _DateFilterDialog(
        filter: filter,
        onSubmitted: (value) => _submit(
          MessageSearchTokenEditor.withToken(
            query,
            filter: filter,
            value: value,
          ),
        ),
      ),
    );
  }

  void _submit(String text) => onSubmit(text);

  bool _filterAnswers(String filter, String value) =>
      MessageSearchTokenEditor.answers(query, filter: filter, value: value);
}

/// A date answer for `before:` or `after:`, typed and validated before it
/// becomes a token.
class _DateFilterDialog extends StatefulWidget {
  const _DateFilterDialog({required this.filter, required this.onSubmitted});

  final String filter;
  final ValueChanged<String> onSubmitted;

  @override
  State<_DateFilterDialog> createState() => _DateFilterDialogState();
}

class _DateFilterDialogState extends State<_DateFilterDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    // The grammar accepts single-digit month and day (`2024-5-1`) and a
    // picker that rejected those would call the bar's own answer wrong, so
    // the answer is normalised to the padded shape before it becomes a
    // token.
    final normalized = _normalized(_controller.text.trim());
    if (normalized == null) {
      setState(() => _error = 'Enter a date as YYYY, YYYY-MM or YYYY-MM-DD.');
      return;
    }
    widget.onSubmitted(normalized);
    Navigator.of(context).pop();
  }

  static String? _normalized(String value) {
    final match = RegExp(
      r'^(\d{4})(?:-(\d{1,2})(?:-(\d{1,2}))?)?$',
    ).firstMatch(value);
    if (match == null) return null;
    final year = match.group(1)!;
    final month = match.group(2);
    final day = match.group(3);
    if (month == null) return year;
    final paddedMonth = month.padLeft(2, '0');
    if (day == null) return '$year-$paddedMonth';
    return '$year-$paddedMonth-${day.padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: ValueKey('search-date-${widget.filter}'),
    title: Text('${widget.filter == 'before' ? 'Before' : 'After'} date'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Messages ${widget.filter == 'before' ? 'older' : 'newer'} than a '
          'year, month or day.',
          style: TextStyle(fontSize: 12, color: context.surfaces.muted),
        ),
        const SizedBox(height: 12),
        TextField(
          key: ValueKey('search-date-field-${widget.filter}'),
          controller: _controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: '2024-05-01',
            errorText: _error,
          ),
          onSubmitted: (_) => _submit(),
        ),
      ],
    ),
    actions: [
      TextButton(
        key: ValueKey('search-date-cancel-${widget.filter}'),
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: ValueKey('search-date-apply-${widget.filter}'),
        onPressed: _submit,
        child: const Text('Apply'),
      ),
    ],
  );
}
