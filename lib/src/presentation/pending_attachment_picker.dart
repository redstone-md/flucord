import 'package:file_picker/file_picker.dart';

import '../domain/chat_models.dart';

abstract interface class PendingAttachmentPicker {
  Future<List<PendingAttachment>> pick();
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
