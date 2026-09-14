import 'package:file_picker/file_picker.dart';

import '../domain/chat_models.dart';

abstract interface class PendingAttachmentPicker {
  Future<List<PendingAttachment>> pick();
}

final class PendingAttachmentSelection {
  final List<PendingAttachment> _items = [];

  List<PendingAttachment> get items => List.unmodifiable(_items);
  bool get isEmpty => _items.isEmpty;
  bool get isNotEmpty => _items.isNotEmpty;

  bool merge(Iterable<PendingAttachment> attachments) {
    var reachedLimit = false;
    for (final attachment in attachments) {
      if (_items.any((item) => item.path == attachment.path)) continue;
      if (_items.length == PendingAttachment.maxCount) {
        reachedLimit = true;
        continue;
      }
      _items.add(attachment);
    }
    return reachedLimit;
  }

  void removeAt(int index) => _items.removeAt(index);

  /// Puts [attachment] in one slot's place, which is how the spoiler tag is
  /// applied without changing the order the files were picked in.
  ///
  /// The slot's own path still matches, because tagging a file renames it
  /// rather than replacing it; only the other slots need to stay distinct.
  void replaceAt(int index, PendingAttachment attachment) {
    if (index < 0 || index >= _items.length) return;
    for (var other = 0; other < _items.length; other++) {
      if (other != index && _items[other].path == attachment.path) return;
    }
    _items[index] = attachment;
  }

  void clear() => _items.clear();
}

final class NativePendingAttachmentPicker implements PendingAttachmentPicker {
  const NativePendingAttachmentPicker();

  @override
  Future<List<PendingAttachment>> pick() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Attach files',
      allowMultiple: true,
      lockParentWindow: true,
    );
    if (result == null) return const [];
    return result.files
        .where((file) => file.path != null)
        .map(
          (file) => PendingAttachment(
            name: file.name,
            path: file.path!,
            size: file.size,
          ),
        )
        .toList(growable: false);
  }
}
