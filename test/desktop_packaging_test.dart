import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tracks all supported desktop runners in Flutter metadata', () {
    final metadata = File('.metadata').readAsStringSync();

    for (final platform in ['linux', 'macos', 'windows']) {
      expect(metadata, contains('- platform: $platform'));
    }
  });

  test('uses the cross-platform native video bundle', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(pubspec, contains('media_kit_libs_video:'));
    expect(pubspec, isNot(contains('media_kit_libs_windows_video:')));
  });

  test('configures a branded Linux runner', () {
    final cmake = File('linux/CMakeLists.txt').readAsStringSync();
    final runner = File('linux/runner/my_application.cc').readAsStringSync();
    final desktop = File('linux/dev.flucord.app.desktop').readAsStringSync();

    expect(cmake, contains('set(APPLICATION_ID "dev.flucord.app")'));
    expect(cmake, contains('dev.flucord.app.desktop'));
    expect(runner, contains('gtk_window_set_title(window, "Flucord")'));
    expect(runner, contains('G_APPLICATION_HANDLES_COMMAND_LINE'));
    expect(runner, contains('"flucord/protocol"'));
    expect(runner, contains('g_queue_push_tail'));
    expect(runner, contains('"ready"'));
    expect(runner, contains('fl_method_channel_invoke_method'));
    expect(desktop, contains('MimeType=x-scheme-handler/flucord;'));
    expect(desktop, contains('Exec=flucord %u'));
  });

  test('grants the sandboxed macOS runner required capabilities', () {
    final appInfo = File(
      'macos/Runner/Configs/AppInfo.xcconfig',
    ).readAsStringSync();
    final infoPlist = File('macos/Runner/Info.plist').readAsStringSync();
    final debugEntitlements = File(
      'macos/Runner/DebugProfile.entitlements',
    ).readAsStringSync();
    final releaseEntitlements = File(
      'macos/Runner/Release.entitlements',
    ).readAsStringSync();

    expect(appInfo, contains('PRODUCT_BUNDLE_IDENTIFIER = dev.flucord.app'));
    expect(
      File('macos/Runner.xcodeproj/project.pbxproj').readAsStringSync(),
      isNot(contains('com.example')),
    );
    expect(infoPlist, contains('<key>NSMicrophoneUsageDescription</key>'));
    expect(infoPlist, contains('<key>NSScreenCaptureUsageDescription</key>'));
    expect(infoPlist, contains('<key>CFBundleURLTypes</key>'));
    expect(infoPlist, contains('<string>flucord</string>'));
    for (final entitlements in [debugEntitlements, releaseEntitlements]) {
      expect(entitlements, contains('com.apple.security.network.client'));
      expect(entitlements, contains('com.apple.security.device.audio-input'));
    }
  });

  test('selects a protocol integration for every desktop host', () {
    final mainSource = File('lib/main.dart').readAsStringSync();
    final windows = File(
      'lib/src/platform/windows_desktop_integration.dart',
    ).readAsStringSync();
    final macos = File(
      'lib/src/platform/macos_desktop_integration.dart',
    ).readAsStringSync();
    final linux = File(
      'lib/src/platform/linux_desktop_integration.dart',
    ).readAsStringSync();

    expect(mainSource, contains('WindowsDesktopIntegration()'));
    expect(mainSource, contains('MacosDesktopIntegration()'));
    expect(mainSource, contains('LinuxDesktopIntegration('));
    for (final integration in [windows, macos, linux]) {
      expect(integration, contains('DesktopMessageNotificationController'));
      expect(integration, contains('DesktopTrayCoordinator'));
    }
    expect(
      File('pubspec.yaml').readAsStringSync(),
      contains('app_icon_32.png'),
    );
  });
}
