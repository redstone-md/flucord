import 'discord_account_connection_controller.dart';
import 'discord_friends_controller.dart';
import 'discord_oauth_controller.dart';
import 'discord_social_activity_controller.dart';
import 'discord_social_dm_controller.dart';
import 'discord_social_presence_controller.dart';
import 'discord_social_sdk_controller.dart';
import '../domain/discord_social_sdk.dart';
import 'oauth_guild_directory_controller.dart';
import 'oauth_guild_membership_controller.dart';

/// Keeps every surface that belongs to an account in step with the
/// account.
///
/// The OAuth account decides which guilds the directory shows and whose
/// memberships are loaded; the Social SDK's availability, gated by whether
/// the account connection allows social access, decides what the friends,
/// DM, presence and activity surfaces may show. These rules used to sit in
/// the app widget, where no test could reach them without pumping the
/// whole client.
final class AccountConnectionCoordination {
  AccountConnectionCoordination({
    required DiscordOAuthController oauth,
    required DiscordAccountConnectionController accountConnection,
    required DiscordSocialSdkController socialSdk,
    required OAuthGuildDirectoryController directory,
    required OAuthGuildMembershipController membership,
    required DiscordFriendsController friends,
    required DiscordSocialDmController socialDm,
    required DiscordSocialPresenceController socialPresence,
    required DiscordSocialActivityController socialActivity,
  }) : _oauth = oauth,
       _accountConnection = accountConnection,
       _socialSdk = socialSdk,
       _directory = directory,
       _membership = membership,
       _friends = friends,
       _socialDm = socialDm,
       _socialPresence = socialPresence,
       _socialActivity = socialActivity {
    _oauth.addListener(_syncOAuthAccount);
    _socialSdk.addListener(_syncSocialSdkAvailability);
    _accountConnection.addListener(_syncSocialSdkAvailability);
  }

  final DiscordOAuthController _oauth;
  final DiscordAccountConnectionController _accountConnection;
  final DiscordSocialSdkController _socialSdk;
  final OAuthGuildDirectoryController _directory;
  final OAuthGuildMembershipController _membership;
  final DiscordFriendsController _friends;
  final DiscordSocialDmController _socialDm;
  final DiscordSocialPresenceController _socialPresence;
  final DiscordSocialActivityController _socialActivity;

  void dispose() {
    _oauth.removeListener(_syncOAuthAccount);
    _socialSdk.removeListener(_syncSocialSdkAvailability);
    _accountConnection.removeListener(_syncSocialSdkAvailability);
  }

  void _syncOAuthAccount() {
    final account = _oauth.account;
    _directory.reconcile(account);
    _membership.reconcileAccount(account?.id);
  }

  void _syncSocialSdkAvailability() {
    final availability = _socialSdk.availability;
    final authenticated = _accountConnection.socialAccessAllowed;
    for (final reconcileSession in _socialSurfaces) {
      reconcileSession(availability, authenticated: authenticated);
    }
  }

  /// Every social surface answers the same two questions: is the SDK
  /// usable at all, and is this account allowed to use it.
  List<
    void Function(DiscordSocialSdkAvailability?, {required bool authenticated})
  >
  get _socialSurfaces => [
    _friends.reconcileSession,
    _socialDm.reconcileSession,
    _socialPresence.reconcileSession,
    _socialActivity.reconcileSession,
  ];
}
