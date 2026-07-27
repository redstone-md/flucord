part of 'guild_permissions_test.dart';

void _threadCases() {
  group('thread adjuster', () {
    final parent = DiscordPermissions.combine([
      DiscordPermissions.viewChannel,
      DiscordPermissions.readMessageHistory,
      DiscordPermissions.sendMessagesInThreads,
    ]);

    test('a media thread keeps exactly two bits', () {
      final result = GuildPermissions.inThread(
        DiscordPermissions.all,
        thread: const ThreadContext(isMedia: true),
      );

      expect(
        result,
        DiscordPermissions.combine([
          DiscordPermissions.readMessageHistory,
          DiscordPermissions.viewChannel,
        ]),
      );
    });

    test('an unjoined private thread resolves to nothing', () {
      final result = GuildPermissions.inThread(
        parent,
        thread: const ThreadContext(isPrivate: true),
      );

      expect(result, BigInt.zero);
    });

    test(
      'joining, guest standing, or MANAGE_THREADS opens a private thread',
      () {
        expect(
          GuildPermissions.inThread(
            parent,
            thread: const ThreadContext(isPrivate: true, hasJoined: true),
          ),
          isNot(BigInt.zero),
        );
        expect(
          GuildPermissions.inThread(
            parent,
            thread: const ThreadContext(isPrivate: true),
            isGuest: true,
          ),
          isNot(BigInt.zero),
        );
        expect(
          GuildPermissions.inThread(
            DiscordPermissions.add(parent, DiscordPermissions.manageThreads),
            thread: const ThreadContext(isPrivate: true),
          ),
          isNot(BigInt.zero),
        );
      },
    );

    test('SEND_MESSAGES is derived from the thread bit, never inherited', () {
      final withoutThreadBit = DiscordPermissions.combine([
        DiscordPermissions.viewChannel,
        DiscordPermissions.sendMessages,
      ]);

      expect(
        DiscordPermissions.hasAll(
          GuildPermissions.inThread(
            withoutThreadBit,
            thread: const ThreadContext(),
          ),
          DiscordPermissions.sendMessages,
        ),
        isFalse,
      );
      expect(
        DiscordPermissions.hasAll(
          GuildPermissions.inThread(parent, thread: const ThreadContext()),
          DiscordPermissions.sendMessages,
        ),
        isTrue,
      );
    });

    test('a locked thread only stays writable for a thread manager', () {
      expect(
        DiscordPermissions.hasAll(
          GuildPermissions.inThread(
            parent,
            thread: const ThreadContext(isLocked: true),
          ),
          DiscordPermissions.sendMessages,
        ),
        isFalse,
      );
      expect(
        DiscordPermissions.hasAll(
          GuildPermissions.inThread(
            DiscordPermissions.add(parent, DiscordPermissions.manageThreads),
            thread: const ThreadContext(isLocked: true),
          ),
          DiscordPermissions.sendMessages,
        ),
        isTrue,
      );
    });
  });
}
