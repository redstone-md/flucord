import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/platform/desktop_message_notification_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> shown;
  late List<String> closed;

  setUp(() {
    shown = [];
    closed = [];
    const channel = MethodChannel('local_notifier');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'setup') {
            return true;
          }
          if (call.method == 'notify') {
            shown.add(call.arguments['identifier'] as String);
          }
          if (call.method == 'close') {
            closed.add(call.arguments['identifier'] as String);
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
  });

  Future<void> show(LocalDesktopNotificationGateway gateway, String id) =>
      gateway.show(
        DesktopNotificationRequest(
          identifier: id,
          title: 'Title',
          body: 'Body',
          onClick: () async {},
        ),
      );

  test('a live set past the cap retires its oldest member', () async {
    final gateway = LocalDesktopNotificationGateway();
    addTearDown(gateway.dispose);
    await gateway.initialize();

    final cap = LocalDesktopNotificationGateway.maxLive;
    for (var index = 0; index <= cap; index++) {
      await show(gateway, 'toast-$index');
    }

    expect(shown, hasLength(cap + 1));
    // The set never grew past the cap: the first toast was destroyed to make
    // room for the last one.
    expect(closed, ['toast-0']);
  });

  test(
    'a notification the OS never reports closed is retired on the cap',
    () async {
      final gateway = LocalDesktopNotificationGateway();
      addTearDown(gateway.dispose);
      await gateway.initialize();

      for (var index = 0; index < 30; index++) {
        await show(gateway, 'toast-$index');
      }

      // Nothing fired a close callback, so the cap did all the retiring.
      expect(closed, hasLength(30 - LocalDesktopNotificationGateway.maxLive));
      expect(closed.first, 'toast-0');
      expect(
        closed.last,
        'toast-${30 - LocalDesktopNotificationGateway.maxLive - 1}',
      );
    },
  );

  test('dismiss takes down the toast with that identifier only', () async {
    final gateway = LocalDesktopNotificationGateway();
    addTearDown(gateway.dispose);
    await gateway.initialize();
    await show(gateway, 'flucord-call-dm-mira');
    await show(gateway, 'flucord-message-1');

    await gateway.dismiss('flucord-call-dm-mira');
    // Gone already: a second dismiss reaches nothing native.
    await gateway.dismiss('flucord-call-dm-mira');

    expect(closed, ['flucord-call-dm-mira']);
  });
}
