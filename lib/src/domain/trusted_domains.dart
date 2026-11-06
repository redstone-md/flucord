/// The hosts a link opens on without asking first.
///
/// Discord's own hosts are always trusted, and so is any host under one of
/// them. The rest are the ones the person trusted from the "Leaving" dialog.
/// They belong to the machine rather than the account, like Discord's own
/// list, which its client keeps in local storage.
final class TrustedDomains {
  const TrustedDomains([this.hosts = const {}]);

  static const none = TrustedDomains();

  /// Discord's own hosts. A link to one of them never asks.
  static const discordHosts = {
    'discord.com',
    'discordapp.com',
    'discord.gg',
    'discord.gift',
    'discord.new',
    'discord.co',
    'discord.dev',
    'discord.media',
    'discordapp.net',
    'discordstatus.com',
    'dis.gd',
  };

  /// The hosts the person trusted, in lower case.
  final Set<String> hosts;

  bool trusts(Uri uri) {
    final host = uri.host.toLowerCase();
    if (host.isEmpty) return false;
    return hosts.contains(host) ||
        discordHosts.any((own) => host == own || host.endsWith('.$own'));
  }

  /// These hosts and the host of [uri].
  TrustedDomains adding(Uri uri) {
    final host = uri.host.toLowerCase();
    if (host.isEmpty) return this;
    return TrustedDomains({...hosts, host});
  }

  List<String> toJson() => [...hosts]..sort();

  /// Reads a stored list. Anything that is not a list of strings reads as
  /// no trusted hosts, so a damaged file asks again rather than trusts.
  static TrustedDomains fromJson(Object? value) {
    if (value is! List) return none;
    return TrustedDomains({
      for (final host in value)
        if (host is String && host.isNotEmpty) host.toLowerCase(),
    });
  }
}

abstract interface class TrustedDomainsRepository {
  Future<TrustedDomains> load();

  Future<void> save(TrustedDomains domains);
}
