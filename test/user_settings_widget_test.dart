import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/app.dart';
import 'package:flucord/src/application/user_settings_controller.dart';
import 'package:flucord/src/domain/user_settings.dart';
import 'package:flucord/src/domain/user_settings_repository.dart';
import 'package:flucord/src/presentation/widgets/user_settings_controls.dart';
import 'package:flucord/src/presentation/widgets/user_settings_dialog.dart';
import 'package:flucord/src/theme/flucord_theme.dart';

void main() {
  testWidgets('renders every category and applies an appearance edit', (
    tester,
  ) async {
    final repository = _Repository();
    final controller = await _pumpDialog(tester, repository);

    expect(
      find.byKey(const ValueKey('settings-section-appearance')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('setting-theme-light')));
    await tester.pumpAndSettle();

    expect(repository.applied.single.theme, UserSettingsTheme.light);
    expect(controller.settings, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('leaves a theme Flucord cannot draw unselectable', (
    tester,
  ) async {
    final repository = _Repository();
    await _pumpDialog(tester, repository);

    final darker = tester.widget<ChoiceChip>(
      find.byKey(const ValueKey('setting-theme-darker')),
    );
    final developerMode = tester.widget<Switch>(
      find.descendant(
        of: find.byKey(const ValueKey('setting-developer-mode')),
        matching: find.byType(Switch),
      ),
    );

    expect(darker.onSelected, isNull);
    expect(developerMode.onChanged, isNull);
    expect(
      find.text('Flucord has no surface for this setting yet.'),
      findsWidgets,
    );
    expect(repository.applied, isEmpty);
  });

  testWidgets('walks the rail and edits chat, notifications and privacy', (
    tester,
  ) async {
    final repository = _Repository();
    await _pumpDialog(tester, repository);

    await tester.tap(find.byKey(const ValueKey('settings-nav-chat')));
    await tester.pumpAndSettle();
    await _tapSetting(tester, 'setting-render-reactions');
    expect(repository.applied.last.renderReactions, isFalse);

    await tester.tap(find.byKey(const ValueKey('settings-nav-notifications')));
    await tester.pumpAndSettle();
    await _tapSetting(tester, 'setting-quiet-mode');
    expect(repository.applied.last.quietMode, isTrue);

    await tester.tap(find.byKey(const ValueKey('settings-nav-privacy')));
    await tester.pumpAndSettle();
    await _tapSetting(tester, 'setting-show-local-time');
    expect(repository.applied.last.showLocalTime, isTrue);

    await tester.tap(find.byKey(const ValueKey('settings-nav-language')));
    await tester.pumpAndSettle();
    expect(find.text('en-GB'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('every editable control writes the leaf it names', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _Repository();
    await _pumpDialog(tester, repository);

    await _tapChoice(tester, 'setting-hour-cycle-hour12');
    expect(
      repository.applied.last.timestampHourCycle,
      TimestampHourCycle.hour12,
    );

    await _openSection(tester, 'chat');
    await _tapSetting(tester, 'setting-render-embeds');
    expect(repository.applied.last.renderEmbeds, isFalse);
    await _tapSetting(tester, 'setting-inline-embed-media');
    expect(repository.applied.last.inlineEmbedMedia, isFalse);
    await _tapSetting(tester, 'setting-inline-attachment-media');
    expect(repository.applied.last.inlineAttachmentMedia, isFalse);

    await _openSection(tester, 'notifications');
    await _tapSetting(tester, 'setting-go-live-notifications');
    expect(repository.applied.last.notifyFriendsOnGoLive, isFalse);
    await _tapSetting(tester, 'setting-friend-online-notifications');
    expect(repository.applied.last.friendOnlineNotifications, isFalse);
    await _tapChoice(tester, 'setting-reaction-notifications-disabled');
    expect(
      repository.applied.last.reactionNotifications,
      ReactionNotifications.disabled,
    );

    await _openSection(tester, 'privacy');
    await _tapSetting(tester, 'setting-activity-party-friends');
    expect(repository.applied.last.allowActivityPartyFriends, isFalse);
    await _tapSetting(tester, 'setting-activity-party-voice');
    expect(repository.applied.last.allowActivityPartyVoiceChannel, isFalse);
    await _tapSetting(tester, 'setting-detect-platform-accounts');
    expect(repository.applied.last.detectPlatformAccounts, isTrue);
    await _tapSetting(tester, 'setting-hide-legacy-username');
    expect(repository.applied.last.hideLegacyUsername, isTrue);
    await _tapChoice(tester, 'setting-spam-filter-nonFriends');
    expect(
      repository.applied.last.spamFilter,
      DirectMessageSpamFilter.nonFriends,
    );

    await _openSection(tester, 'status');
    await _tapSetting(tester, 'setting-show-current-game');
    expect(repository.applied.last.showCurrentGame, isFalse);
    expect(find.text('rocket'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saves and clears the custom status', (tester) async {
    final repository = _Repository();
    await _pumpDialog(tester, repository);

    await tester.tap(find.byKey(const ValueKey('settings-nav-status')));
    await tester.pumpAndSettle();
    expect(find.text('dnd'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('setting-custom-status-field')),
      'reviewing',
    );
    await tester.tap(find.byKey(const ValueKey('setting-custom-status-save')));
    await tester.pumpAndSettle();
    expect(repository.applied.last.customStatusText, 'reviewing');

    await tester.tap(find.byKey(const ValueKey('setting-custom-status-clear')));
    await tester.pumpAndSettle();
    expect(repository.applied.last.clearCustomStatus, isTrue);
  });

  testWidgets('adopts a custom status changed on another device', (
    tester,
  ) async {
    final repository = _Repository();
    await _pumpDialog(tester, repository);
    await _openSection(tester, 'status');

    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('setting-custom-status-field')),
          )
          .controller!
          .text,
      'shipping',
    );

    repository.push(
      const UserSettings(
        status: StatusPreferences(customStatusText: 'on a call'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('setting-custom-status-field')),
          )
          .controller!
          .text,
      'on a call',
    );
  });

  testWidgets('says so when the session has no settings to show', (
    tester,
  ) async {
    final controller = UserSettingsController(() => null);
    addTearDown(controller.dispose);
    await _pumpApp(tester, controller);

    expect(
      find.byKey(const ValueKey('user-settings-unavailable')),
      findsOneWidget,
    );
    expect(find.byType(Switch), findsNothing);
  });

  testWidgets('offers a retry when the settings never arrive', (tester) async {
    final repository = _Repository(failLoad: true);
    final controller = UserSettingsController(() => repository);
    addTearDown(controller.dispose);
    await _pumpApp(tester, controller);

    expect(find.byKey(const ValueKey('user-settings-error')), findsOneWidget);
    repository.failLoad = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('settings-section-appearance')),
      findsOneWidget,
    );
  });

  testWidgets('reports a rejected write above the sections', (tester) async {
    final repository = _Repository(writeError: StateError('rejected'));
    await _pumpDialog(tester, repository);

    expect(
      find.byKey(const ValueKey('user-settings-write-error')),
      findsOneWidget,
    );
  });

  testWidgets('stacks the rail and controls in a compact window', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _Repository();
    await _pumpDialog(tester, repository);

    // The label and its control stop sharing a row well before the window
    // gets this narrow, which is what keeps the chips from overflowing.
    final row = tester.widget<SettingRow>(find.byType(SettingRow).first);
    expect(row.title, 'Theme');
    expect(
      find.byKey(const ValueKey('settings-nav-appearance')),
      findsOneWidget,
    );

    // Every category stays reachable: the rail became a scrolling strip.
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings-nav-privacy')),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('settings-nav-privacy')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('settings-section-privacy')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('reaches the dialog from the server rail', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1180, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(FlucordApp.demo());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('open-user-settings')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('user-settings-dialog')), findsOneWidget);
    // The demo transport has no account, and the surface says so instead of
    // offering controls that could never be saved.
    expect(
      find.byKey(const ValueKey('user-settings-unavailable')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens and closes as a dialog route', (tester) async {
    final controller = UserSettingsController(() => _Repository());
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  UserSettingsDialog.show(context, controller: controller),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('user-settings-dialog')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('user-settings-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('user-settings-dialog')), findsNothing);
  });
}

/// Scrolls the row into view before tapping it: the sections are longer than
/// the pane, which is the point of the pane being scrollable.
Future<void> _tapSetting(WidgetTester tester, String key) async {
  final row = find.byKey(ValueKey(key));
  await tester.ensureVisible(row);
  await tester.pumpAndSettle();
  // The control is aligned to the trailing edge of its slot, so the tap has
  // to land on the switch rather than on the middle of the slot.
  await tester.tap(find.descendant(of: row, matching: find.byType(Switch)));
  await tester.pumpAndSettle();
}

Future<void> _openSection(WidgetTester tester, String name) async {
  await tester.tap(find.byKey(ValueKey('settings-nav-$name')));
  await tester.pumpAndSettle();
}

Future<void> _tapChoice(WidgetTester tester, String key) async {
  final chip = find.byKey(ValueKey(key));
  await tester.ensureVisible(chip);
  await tester.pumpAndSettle();
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

Future<UserSettingsController> _pumpDialog(
  WidgetTester tester,
  _Repository repository,
) async {
  final controller = UserSettingsController(() => repository);
  addTearDown(controller.dispose);
  await _pumpApp(tester, controller);
  return controller;
}

Future<void> _pumpApp(
  WidgetTester tester,
  UserSettingsController controller,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(body: UserSettingsDialog(controller: controller)),
    ),
  );
  await tester.pumpAndSettle();
}

final class _Repository implements UserSettingsRepository {
  _Repository({this.failLoad = false, this.writeError});

  bool failLoad;
  final Object? writeError;
  final List<UserSettingsPatch> applied = [];
  final StreamController<UserSettings> _updates = StreamController.broadcast();
  UserSettings? _current;

  @override
  Stream<UserSettings> get updates => _updates.stream;

  @override
  UserSettings? get current => _current;

  @override
  bool get isLoaded => _current != null;

  @override
  Object? get lastWriteError => writeError;

  void push(UserSettings settings) {
    _current = settings;
    _updates.add(settings);
  }

  @override
  Future<UserSettings> load() async {
    if (failLoad) throw StateError('offline');
    return _current = _settings;
  }

  @override
  Future<void> apply(
    UserSettingsPatch patch, {
    UserSettingsSaveDelay delay = UserSettingsSaveDelay.immediate,
  }) async => applied.add(patch);

  @override
  Future<void> flush() async {}
}

const _settings = UserSettings(
  appearance: AppearancePreferences(
    theme: UserSettingsTheme.dark,
    density: UserInterfaceDensity.cozy,
  ),
  localization: LocalizationPreferences(
    locale: 'en-GB',
    timezoneName: 'Europe/London',
    timezoneOffsetMinutes: 60,
  ),
  status: StatusPreferences(
    status: 'dnd',
    customStatusText: 'shipping',
    customStatusEmojiName: 'rocket',
    statusExpiresAtMs: 1800000000000,
  ),
);
