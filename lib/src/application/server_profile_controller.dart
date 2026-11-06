import 'package:flutter/foundation.dart';

import '../domain/guild_management.dart';
import '../domain/guild_management_repository.dart';
import '../domain/user_profile.dart';

/// Drives Edit server profile for one guild: reads what the account set
/// there, keeps a draft, and saves only what the draft changed.
///
/// Built per opening and disposed with the dialog, like the settings
/// window's controller.
final class ServerProfileController extends ChangeNotifier {
  ServerProfileController(this._repository, {required this.guildId});

  final GuildManagementRepository _repository;
  final String guildId;

  OwnServerProfile? _profile;
  Object? _loadError;
  bool _loading = false;
  bool _saving = false;
  String? _refusal;
  bool _disposed = false;

  ProfileValue<String> _nickname = const ProfileValue.untouched();
  ProfileValue<String> _bio = const ProfileValue.untouched();
  ProfileImage _avatar = const ProfileImage.untouched();
  ProfileImage _banner = const ProfileImage.untouched();

  /// What the server holds now, or null before the first read answers.
  OwnServerProfile? get profile => _profile;
  Object? get loadError => _loadError;
  bool get isLoading => _loading;
  bool get isSaving => _saving;

  /// Why the last save was refused, in words for the person.
  String? get refusal => _refusal;

  ProfileImage get pendingAvatar => _avatar;
  ProfileImage get pendingBanner => _banner;

  ServerProfileEdit get _edit => ServerProfileEdit(
    nickname: _nickname,
    avatar: _avatar,
    banner: _banner,
    bio: _bio,
  );

  bool get hasChanges => !_edit.isEmpty;

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    _loadError = null;
    _notify();
    try {
      _profile = await _repository.loadOwnServerProfile(guildId);
    } on Object catch (error) {
      _loadError = error;
    } finally {
      _loading = false;
      _notify();
    }
  }

  /// An empty nickname means "use my own name here".
  void editNickname(String text) {
    _nickname = _textChange(text, _profile?.nickname ?? '');
    _notify();
  }

  void editBio(String text) {
    _bio = _textChange(text, _profile?.bio ?? '');
    _notify();
  }

  /// A data URI replaces the avatar, null removes it.
  void editAvatar(String? dataUri) {
    _avatar = _imageChange(dataUri, _profile?.avatarHash);
    _notify();
  }

  void editBanner(String? dataUri) {
    _banner = _imageChange(dataUri, _profile?.bannerHash);
    _notify();
  }

  /// Saves the draft. Answers whether the server took it; a refusal leaves
  /// the draft as it was and sets [refusal].
  Future<bool> save() async {
    if (!hasChanges || _saving) return !hasChanges;
    _saving = true;
    _refusal = null;
    _notify();
    try {
      _profile = await _repository.saveOwnServerProfile(
        guildId: guildId,
        edit: _edit,
      );
      _nickname = const ProfileValue.untouched();
      _bio = const ProfileValue.untouched();
      _avatar = const ProfileImage.untouched();
      _banner = const ProfileImage.untouched();
      return true;
    } on ServerProfileRefusal catch (refusal) {
      _refusal = refusal.message;
      return false;
    } on Object {
      _refusal = 'Discord did not save your server profile. Try again.';
      return false;
    } finally {
      _saving = false;
      _notify();
    }
  }

  static ProfileValue<String> _textChange(String text, String stored) {
    if (text == stored) return const ProfileValue.untouched();
    return text.isEmpty ? const ProfileValue.cleared() : ProfileValue.set(text);
  }

  static ProfileImage _imageChange(String? dataUri, String? storedHash) {
    if (dataUri != null) return ProfileImage.replaced(dataUri);
    return storedHash == null
        ? const ProfileImage.untouched()
        : const ProfileImage.removed();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
