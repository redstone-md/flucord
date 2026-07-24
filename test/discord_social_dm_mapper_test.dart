import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/data/discord_social_dm_mapper.dart';
import 'package:flucord/src/domain/discord_relationship.dart';
import 'package:flucord/src/domain/discord_social_dm.dart';

void main() {
  test('maps native conversation summaries and message handles', () {
    final conversations = DiscordSocialDmMapper.conversations([
      {
        'user_id': '101',
        'last_message_id': '9001',
        'display_name': 'Ada',
        'username': 'ada',
        'status': 'online',
        'is_provisional': false,
      },
    ]);
    final messages = DiscordSocialDmMapper.messages([
      {
        'id': '9001',
        'conversation_user_id': '101',
        'author_id': '101',
        'recipient_id': '202',
        'author_display_name': 'Ada',
        'content': 'hello',
        'sent_timestamp': 1771718400000,
        'edited_timestamp': 1771718460000,
        'authored_by_current_user': false,
      },
    ]);

    expect(conversations.single.user.displayName, 'Ada');
    expect(conversations.single.user.status, DiscordPresenceStatus.online);
    expect(conversations.single.lastMessageId, '9001');
    expect(messages.single.content, 'hello');
    expect(messages.single.sentAt, DateTime.utc(2026, 2, 22));
    expect(messages.single.editedAt, DateTime.utc(2026, 2, 22, 0, 1));
  });

  test('maps created, updated, and deleted native events', () {
    final payload = {
      'type': 'updated',
      'message': {
        'id': '44',
        'conversation_user_id': '11',
        'author_id': '11',
        'recipient_id': '22',
        'author_display_name': 'Ada',
        'content': 'edited',
        'sent_timestamp': 1771718400000,
        'edited_timestamp': 1771718460000,
        'authored_by_current_user': false,
      },
    };

    final changed = DiscordSocialDmMapper.event(
      'socialMessageChanged',
      payload,
    );
    final deleted = DiscordSocialDmMapper.event('socialMessageDeleted', {
      'message_id': '44',
      'channel_id': '55',
    });

    expect(changed.type, DiscordSocialDmEventType.updated);
    expect(changed.message?.content, 'edited');
    expect(deleted.type, DiscordSocialDmEventType.deleted);
    expect(deleted.messageId, '44');
  });

  test('rejects incomplete native payloads', () {
    expect(
      () => DiscordSocialDmMapper.messages([
        {'id': '44'},
      ]),
      throwsFormatException,
    );
    expect(
      () => DiscordSocialDmMapper.event('socialMessageChanged', {
        'type': 'unknown',
      }),
      throwsFormatException,
    );
  });
}
