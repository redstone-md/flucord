import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pasteboard/pasteboard.dart';
import 'package:path/path.dart' as p;

import '../domain/chat_models.dart';
import 'pending_attachment_picker.dart';

/// What Ctrl+V can attach: files copied in a file manager, or a copied picture.
///
/// An attachment is a path on disk, so a picture is kept as a temp file until
/// it has gone out. Each one has its own folder, because each is `image.png` to
/// the people who receive it, and two pastes must stay two attachments.
abstract final class ClipboardAttachments {
  static final _folder = Directory(
    p.join(Directory.systemTemp.path, 'flucord-pasted'),
  );

  /// Whether what an earlier run left behind is gone. Drafts live in memory, so
  /// nothing can still send those files. It goes on the first paste, in one
  /// synchronous step, so a second paste cannot start inside it. A held future
  /// would not do: it keeps the zone it was made in, and a test's zone ends
  /// with the test.
  static bool _earlierRunCleared = false;

  /// The clipboard's files, or else its picture, or else nothing.
  static Future<List<PendingAttachment>> read() async {
    final files = await pendingAttachmentsAt(await Pasteboard.files());
    if (files.isNotEmpty) return files;
    final image = await Pasteboard.image;
    return image == null ? const [] : [await _keep(await _asPng(image))];
  }

  /// Deletes the temp files among [sent]. A picture of the user's screen should
  /// not stay on disk once it has done its job.
  static Future<void> release(Iterable<PendingAttachment> sent) async {
    for (final attachment in sent) {
      if (p.isWithin(_folder.path, attachment.path)) {
        await _delete(File(attachment.path).parent);
      }
    }
  }

  /// Deletes every pasted picture, sent or not, for a sign-out. A draft that
  /// still names one loses it, which is right: the account it was for is gone.
  static Future<void> clear() => _delete(_folder);

  /// The clipboard's picture is a bitmap on Windows, and a full screen bitmap
  /// can be over the upload limit. A PNG of it is not.
  static Future<Uint8List> _asPng(Uint8List image) async {
    final codec = await ui.instantiateImageCodec(image);
    final frame = await codec.getNextFrame();
    final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    codec.dispose();
    if (png == null) throw StateError('The picture has no PNG form.');
    return png.buffer.asUint8List();
  }

  static Future<PendingAttachment> _keep(Uint8List png) async {
    if (!_earlierRunCleared) {
      _earlierRunCleared = true;
      try {
        _folder.deleteSync(recursive: true);
      } on FileSystemException {
        // Missing, or held open by the system. The next run tries again.
      }
    }
    await _folder.create(recursive: true);
    final own = await _folder.createTemp();
    final file = File(p.join(own.path, 'image.png'));
    await file.writeAsBytes(png);
    return PendingAttachment(
      name: 'image.png',
      path: file.path,
      size: png.length,
    );
  }

  /// A file the system still holds open cannot go now. The next run clears it.
  static Future<void> _delete(Directory directory) async {
    try {
      await directory.delete(recursive: true);
    } on FileSystemException {
      return;
    }
  }
}
