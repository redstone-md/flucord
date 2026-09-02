import 'package:flucord/src/application/room_focus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a click puts a tile on the stage, a second takes it off', () {
    final focus = RoomFocus();
    var changes = 0;
    focus.addListener(() => changes++);

    focus.toggle('them');
    expect(focus.userId, 'them');
    focus.toggle('me');
    expect(focus.userId, 'me');
    focus.toggle('me');
    expect(focus.userId, isNull);
    expect(changes, 3);
  });

  test('the focus follows its participant out of the room', () {
    final focus = RoomFocus()..focus('them');

    focus.keepAmong(['me', 'them']);
    expect(focus.userId, 'them');

    focus.keepAmong(['me']);
    expect(focus.userId, isNull);
  });
}
