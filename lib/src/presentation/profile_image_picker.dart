import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// An image the user chose for their avatar or banner.
final class ProfileImageSelection {
  const ProfileImageSelection({
    required this.name,
    required this.dataUri,
    required this.byteCount,
  });

  final String name;

  /// `data:image/png;base64,…`, which is the only avatar form the profile
  /// route accepts.
  final String dataUri;
  final int byteCount;
}

/// Why a chosen file cannot become a profile image.
enum ProfileImageRejection {
  /// Not one of the formats Discord stores.
  unsupportedFormat,

  /// Larger than [ProfileImageCodec.maxBytes].
  tooLarge,

  /// The file had no bytes to read.
  empty,
}

final class ProfileImageRejected implements Exception {
  const ProfileImageRejected(this.reason);

  final ProfileImageRejection reason;

  String get message => switch (reason) {
    ProfileImageRejection.unsupportedFormat =>
      'Choose a PNG, JPEG, GIF or WebP image.',
    ProfileImageRejection.tooLarge => 'Images must be under 10 MB.',
    ProfileImageRejection.empty => 'That file is empty.',
  };

  @override
  String toString() => message;
}

/// Turns image bytes into the data URI Discord's profile routes take.
///
/// The media type is read from the bytes rather than from the file name: a
/// renamed `.png` that is really a JPEG would be declared wrong, and Discord
/// rejects the upload rather than sniffing it back. Keeping the check here also
/// means the failure is a message in the form instead of an opaque 400.
abstract final class ProfileImageCodec {
  /// Discord's own limit for an uploaded avatar or banner.
  static const maxBytes = 10 * 1024 * 1024;

  /// Encodes [bytes], throwing [ProfileImageRejected] for anything the account
  /// could not store.
  static ProfileImageSelection encode(String name, Uint8List bytes) {
    if (bytes.isEmpty) {
      throw const ProfileImageRejected(ProfileImageRejection.empty);
    }
    if (bytes.length > maxBytes) {
      throw const ProfileImageRejected(ProfileImageRejection.tooLarge);
    }
    final mediaType = detectMediaType(bytes);
    if (mediaType == null) {
      throw const ProfileImageRejected(ProfileImageRejection.unsupportedFormat);
    }
    return ProfileImageSelection(
      name: name,
      dataUri: 'data:$mediaType;base64,${base64Encode(bytes)}',
      byteCount: bytes.length,
    );
  }

  /// The media type [bytes] carry, or `null` when it is not one Discord takes.
  static String? detectMediaType(Uint8List bytes) {
    if (_startsWith(bytes, const [0x89, 0x50, 0x4e, 0x47])) return 'image/png';
    if (_startsWith(bytes, const [0xff, 0xd8, 0xff])) return 'image/jpeg';
    if (_startsWith(bytes, const [0x47, 0x49, 0x46, 0x38])) return 'image/gif';
    // RIFF....WEBP — the four size bytes in between are not part of the tag.
    if (_startsWith(bytes, const [0x52, 0x49, 0x46, 0x46]) &&
        bytes.length >= 12 &&
        _startsWith(bytes.sublist(8, 12), const [0x57, 0x45, 0x42, 0x50])) {
      return 'image/webp';
    }
    return null;
  }

  static bool _startsWith(Uint8List bytes, List<int> prefix) {
    if (bytes.length < prefix.length) return false;
    for (var index = 0; index < prefix.length; index++) {
      if (bytes[index] != prefix[index]) return false;
    }
    return true;
  }
}

abstract interface class ProfileImagePicker {
  /// The chosen image, or `null` when the user cancelled.
  Future<ProfileImageSelection?> pick();
}

final class NativeProfileImagePicker implements ProfileImagePicker {
  const NativeProfileImagePicker();

  @override
  Future<ProfileImageSelection?> pick() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Choose an image',
      type: FileType.image,
      lockParentWindow: true,
    );
    final file = result?.files.singleOrNull;
    final path = file?.path;
    if (file == null || path == null) return null;
    return ProfileImageCodec.encode(file.name, await File(path).readAsBytes());
  }
}
