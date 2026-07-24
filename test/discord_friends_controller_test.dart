import 'dart:async';

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

  test('accepts an incoming request only after native confirmation', () async {
    final completer = Completer<void>();
    final request = _request('1', 'Ada');
    final gateway = _FriendsGateway([request])..mutationCompleter = completer;
    final controller = DiscordFriendsController(gateway);
    addTearDown(controller.dispose);
    controller.reconcileAvailability(DiscordSocialSdkAvailability.ready);
    await controller.initialize();

    final operation = controller.updateRelationship(
      request,
      DiscordRelationshipAction.acceptRequest,
    );
    expect(controller.isMutating('1'), isTrue);
    expect(controller.relationships.single.kind, request.kind);

    completer.complete();
    expect(await operation, isTrue);
    expect(controller.isMutating('1'), isFalse);
    expect(
      controller.relationships.single.kind,
      DiscordRelationshipKind.friend,
    );
    expect(
      gateway.mutations.single.action,
      DiscordRelationshipAction.acceptRequest,
    );
  });

  test(
    'retains the relationship and exposes a per-user mutation error',
    () async {
      final friend = _friend('1', 'Ada');
      final gateway = _FriendsGateway([friend])..mutationError = 'rate_limited';
      final controller = DiscordFriendsController(gateway);
      addTearDown(controller.dispose);
      controller.reconcileAvailability(DiscordSocialSdkAvailability.ready);
      await controller.initialize();

      final succeeded = await controller.updateRelationship(
        friend,
        DiscordRelationshipAction.removeFriend,
      );

      expect(succeeded, isFalse);
      expect(controller.relationships.single.user.id, '1');
      expect(controller.mutationErrorFor('1'), 'rate_limited');
      expect(controller.isMutating('1'), isFalse);
    },
  );

  test('rejects actions that do not match the relationship type', () async {
    final friend = _friend('1', 'Ada');
    final gateway = _FriendsGateway([friend]);
    final controller = DiscordFriendsController(gateway);
    addTearDown(controller.dispose);
    controller.reconcileAvailability(DiscordSocialSdkAvailability.ready);
    await controller.initialize();

    expect(
      await controller.updateRelationship(
        friend,
        DiscordRelationshipAction.acceptRequest,
      ),
      isFalse,
    );
    expect(gateway.mutations, isEmpty);
  });
}

DiscordRelationship _friend(String id, String displayName) =>
    DiscordRelationship(
      user: DiscordRelationshipUser(id: id, displayName: displayName),
      kind: DiscordRelationshipKind.friend,
    );

DiscordRelationship _request(String id, String displayName) =>
    DiscordRelationship(
      user: DiscordRelationshipUser(id: id, displayName: displayName),
      kind: DiscordRelationshipKind.incomingRequest,
    );

final class _FriendsGateway implements DiscordSocialSdkGateway {
  _FriendsGateway(this._relationships) : _errorCode = null;

  _FriendsGateway.error(String code)
    : _relationships = const [],
      _errorCode = code;

  final List<DiscordRelationship> _relationships;
  final String? _errorCode;
  int relationshipCalls = 0;
  final List<({String userId, DiscordRelationshipAction action})> mutations =
      [];
  Completer<void>? mutationCompleter;
  String? mutationError;

  @override
  Future<DiscordSocialSdkAvailability> checkAvailability() async =>
      DiscordSocialSdkAvailability.ready;

  @override
  Future<List<DiscordRelationship>> fetchRelationships() async {
    relationshipCalls++;
    if (_errorCode case final code?) throw DiscordSocialSdkException(code);
    return _relationships;
  }

  @override
  Future<void> updateRelationship({
    required String userId,
    required DiscordRelationshipAction action,
  }) async {
    mutations.add((userId: userId, action: action));
    if (mutationCompleter case final completer?) await completer.future;
    if (mutationError case final code?) throw DiscordSocialSdkException(code);
  }
}
