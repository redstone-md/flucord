import 'package:flutter_test/flutter_test.dart';
import 'package:flucord/src/application/discord_friends_controller.dart';
import 'package:flucord/src/domain/discord_relationship.dart';
import 'package:flucord/src/domain/discord_social_sdk.dart';

void main() {
  test('loads and sorts relationships when the native SDK is ready', () async {
    final gateway = _FriendsGateway([_friend('2', 'Zed'), _friend('1', 'Ada')]);
    final controller = DiscordFriendsController(gateway);
    addTearDown(controller.dispose);

    controller.reconcileAvailability(DiscordSocialSdkAvailability.ready);
    await controller.initialize();

    expect(controller.state, DiscordFriendsLoadState.ready);
    expect(controller.relationships.map((item) => item.user.displayName), [
      'Ada',
      'Zed',
    ]);
    expect(gateway.relationshipCalls, 1);
  });

  test('distinguishes native authorization from transport failure', () async {
    final gateway = _FriendsGateway.error('not_authenticated');
    final controller = DiscordFriendsController(gateway);
    addTearDown(controller.dispose);

    controller.reconcileAvailability(DiscordSocialSdkAvailability.ready);
    await controller.initialize();

    expect(controller.state, DiscordFriendsLoadState.authorizationRequired);
  });

  test('clears relationship state when SDK availability is revoked', () async {
    final gateway = _FriendsGateway([_friend('1', 'Ada')]);
    final controller = DiscordFriendsController(gateway);
    addTearDown(controller.dispose);
    controller.reconcileAvailability(DiscordSocialSdkAvailability.ready);
    await controller.initialize();

    controller.reconcileAvailability(
      DiscordSocialSdkAvailability.sdkNotBundled,
    );

    expect(controller.state, DiscordFriendsLoadState.unavailable);
    expect(controller.relationships, isEmpty);
  });
}

DiscordRelationship _friend(String id, String displayName) =>
    DiscordRelationship(
      user: DiscordRelationshipUser(id: id, displayName: displayName),
      kind: DiscordRelationshipKind.friend,
    );

final class _FriendsGateway implements DiscordSocialSdkGateway {
  _FriendsGateway(this._relationships) : _errorCode = null;

  _FriendsGateway.error(String code)
    : _relationships = const [],
      _errorCode = code;

  final List<DiscordRelationship> _relationships;
  final String? _errorCode;
  int relationshipCalls = 0;

  @override
  Future<DiscordSocialSdkAvailability> checkAvailability() async =>
      DiscordSocialSdkAvailability.ready;

  @override
  Future<List<DiscordRelationship>> fetchRelationships() async {
    relationshipCalls++;
    if (_errorCode case final code?) throw DiscordSocialSdkException(code);
    return _relationships;
  }
}
