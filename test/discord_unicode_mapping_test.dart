import 'dart:convert';

import 'package:flucord/src/data/discord/discord_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps emoji-leading avatar monograms well-formed', () {
    final member = DiscordMapper().member({
      'id': 'emoji-member',
      'global_name': '💣 Jack',
    });

    expect(member.initials, '💣J');
    expect(utf8.encode(member.initials), isNotEmpty);
  });
}
