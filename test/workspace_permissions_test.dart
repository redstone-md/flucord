import 'package:flucord/src/domain/channel_capabilities.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/domain/discord_permissions.dart';
import 'package:flucord/src/domain/guild_membership.dart';
import 'package:flucord/src/domain/permission_overwrite.dart';
import 'package:flucord/src/domain/workspace_permissions.dart';
import 'package:flutter_test/flutter_test.dart';

const _guild = 'guild-1';
const _me = 'member-1';

DiscordPermissionOverwrite _overwrite(
  String id, {
  BigInt? allow,
  BigInt? deny,
}) => DiscordPermissionOverwrite(
  id: id,
  allow: allow ?? BigInt.zero,
  deny: deny ?? BigInt.zero,
);

ConversationChannel _channel(
  String id, {
  ChannelKind kind = ChannelKind.text,
  Map<String, DiscordPermissionOverwrite> overwrites = const {},
  bool isThread = false,
  bool isLocked = false,
  String? parentId,
  String spaceId = _guild,
  String? recipientId,
}) => ConversationChannel(
  id: id,
  spaceId: spaceId,
  name: id,
  topic: '',
  kind: kind,
  isThread: isThread,
  isLocked: isLocked,
  parentId: parentId,
  recipientId: recipientId,
  permissionOverwrites: overwrites,
);

ChatWorkspace _workspace({
  required List<ConversationChannel> channels,
  BigInt? everyone,
  List<CommunityRole> roles = const [],
  // A member record with no roles is the normal shape for an ordinary member;
  // its absence is what means "we were never told".
  GuildMembership? membership = const GuildMembership(),
  Map<String, GuildMembership> otherMemberships = const {},
  String? ownerId,
  bool requiresMultiFactorAuth = false,
  bool withDirectMessages = false,
}) => ChatWorkspace(
  spaces: [
    CommunitySpace(
      id: _guild,
      name: 'The Forge',
      monogram: 'TF',
      colorValue: 0xff456b5a,
      ownerId: ownerId,
      requiresMultiFactorAuth: requiresMultiFactorAuth,
    ),
    if (withDirectMessages) const CommunitySpace.directMessages(),
  ],
  channels: channels,
  roles: [
    if (everyone != null)
      CommunityRole(
        id: _guild,
        spaceId: _guild,
        name: '@everyone',
        position: 0,
        permissions: everyone,
      ),
    ...roles,
  ],
  members: [
    Member(
      id: _me,
      displayName: 'Ada',
      initials: 'A',
      role: 'Member',
      presence: Presence.online,
      colorValue: 0xff456b5a,
      spaceIds: const {_guild},
      membershipsBySpace: {_guild: ?membership},
    ),
    for (final entry in otherMemberships.entries)
      Member(
        id: entry.key,
        displayName: entry.key,
        initials: 'X',
        role: 'Member',
        presence: Presence.online,
        colorValue: 0xff456b5a,
        spaceIds: const {_guild},
        membershipsBySpace: {_guild: entry.value},
      ),
  ],
  messages: const [],
  currentMemberId: _me,
);

void main() {
  group('missing permission data', () {
    test('a guild with no @everyone record stays fully permitted', () {
      // Three of Flucord's four transports never carried roles; denying on
      // absence would empty their sidebars.
      final workspace = _workspace(channels: [_channel('general')]);
      final permissions = WorkspacePermissions(workspace);

      expect(
        permissions.inChannel(workspace.channels.single),
        DiscordPermissions.all,
      );
      expect(permissions.visibleChannelsFor(_guild), hasLength(1));
      expect(
        permissions.capabilitiesIn(workspace.channels.single),
        ChannelCapabilities.unrestricted,
      );
    });

    test(
      'a role we hold no permission bits for is not a role that grants 0',
      () {
        final workspace = _workspace(
          channels: [_channel('general')],
          roles: const [
            CommunityRole(
              id: _guild,
              spaceId: _guild,
              name: '@everyone',
              position: 0,
            ),
          ],
        );

        expect(
          WorkspacePermissions(workspace).inChannel(workspace.channels.single),
          DiscordPermissions.all,
        );
      },
    );

    test('an @everyone role that really grants nothing hides the channel', () {
      final workspace = _workspace(
        channels: [_channel('general')],
        everyone: BigInt.zero,
      );

      expect(
        WorkspacePermissions(workspace).visibleChannelsFor(_guild),
        isEmpty,
      );
    });

    test('roles we know but a membership we do not is still unknown', () {
      // Without the member record the computation would answer for somebody
      // holding no roles, and hide every channel `@everyone` cannot see.
      final workspace = _workspace(
        channels: [
          _channel(
            'staff',
            overwrites: {
              _guild: _overwrite(_guild, deny: DiscordPermissions.viewChannel),
            },
          ),
        ],
        everyone: DiscordPermissions.viewChannel,
        membership: null,
      );

      expect(
        WorkspacePermissions(workspace).visibleChannelsFor(_guild),
        hasLength(1),
      );
    });
  });

  group('channel visibility', () {
    test('lists only the channels VIEW_CHANNEL survives', () {
      final workspace = _workspace(
        everyone: DiscordPermissions.viewChannel,
        channels: [
          _channel('general'),
          _channel(
            'staff',
            overwrites: {
              _guild: _overwrite(_guild, deny: DiscordPermissions.viewChannel),
            },
          ),
        ],
      );

      expect(
        WorkspacePermissions(
          workspace,
        ).visibleChannelsFor(_guild).map((channel) => channel.id),
        ['general'],
      );
    });

    test('a role overwrite can grant back what @everyone was denied', () {
      final workspace = _workspace(
        everyone: DiscordPermissions.viewChannel,
        roles: [
          CommunityRole(
            id: 'role-staff',
            spaceId: _guild,
            name: 'Staff',
            position: 1,
            permissions: BigInt.zero,
          ),
        ],
        membership: const GuildMembership(roleIds: ['role-staff']),
        channels: [
          _channel(
            'staff',
            overwrites: {
              _guild: _overwrite(_guild, deny: DiscordPermissions.viewChannel),
              'role-staff': _overwrite(
                'role-staff',
                allow: DiscordPermissions.viewChannel,
              ),
            },
          ),
        ],
      );

      expect(
        WorkspacePermissions(workspace).visibleChannelsFor(_guild),
        hasLength(1),
      );
    });

    test('a timed-out member loses the composer but keeps the channel', () {
      final now = DateTime.utc(2026, 7, 26, 12);
      final workspace = _workspace(
        everyone: DiscordPermissions.combine([
          DiscordPermissions.viewChannel,
          DiscordPermissions.sendMessages,
        ]),
        membership: GuildMembership(
          timeoutUntil: now.add(const Duration(minutes: 10)),
        ),
        channels: [_channel('general')],
      );

      final capabilities = WorkspacePermissions(
        workspace,
        now: now,
      ).capabilitiesIn(workspace.channels.single);

      expect(capabilities.viewChannel, isTrue);
      expect(capabilities.sendMessages, isFalse);
    });
  });

  group('channel scope', () {
    test("a voice channel's chat offers neither threads nor pins", () {
      final workspace = _workspace(
        everyone: DiscordPermissions.all,
        channels: [
          _channel('voice', kind: ChannelKind.voice),
          _channel('general'),
        ],
      );
      final permissions = WorkspacePermissions(workspace);

      final voice = permissions.capabilitiesIn(workspace.channels.first);
      final text = permissions.capabilitiesIn(workspace.channels.last);

      expect(voice.sendMessages, isTrue);
      expect(voice.pinMessages, isFalse);
      expect(voice.createPublicThreads, isFalse);
      expect(text.pinMessages, isTrue);
      expect(text.createPublicThreads, isTrue);
    });

    test('a thread cannot start another thread', () {
      final workspace = _workspace(
        everyone: DiscordPermissions.all,
        channels: [
          _channel('general'),
          _channel('thread', isThread: true, parentId: 'general'),
        ],
      );

      expect(
        WorkspacePermissions(
          workspace,
        ).capabilitiesIn(workspace.channels.last).createPublicThreads,
        isFalse,
      );
    });

    test('a direct message permits everything but moderating and threads', () {
      final workspace = _workspace(
        withDirectMessages: true,
        channels: [
          _channel(
            'dm-1',
            spaceId: CommunitySpace.directMessagesId,
            recipientId: 'other',
          ),
        ],
      );

      final capabilities = WorkspacePermissions(
        workspace,
      ).capabilitiesIn(workspace.channels.single);

      expect(capabilities.sendMessages, isTrue);
      expect(capabilities.pinMessages, isTrue);
      expect(capabilities.attachFiles, isTrue);
      expect(capabilities.manageMessages, isFalse);
      expect(capabilities.createPublicThreads, isFalse);
    });
  });

  group('threads', () {
    test('inherit the parent overwrites, never their own', () {
      final workspace = _workspace(
        everyone: DiscordPermissions.combine([
          DiscordPermissions.viewChannel,
          DiscordPermissions.sendMessages,
        ]),
        channels: [
          _channel(
            'general',
            overwrites: {
              _guild: _overwrite(
                _guild,
                allow: DiscordPermissions.sendMessagesInThreads,
              ),
            },
          ),
          _channel(
            'post',
            isThread: true,
            parentId: 'general',
            // A thread's own map is ignored, so this deny must not bite.
            overwrites: {
              _guild: _overwrite(_guild, deny: DiscordPermissions.viewChannel),
            },
          ),
        ],
      );
      final capabilities = WorkspacePermissions(
        workspace,
      ).capabilitiesIn(workspace.channels.last);

      expect(capabilities.viewChannel, isTrue);
      expect(capabilities.sendMessages, isTrue);
    });

    test('a locked thread closes the composer', () {
      final workspace = _workspace(
        everyone: DiscordPermissions.combine([
          DiscordPermissions.viewChannel,
          DiscordPermissions.sendMessages,
          DiscordPermissions.sendMessagesInThreads,
        ]),
        channels: [
          _channel('general'),
          _channel('post', isThread: true, isLocked: true, parentId: 'general'),
        ],
      );

      expect(
        WorkspacePermissions(
          workspace,
        ).capabilitiesIn(workspace.channels.last).sendMessages,
        isFalse,
      );
    });

    test('a thread whose parent record is gone falls back to the guild', () {
      final workspace = _workspace(
        everyone: DiscordPermissions.combine([
          DiscordPermissions.viewChannel,
          DiscordPermissions.sendMessagesInThreads,
        ]),
        channels: [_channel('orphan', isThread: true, parentId: 'missing')],
      );
      final capabilities = WorkspacePermissions(
        workspace,
      ).capabilitiesIn(workspace.channels.single);

      expect(capabilities.viewChannel, isTrue);
      expect(capabilities.sendMessages, isTrue);
    });
  });

  group('subject', () {
    test('answers for another member when asked to', () {
      final workspace = _workspace(
        everyone: DiscordPermissions.viewChannel,
        ownerId: 'owner-1',
        otherMemberships: const {'owner-1': GuildMembership()},
        channels: [
          _channel(
            'staff',
            overwrites: {
              _guild: _overwrite(_guild, deny: DiscordPermissions.viewChannel),
            },
          ),
        ],
      );

      expect(
        WorkspacePermissions(workspace).visibleChannelsFor(_guild),
        isEmpty,
      );
      expect(
        WorkspacePermissions(
          workspace,
          memberId: 'owner-1',
        ).visibleChannelsFor(_guild),
        hasLength(1),
      );
    });

    test('can() reads a single bit out of the computed value', () {
      final workspace = _workspace(
        everyone: DiscordPermissions.viewChannel,
        channels: [_channel('general')],
      );
      final permissions = WorkspacePermissions(workspace);

      expect(
        permissions.can(
          DiscordPermissions.viewChannel,
          workspace.channels.single,
        ),
        isTrue,
      );
      expect(
        permissions.can(
          DiscordPermissions.sendMessages,
          workspace.channels.single,
        ),
        isFalse,
      );
    });
  });

  group('capabilities', () {
    test('moderating is your own message always, anyone else with the bit', () {
      final message = ChatMessage(
        id: 'm1',
        channelId: 'general',
        authorId: 'someone-else',
        body: 'hi',
        sentAt: DateTime.utc(2026, 7, 26),
      );
      final mine = ChatMessage(
        id: 'm2',
        channelId: 'general',
        authorId: _me,
        body: 'hi',
        sentAt: DateTime.utc(2026, 7, 26),
      );

      expect(
        ChannelCapabilities.none.canModerate(mine, currentMemberId: _me),
        isTrue,
      );
      expect(
        ChannelCapabilities.none.canModerate(message, currentMemberId: _me),
        isFalse,
      );
      expect(
        ChannelCapabilities.unrestricted.canModerate(
          message,
          currentMemberId: _me,
        ),
        isTrue,
      );
    });

    test('has value semantics', () {
      final resolved = ChannelCapabilities.fromPermissions(
        DiscordPermissions.all,
      );

      expect(resolved, ChannelCapabilities.unrestricted);
      expect(resolved.hashCode, ChannelCapabilities.unrestricted.hashCode);
      expect(
        ChannelCapabilities.fromPermissions(BigInt.zero),
        ChannelCapabilities.none,
      );
      expect(ChannelCapabilities.none, isNot(ChannelCapabilities.unrestricted));
      expect(ChannelCapabilities.none, isNot(BigInt.zero));
    });
  });
}
