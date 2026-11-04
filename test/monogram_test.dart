import 'package:flucord/src/domain/monogram.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a monogram is the first letter of the first two words', () {
    expect(monogramOf('Dota 2'), 'D2');
    expect(monogramOf('  tabletop   simulator  game '), 'TS');
    // A whole character, not half of a surrogate pair.
    expect(monogramOf('🎮 night'), '🎮N');
    expect(monogramOf('   '), '?');
  });
}
