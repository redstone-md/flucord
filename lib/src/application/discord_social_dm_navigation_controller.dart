import 'package:flutter/foundation.dart';

final class DiscordSocialDmNavigationController extends ChangeNotifier {
  String? _selectedUserId;

  String? get selectedUserId => _selectedUserId;
  bool get friendsSelected => _selectedUserId == null;

  void openConversation(String userId) {
    final normalized = userId.trim();
    if (normalized.isEmpty || normalized == _selectedUserId) return;
    _selectedUserId = normalized;
    notifyListeners();
  }

  void showFriends() {
    if (_selectedUserId == null) return;
    _selectedUserId = null;
    notifyListeners();
  }
}
