import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/user_notes.dart';
import '../domain/user_profile.dart';

/// Drives the full profile popover for somebody else.
///
/// One controller serves whichever user the popover is open on: the popover is
/// transient, the account and the notes are not, and keeping one controller
/// means opening the next profile costs no new subscriptions. The profile
/// plane is resolved through a provider for the same reason every account
/// surface is: a session swap must not fetch a profile with credentials that
/// just signed out.
final class MemberProfileController extends ChangeNotifier {
  MemberProfileController({
    required UserProfileRepository? Function() profileProvider,
    required UserNotesRepository? Function() notesProvider,
  }) : _profileProvider = profileProvider,
       _notesProvider = notesProvider;

  final UserProfileRepository? Function() _profileProvider;
  final UserNotesRepository? Function() _notesProvider;

  StreamSubscription<UserNotes>? _notesSubscription;
  bool _disposed = false;

  String? _openUserId;
  bool _isLoading = false;
  Object? _error;
  OtherUserProfile? _profile;
  bool _profileUnavailable = false;
  bool _noteSaving = false;
  bool _noteRefused = false;

  /// Which user the popover is open on, or null when it is closed.
  String? get openUserId => _openUserId;

  OtherUserProfile? get profile => _profile;

  bool get isLoading => _isLoading;
  Object? get error => _error;

  /// Whether the fetch came back empty rather than failing: Discord refuses
  /// the profile route for somebody this account has no relationship with,
  /// and the popover answers that by showing what the roster already knows.
  bool get profileUnavailable => _profileUnavailable;

  bool get noteSaving => _noteSaving;

  /// Whether the last note write was refused, which is an answer to say in
  /// words rather than a broken session.
  bool get noteRefused => _noteRefused;

  /// The note kept on the open user, or null when there is none.
  String? get note => _notesProvider()?.current.noteFor(_openUserId ?? '');

  /// Whether this transport can show a full profile or a note at all.
  bool get isSupported =>
      _profileProvider() != null || _notesProvider() != null;

  /// Opens the popover on [userId], fetching the profile and the notes.
  ///
  /// A profile that is already held for the same user is kept rather than
  /// refetched: the popover closes and reopens on the same person in a
  /// session's lifetime, and the profile route is rate-limited.
  Future<void> open(String userId) async {
    if (_disposed) return;
    _bindNotes();
    if (_openUserId == userId && (_profile != null || _isLoading)) return;
    _openUserId = userId;
    _profile = null;
    _profileUnavailable = false;
    _error = null;
    _noteRefused = false;
    _notify();
    await _fetchProfile(userId);
  }

  /// Re-reads the profile of the open user, after a failure.
  Future<void> retry() async {
    final userId = _openUserId;
    if (userId == null || _disposed) return;
    _error = null;
    _notify();
    await _fetchProfile(userId);
  }

  /// Saves the note on the open user, or removes it when [text] is empty.
  ///
  /// A refused write leaves the field as it is and raises [noteRefused], so
  /// the popover can say what happened instead of dropping the text.
  Future<bool> saveNote(String text) async {
    final userId = _openUserId;
    final notes = _notesProvider();
    if (userId == null || notes == null || _disposed || _noteSaving) {
      return false;
    }
    final trimmed = text.trim();
    _noteRefused = false;
    _noteSaving = true;
    _notify();
    try {
      final taken = await notes.setNote(
        userId: userId,
        note: trimmed.isEmpty ? null : trimmed,
      );
      _noteRefused = !taken;
      return taken;
    } finally {
      _noteSaving = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_notesSubscription?.cancel());
    _notesSubscription = null;
    super.dispose();
  }

  Future<void> _fetchProfile(String userId) async {
    final profile = _profileProvider();
    if (profile == null) {
      // A transport with no profile plane still shows the roster's answer,
      // which the popover draws from its own member row.
      _profileUnavailable = true;
      _notify();
      return;
    }
    _isLoading = true;
    _notify();
    try {
      final fetched = await profile.loadProfileOf(userId);
      if (_openUserId != userId) return;
      _profile = fetched;
      _profileUnavailable = fetched == null;
    } on Object catch (error) {
      if (_openUserId != userId) return;
      _error = error;
    } finally {
      _isLoading = false;
      if (!_disposed) _notify();
    }
  }

  /// Follows the live notes store rather than one captured at construction,
  /// so a note edited on another device repaints the open popover.
  void _bindNotes() {
    final notes = _notesProvider();
    if (identical(notes, _boundNotes)) return;
    unawaited(_notesSubscription?.cancel());
    _notesSubscription = notes?.updates.listen((_) => _notify());
    _boundNotes = notes;
  }

  UserNotesRepository? _boundNotes;

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}
