import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

import '../tool/write_appcast.dart';

const _sparkle = 'http://www.andymatuschak.org/xml-namespaces/sparkle';

AppcastRelease _release({
  String tag = 'v0.0.29',
  String version = '0.0.29+29',
}) => AppcastRelease(
  repository: 'redstone-md/flucord',
  tag: tag,
  version: version,
  installerName: 'flucord-windows-x64-setup-$tag.exe',
  installerLength: 48213760,
  dsaSignature: 'MC0CFQCi2s+v/0hW==',
  publishedAt: DateTime.utc(2026, 11, 6, 22, 38, 17),
);

void main() {
  test('the appcast offers the signed Windows setup of the release', () {
    final document = XmlDocument.parse(appcastXml(_release()));

    final items = document.findAllElements('item').toList();
    expect(items, hasLength(1));
    final item = items.single;
    expect(item.getElement('title')!.innerText, 'Flucord v0.0.29');
    expect(
      item.getElement('pubDate')!.innerText,
      'Fri, 06 Nov 2026 22:38:17 GMT',
    );
    expect(
      item.getElement('releaseNotesLink', namespace: _sparkle)!.innerText,
      'https://github.com/redstone-md/flucord/releases/tag/v0.0.29',
    );

    final enclosure = item.getElement('enclosure')!;
    expect(
      enclosure.getAttribute('url'),
      'https://github.com/redstone-md/flucord/releases/download/v0.0.29/'
      'flucord-windows-x64-setup-v0.0.29.exe',
    );
    expect(enclosure.getAttribute('length'), '48213760');
    expect(enclosure.getAttribute('type'), 'application/octet-stream');
    // WinSparkle compares sparkle:version with the exe's FileVersion, which
    // Flutter stamps as the full pubspec version.
    expect(enclosure.getAttribute('version', namespace: _sparkle), '0.0.29+29');
    expect(
      enclosure.getAttribute('shortVersionString', namespace: _sparkle),
      '0.0.29',
    );
    expect(enclosure.getAttribute('os', namespace: _sparkle), 'windows-x64');
    expect(
      enclosure.getAttribute('dsaSignature', namespace: _sparkle),
      'MC0CFQCi2s+v/0hW==',
    );
  });

  test('a tag that does not name the version is refused', () {
    expect(
      () => appcastXml(_release(tag: 'v0.0.30')),
      throwsA(isA<ArgumentError>()),
    );
  });
}
