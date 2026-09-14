part of 'discord_presence_service_test.dart';

void _editingCases() {
  group('editing', () {
    test('writes the chosen status through the settings blob', () async {
      final harness = _Harness();
      addTearDown(harness.dispose);

      await harness.service.setStatus(Presence.doNotDisturb);

      expect(
        harness.settings.patches.single.onlineStatus,
        Presence.doNotDisturb,
      );
    });

    test('refuses a status no account can store', () async {
      final harness = _Harness();
      addTearDown(harness.dispose);

      await harness.service.setStatus(Presence.streaming);
      await harness.service.setStatus(Presence.unknown);

      expect(harness.settings.patches, isEmpty);
    });

    test('writes a custom status with its emoji and expiry', () async {
      final harness = _Harness();
      addTearDown(harness.dispose);

      await harness.service.setCustomStatus(
        text: 'Heads down',
        emojiName: '🛠',
        expiry: CustomStatusDuration.oneHour,
      );

      final patch = harness.settings.patches.single;
      expect(patch.customStatusText, 'Heads down');
      expect(patch.customStatusEmojiName, '🛠');
      expect(
        patch.customStatusExpiresAtMs,
        harness.now.add(const Duration(hours: 1)).millisecondsSinceEpoch,
      );
    });

    test('an empty message and emoji clears the whole submessage', () async {
      final harness = _Harness();
      addTearDown(harness.dispose);

      await harness.service.setCustomStatus();

      expect(harness.settings.patches.single.clearCustomStatus, isTrue);
    });

    test('reports whether the account is editable yet', () async {
      final loaded = _Harness();
      addTearDown(loaded.dispose);
      expect(loaded.service.canEdit, isTrue);

      final pending = _Harness(settings: _FakeSettings(loaded: false));
      addTearDown(pending.dispose);
      expect(pending.service.canEdit, isFalse);
    });
  });
}
