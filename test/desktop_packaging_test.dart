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

    expect(cmake, contains('set(APPLICATION_ID "dev.flucord.app")'));
    expect(runner, contains('gtk_window_set_title(window, "Flucord")'));
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
    for (final entitlements in [debugEntitlements, releaseEntitlements]) {
      expect(entitlements, contains('com.apple.security.network.client'));
      expect(entitlements, contains('com.apple.security.device.audio-input'));
    }
  });
}
