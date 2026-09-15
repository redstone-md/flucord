import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'profile_image_picker.dart';

/// A file the user chose for an expression, already turned into the `data:`
/// URI the upload routes take.
final class ExpressionFileSelection {
  const ExpressionFileSelection({
    required this.name,
    required this.dataUri,
    required this.byteCount,
  });

  final String name;
  final String dataUri;
  final int byteCount;
}

/// Why a chosen file cannot become one kind of expression.
enum ExpressionFileRejection {
  /// Not one of the formats that kind of expression accepts.
  unsupportedFormat,

  /// Larger than that kind of expression accepts.
  tooLarge,

  /// The file had no bytes to read.
  empty,
}

/// One of the three kinds a guild can own.
enum ExpressionKind { emoji, sticker, sound }

/// Turns chosen bytes into the form the upload routes take, checking each
/// kind's own limits before anything is sent.
///
/// The limits and formats are Discord's own, stated per kind because they
/// differ: an emoji is a small still or looping image, a sticker is a bigger
/// one in fewer formats, and a sound is audio. Reading the media type from
/// the bytes rather than the file name keeps a renamed file from being
/// declared wrong, the same way the profile image codec works.
final class ExpressionFileRejected implements Exception {
  const ExpressionFileRejected(this.reason, this.kind);

  final ExpressionFileRejection reason;
  final ExpressionKind kind;

  /// The sentence the settings page shows.
  String get message => switch (reason) {
    ExpressionFileRejection.unsupportedFormat => switch (kind) {
      ExpressionKind.emoji => 'Emoji images must be PNG, JPEG, GIF or WebP.',
      ExpressionKind.sticker =>
        'Stickers must be PNG, APNG, GIF or a Lottie JSON file.',
      ExpressionKind.sound => 'Sounds must be an MP3 or OGG file.',
    },
    ExpressionFileRejection.tooLarge => switch (kind) {
      ExpressionKind.emoji => 'Emoji images must be under 256 KB.',
      ExpressionKind.sticker =>
        'Stickers must be under 512 KB, and 5 seconds at most.',
      ExpressionKind.sound => 'Sounds must be under 512 KB.',
    },
    ExpressionFileRejection.empty => 'That file is empty.',
  };

  @override
  String toString() => message;
}

abstract final class ExpressionFileCodec {
  /// Discord's limit for one emoji image.
  static const emojiMaxBytes = 256 * 1024;

  /// Discord's limit for one sticker file.
  static const stickerMaxBytes = 512 * 1024;

  /// Discord's limit for one soundboard sound.
  static const soundMaxBytes = 512 * 1024;

  /// Encodes [bytes] for [kind], throwing [ExpressionFileRejected] for
  /// anything the server would refuse up front.
  static ExpressionFileSelection encode(
    ExpressionKind kind,
    String name,
    Uint8List bytes,
  ) {
    if (bytes.isEmpty) {
      throw const ExpressionFileRejected(
        ExpressionFileRejection.empty,
        ExpressionKind.emoji,
      );
    }
    final mediaType = detectMediaType(kind, bytes);
    if (mediaType == null) {
      throw ExpressionFileRejected(
        ExpressionFileRejection.unsupportedFormat,
        kind,
      );
    }
    final limit = switch (kind) {
      ExpressionKind.emoji => emojiMaxBytes,
      ExpressionKind.sticker => stickerMaxBytes,
      ExpressionKind.sound => soundMaxBytes,
    };
    if (bytes.length > limit) {
      throw ExpressionFileRejected(ExpressionFileRejection.tooLarge, kind);
    }
    return ExpressionFileSelection(
      name: name,
      dataUri: 'data:$mediaType;base64,${base64Encode(bytes)}',
      byteCount: bytes.length,
    );
  }

  /// The media type [bytes] carry for [kind], or null when it is not one
  /// that kind accepts.
  ///
  /// The image half is the same sniff the avatar and banner edits use, read
  /// from the bytes rather than the file name; each kind then keeps the
  /// formats Discord takes for it, which is where a sticker differs from an
  /// emoji and a sound differs from both.
  static String? detectMediaType(ExpressionKind kind, Uint8List bytes) {
    if (kind == ExpressionKind.sound) return _soundType(bytes);
    final image = ProfileImageCodec.detectMediaType(bytes);
    if (image == null) {
      // A Lottie sticker is a JSON file, which is what the lottie format is.
      return kind == ExpressionKind.sticker && _isJson(bytes)
          ? 'application/json'
          : null;
    }
    // A sticker is a still or looping picture only: Discord takes no JPEG
    // or WebP sticker.
    if (kind == ExpressionKind.sticker &&
        image != 'image/png' &&
        image != 'image/gif') {
      return null;
    }
    return image;
  }

  /// MP3 files begin with an ID3 tag or a frame sync; OGG files with OggS.
  /// Both are read from the bytes so a renamed file still uploads.
  static String? _soundType(Uint8List bytes) {
    if (_startsWith(bytes, const [0x49, 0x44, 0x33])) return 'audio/mpeg';
    if (_startsWith(bytes, const [0x4f, 0x67, 0x67, 0x53])) {
      return 'audio/ogg';
    }
    if (bytes.length >= 2 && bytes[0] == 0xff && (bytes[1] & 0xe0) == 0xe0) {
      return 'audio/mpeg';
    }
    return null;
  }

  static bool _isJson(Uint8List bytes) {
    for (final byte in bytes) {
      if (byte == 0x09 || byte == 0x0a || byte == 0x0d || byte == 0x20) {
        continue;
      }
      return byte == 0x7b || byte == 0x5b;
    }
    return false;
  }

  static bool _startsWith(Uint8List bytes, List<int> prefix) {
    if (bytes.length < prefix.length) return false;
    for (var index = 0; index < prefix.length; index++) {
      if (bytes[index] != prefix[index]) return false;
    }
    return true;
  }
}

/// Chooses one file of any kind, for the settings page's upload buttons.
abstract interface class ExpressionFilePicker {
  Future<ExpressionFileSelection?> pick(ExpressionKind kind);
}

final class NativeExpressionFilePicker implements ExpressionFilePicker {
  const NativeExpressionFilePicker();

  @override
  Future<ExpressionFileSelection?> pick(ExpressionKind kind) async {
    final result = await FilePicker.pickFiles(
      dialogTitle: switch (kind) {
        ExpressionKind.emoji => 'Choose an emoji image',
        ExpressionKind.sticker => 'Choose a sticker file',
        ExpressionKind.sound => 'Choose a sound file',
      },
      type: switch (kind) {
        ExpressionKind.sound => FileType.audio,
        _ => FileType.image,
      },
      lockParentWindow: true,
    );
    final file = result?.files.singleOrNull;
    final path = file?.path;
    if (file == null || path == null) return null;
    return ExpressionFileCodec.encode(
      kind,
      file.name,
      await File(path).readAsBytes(),
    );
  }
}
