import 'dart:io';

import '../domain/trusted_domains.dart';
import 'json_settings_file.dart';

/// The trusted link hosts, kept in a file beside the keybinds.
///
/// They belong to whoever is sitting at the machine rather than to the
/// account signed in on it, and Discord's settings blob has no group for
/// them: its own client keeps them in local storage too.
final class FileTrustedDomainsRepository implements TrustedDomainsRepository {
  FileTrustedDomainsRepository({Future<Directory> Function()? directory})
    : _file = JsonSettingsFile(fileName, directory: directory);

  static const fileName = 'trusted_domains.json';

  final JsonSettingsFile _file;

  @override
  Future<TrustedDomains> load() async =>
      TrustedDomains.fromJson(await _file.read());

  @override
  Future<void> save(TrustedDomains domains) => _file.write(domains.toJson());
}
