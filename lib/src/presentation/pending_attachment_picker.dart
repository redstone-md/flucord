import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

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

/// The files at [paths], as attachments. A folder cannot be uploaded, and a
/// path that has gone away has nothing to upload, so both are left out.
Future<List<PendingAttachment>> pendingAttachmentsAt(
  Iterable<String> paths,
) async => [
  for (final path in paths)
    if (await FileStat.stat(path) case final stat
        when stat.type == FileSystemEntityType.file)
      PendingAttachment(name: p.basename(path), path: path, size: stat.size),
];
