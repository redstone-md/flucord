// Writes the WinSparkle appcast for one Windows release.
//
// The release workflow runs it after signing the setup:
//
//   dart run tool/write_appcast.dart --repository redstone-md/flucord
//     --tag v0.0.29 --version 0.0.29+29
//     --installer build/distribution/flucord-windows-x64-setup-v0.0.29.exe
//     --signature <base64 DSA signature> --output build/distribution/appcast.xml
import 'dart:io';

import 'package:xml/xml.dart';

const _sparkleNamespace = 'http://www.andymatuschak.org/xml-namespaces/sparkle';

/// One Windows release, as the appcast offers it to installed builds.
final class AppcastRelease {
  AppcastRelease({
    required this.repository,
    required this.tag,
    required this.version,
    required this.installerName,
    required this.installerLength,
    required this.dsaSignature,
    required this.publishedAt,
  }) {
    if (tag != 'v$shortVersion') {
      throw ArgumentError.value(tag, 'tag', 'does not name version $version');
    }
  }

  /// GitHub `owner/name`; the setup is a release asset there.
  final String repository;
  final String tag;

  /// The full pubspec version, build number included. Flutter stamps it as
  /// the exe's FileVersion, which WinSparkle compares with this one.
  final String version;
  final String installerName;
  final int installerLength;

  /// Base64 DSA signature of the setup's SHA-1, as WinSparkle checks it.
  final String dsaSignature;
  final DateTime publishedAt;

  String get shortVersion => version.split('+').first;
}

/// The appcast XML with [release] as its only item.
String appcastXml(AppcastRelease release) {
  final releases = 'https://github.com/${release.repository}/releases';
  final builder = XmlBuilder()..declaration(encoding: 'utf-8');
  builder.element(
    'rss',
    namespaces: {_sparkleNamespace: 'sparkle'},
    attributes: {'version': '2.0'},
    nest: () {
      builder.element(
        'channel',
        nest: () {
          builder.element('title', nest: 'Flucord');
          builder.element('link', nest: releases);
          builder.element(
            'item',
            nest: () {
              builder.element('title', nest: 'Flucord ${release.tag}');
              builder.element(
                'pubDate',
                nest: HttpDate.format(release.publishedAt),
              );
              builder.element(
                'releaseNotesLink',
                namespace: _sparkleNamespace,
                nest: '$releases/tag/${release.tag}',
              );
              builder.element(
                'enclosure',
                nest: () {
                  builder
                    ..attribute(
                      'url',
                      '$releases/download/${release.tag}/'
                          '${release.installerName}',
                    )
                    ..attribute('length', '${release.installerLength}')
                    ..attribute('type', 'application/octet-stream')
                    ..attribute(
                      'version',
                      release.version,
                      namespace: _sparkleNamespace,
                    )
                    ..attribute(
                      'shortVersionString',
                      release.shortVersion,
                      namespace: _sparkleNamespace,
                    )
                    ..attribute(
                      'os',
                      'windows-x64',
                      namespace: _sparkleNamespace,
                    )
                    ..attribute(
                      'dsaSignature',
                      release.dsaSignature,
                      namespace: _sparkleNamespace,
                    );
                },
              );
            },
          );
        },
      );
    },
  );
  return builder.buildDocument().toXmlString(pretty: true);
}

void main(List<String> arguments) {
  final options = _readOptions(arguments);
  final installer = File(options('installer'));
  final release = AppcastRelease(
    repository: options('repository'),
    tag: options('tag'),
    version: options('version'),
    installerName: installer.uri.pathSegments.last,
    installerLength: installer.lengthSync(),
    dsaSignature: options('signature'),
    publishedAt: DateTime.now().toUtc(),
  );
  File(options('output')).writeAsStringSync('${appcastXml(release)}\n');
}

/// Reads `--name value` pairs; a missing or empty option is an error.
String Function(String) _readOptions(List<String> arguments) {
  final values = <String, String>{};
  for (var index = 0; index + 1 < arguments.length; index += 2) {
    final name = arguments[index];
    if (!name.startsWith('--')) {
      throw ArgumentError.value(name, 'arguments', 'expected --name value');
    }
    values[name.substring(2)] = arguments[index + 1];
  }
  return (name) {
    final value = values[name];
    if (value == null || value.isEmpty) {
      throw ArgumentError('Missing --$name.');
    }
    return value;
  };
}
