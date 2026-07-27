import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/domain/guild_audit_log.dart';

void main() {
  group('AuditLogActionType', () {
    test('reads the wire value in either encoding', () {
      expect(AuditLogActionType.fromWire(22), AuditLogActionType.memberBanAdd);
      expect(AuditLogActionType.fromWire('30'), AuditLogActionType.roleCreate);
      expect(AuditLogActionType.fromWire(null), isNull);
      expect(AuditLogActionType.fromWire('nonsense'), isNull);
    });

    test('leaves the real gaps in the enum empty', () {
      // 63-71 and 120 are genuinely absent from Discord's frozen table, so an
      // entry carrying one is unknown rather than mislabelled.
      for (final missing in [63, 70, 71, 120, 122, 135, 148, 155, 205, 999]) {
        expect(
          AuditLogActionType.fromWire(missing),
          isNull,
          reason: 'action $missing should not resolve',
        );
      }
    });

    test('derives the action class client-side', () {
      expect(
        AuditLogActionType.channelCreate.actionClass,
        AuditLogActionClass.create,
      );
      expect(
        AuditLogActionType.channelDelete.actionClass,
        AuditLogActionClass.delete,
      );
      expect(
        AuditLogActionType.channelUpdate.actionClass,
        AuditLogActionClass.update,
      );
      expect(
        AuditLogActionType.messagePin.actionClass,
        AuditLogActionClass.create,
      );
      expect(
        AuditLogActionType.messageUnpin.actionClass,
        AuditLogActionClass.delete,
      );
      expect(
        AuditLogActionType.harmfulLinksBlockedMessage.actionClass,
        AuditLogActionClass.other,
      );
      expect(
        AuditLogActionType.memberPrune.actionClass,
        AuditLogActionClass.delete,
      );
    });

    test('derives the target type by the renderer ladder', () {
      const expectations = <AuditLogActionType, AuditLogTargetType>{
        AuditLogActionType.guildUpdate: AuditLogTargetType.guild,
        AuditLogActionType.channelDelete: AuditLogTargetType.channel,
        AuditLogActionType.messageBulkDelete: AuditLogTargetType.channel,
        AuditLogActionType.channelOverwriteDelete:
            AuditLogTargetType.channelOverwrite,
        AuditLogActionType.botAdd: AuditLogTargetType.user,
        AuditLogActionType.messageDelete: AuditLogTargetType.user,
        AuditLogActionType.messagePin: AuditLogTargetType.user,
        AuditLogActionType.messageUnpin: AuditLogTargetType.user,
        AuditLogActionType.roleDelete: AuditLogTargetType.role,
        AuditLogActionType.inviteDelete: AuditLogTargetType.invite,
        AuditLogActionType.webhookDelete: AuditLogTargetType.webhook,
        AuditLogActionType.emojiDelete: AuditLogTargetType.emoji,
        AuditLogActionType.integrationDelete: AuditLogTargetType.integration,
        AuditLogActionType.stageInstanceDelete:
            AuditLogTargetType.stageInstance,
        AuditLogActionType.stickerDelete: AuditLogTargetType.sticker,
        AuditLogActionType.guildScheduledEventDelete:
            AuditLogTargetType.scheduledEvent,
        AuditLogActionType.threadDelete: AuditLogTargetType.thread,
        AuditLogActionType.applicationCommandPermissionUpdate:
            AuditLogTargetType.applicationCommand,
        AuditLogActionType.soundboardSoundDelete: AuditLogTargetType.soundboard,
        AuditLogActionType.autoModerationRuleDelete:
            AuditLogTargetType.autoModerationRule,
        AuditLogActionType.autoModerationQuarantineUser:
            AuditLogTargetType.user,
        AuditLogActionType.creatorMonetizationTermsAccepted:
            AuditLogTargetType.guild,
        AuditLogActionType.onboardingPromptDelete:
            AuditLogTargetType.onboardingPrompt,
        AuditLogActionType.onboardingUpdate: AuditLogTargetType.guildOnboarding,
        AuditLogActionType.guildHomeRemoveItem: AuditLogTargetType.guildHome,
        AuditLogActionType.harmfulLinksBlockedMessage: AuditLogTargetType.guild,
        AuditLogActionType.homeSettingsUpdate: AuditLogTargetType.homeSettings,
        AuditLogActionType.voiceChannelStatusDelete:
            AuditLogTargetType.voiceChannelStatus,
        AuditLogActionType.guildScheduledEventExceptionDelete:
            AuditLogTargetType.scheduledEventException,
        AuditLogActionType.guildMemberVerificationUpdate:
            AuditLogTargetType.memberVerification,
        AuditLogActionType.guildProfileUpdate: AuditLogTargetType.guildProfile,
        AuditLogActionType.guildMigrateBypassSlowmodePermission:
            AuditLogTargetType.guild,
      };
      expectations.forEach((action, target) {
        expect(action.targetType, target, reason: action.name);
      });
    });
  });

  group('AuditLogQuery', () {
    test('omits the action key entirely for "all actions"', () {
      expect(const AuditLogQuery().toQueryParameters(), {
        'limit': 50,
        'before': null,
        'user_id': null,
        'action_type': null,
        'target_id': null,
      });
    });

    test('carries the filters it was given', () {
      const query = AuditLogQuery(
        before: '111111111111111111',
        userId: '123456789012345678',
        action: AuditLogActionType.memberBanAdd,
        targetId: '222222222222222222',
      );
      expect(query.toQueryParameters(), {
        'limit': 50,
        'before': '111111111111111111',
        'user_id': '123456789012345678',
        'action_type': 22,
        'target_id': '222222222222222222',
      });
    });

    test('paging keeps the filter and replaces the cursor', () {
      const query = AuditLogQuery(action: AuditLogActionType.roleUpdate);
      final next = query.pageAfter('333333333333333333');
      expect(next.action, AuditLogActionType.roleUpdate);
      expect(next.before, '333333333333333333');
    });
  });

  group('AuditLogPage', () {
    test('a short page is the end of the log', () {
      final page = AuditLogPage(entries: [_entry('1', minutes: 0)]);
      expect(page.hasOlderEntries, isFalse);
      expect(page.oldestEntryId, '1');
      expect(const AuditLogPage(entries: []).oldestEntryId, isNull);
    });

    test('a full page means there may be more', () {
      final page = AuditLogPage(
        entries: [for (var index = 0; index < 50; index++) _entry('$index')],
      );
      expect(page.hasOlderEntries, isTrue);
    });
  });

  group('AuditLogMerge', () {
    test('folds consecutive identical actions inside the window', () {
      final records = AuditLogMerge.apply([
        _entry('3', minutes: 20),
        _entry('2', minutes: 10),
        _entry('1', minutes: 0),
      ]);
      expect(records, hasLength(1));
      expect(records.single.count, 3);
      expect(records.single.isMerged, isTrue);
      expect(records.single.timestampStart.minute, 0);
      expect(records.single.timestampEnd.minute, 20);
      expect(records.single.changes, hasLength(3));
    });

    test('a gap of thirty minutes starts a new record', () {
      final records = AuditLogMerge.apply([
        _entry('2', minutes: 30),
        _entry('1', minutes: 0),
      ]);
      expect(records, hasLength(2));
      expect(records.first.head.id, '2');
    });

    test('a different actor is never folded in', () {
      final records = AuditLogMerge.apply([
        _entry('2', minutes: 1, userId: 'other'),
        _entry('1', minutes: 0),
      ]);
      expect(records, hasLength(2));
    });

    test('a different target is never folded in', () {
      final records = AuditLogMerge.apply([
        _entry('2', minutes: 1, targetId: 'elsewhere'),
        _entry('1', minutes: 0),
      ]);
      expect(records, hasLength(2));
    });

    test('a different action is never folded in', () {
      final records = AuditLogMerge.apply([
        _entry('2', minutes: 1, action: AuditLogActionType.channelDelete),
        _entry('1', minutes: 0),
      ]);
      expect(records, hasLength(2));
    });

    test('message and member actions are excluded from folding', () {
      for (final action in [
        AuditLogActionType.messageDelete,
        AuditLogActionType.messageBulkDelete,
        AuditLogActionType.messagePin,
        AuditLogActionType.messageUnpin,
        AuditLogActionType.memberMove,
        AuditLogActionType.memberDisconnect,
        AuditLogActionType.botAdd,
        AuditLogActionType.applicationCommandPermissionUpdate,
        AuditLogActionType.memberPrune,
      ]) {
        final records = AuditLogMerge.apply([
          _entry('2', minutes: 1, action: action),
          _entry('1', minutes: 0, action: action),
        ]);
        expect(records, hasLength(2), reason: action.name);
      }
    });

    test('invites are excluded because the code is the identity', () {
      final records = AuditLogMerge.apply([
        _entry('2', minutes: 1, action: AuditLogActionType.inviteCreate),
        _entry('1', minutes: 0, action: AuditLogActionType.inviteCreate),
      ]);
      expect(records, hasLength(2));
    });

    test('a run stops at fifty entries', () {
      final entries = [
        for (var index = 60; index > 0; index--)
          _entry('$index', minutes: index % 20),
      ];
      final records = AuditLogMerge.apply(entries);
      expect(records.first.count + records.last.count, 60);
      expect(records.every((record) => record.count <= 50), isTrue);
    });

    test('options must be deeply equal to fold', () {
      final same = AuditLogMerge.apply([
        _entry(
          '2',
          minutes: 1,
          options: {
            'channel_id': '1',
            'nested': {'a': 1},
            'list': [1, 2],
          },
        ),
        _entry(
          '1',
          minutes: 0,
          options: {
            'channel_id': '1',
            'nested': {'a': 1},
            'list': [1, 2],
          },
        ),
      ]);
      expect(same, hasLength(1));

      final differentNested = AuditLogMerge.apply([
        _entry(
          '2',
          minutes: 1,
          options: {
            'nested': {'a': 2},
          },
        ),
        _entry(
          '1',
          minutes: 0,
          options: {
            'nested': {'a': 1},
          },
        ),
      ]);
      expect(differentNested, hasLength(2));

      final differentListLength = AuditLogMerge.apply([
        _entry(
          '2',
          minutes: 1,
          options: {
            'list': [1],
          },
        ),
        _entry(
          '1',
          minutes: 0,
          options: {
            'list': [1, 2],
          },
        ),
      ]);
      expect(differentListLength, hasLength(2));

      final differentListItem = AuditLogMerge.apply([
        _entry(
          '2',
          minutes: 1,
          options: {
            'list': [9],
          },
        ),
        _entry(
          '1',
          minutes: 0,
          options: {
            'list': [1],
          },
        ),
      ]);
      expect(differentListItem, hasLength(2));

      final differentKeys = AuditLogMerge.apply([
        _entry('2', minutes: 1, options: {'other': '1'}),
        _entry('1', minutes: 0, options: {'channel_id': '1'}),
      ]);
      expect(differentKeys, hasLength(2));

      final differentSize = AuditLogMerge.apply([
        _entry('2', minutes: 1, options: {'channel_id': '1', 'extra': 2}),
        _entry('1', minutes: 0, options: {'channel_id': '1'}),
      ]);
      expect(differentSize, hasLength(2));
    });

    test('an empty page merges to nothing', () {
      expect(AuditLogMerge.apply(const []), isEmpty);
    });
  });
}

AuditLogEntry _entry(
  String id, {
  int minutes = 0,
  String? userId = '123456789012345678',
  String? targetId = '222222222222222222',
  AuditLogActionType action = AuditLogActionType.channelUpdate,
  Map<String, Object?> options = const {},
}) => AuditLogEntry(
  id: id,
  action: action,
  timestamp: DateTime.utc(2026, 7, 27, 12, minutes),
  targetId: targetId,
  userId: userId,
  options: options,
  changes: const [AuditLogChange(key: 'name', oldValue: 'a', newValue: 'b')],
);
