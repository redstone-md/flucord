import 'dart:async';

import 'package:flutter/services.dart';

import '../domain/discord_relationship.dart';
import '../domain/discord_social_activity.dart';
import '../domain/discord_social_call.dart';
import '../domain/discord_social_dm.dart';
import '../domain/discord_social_presence.dart';
import '../domain/discord_social_sdk.dart';
import 'discord_social_activity_mapper.dart';
import 'discord_social_call_mapper.dart';
import 'discord_social_dm_mapper.dart';
import 'discord_social_sdk_response_codec.dart';

final class DiscordSocialSdkEventRouter {
  const DiscordSocialSdkEventRouter({
    required this.persistGrant,
    required this.clearGrant,
    required this.currentAuthentication,
    required this.authentications,
    required this.dmEvents,
    required this.relationshipUpdates,
    required this.activityInvites,
    required this.activityCalls,
  });

  final Future<void> Function(Object? payload) persistGrant;
  final Future<void> Function() clearGrant;
  final Future<DiscordSocialSdkAuthentication> Function() currentAuthentication;
  final StreamSink<DiscordSocialSdkAuthentication> authentications;
  final StreamSink<DiscordSocialDmEvent> dmEvents;
  final StreamSink<DiscordSocialRelationshipUpdate> relationshipUpdates;
  final StreamSink<DiscordSocialActivityInviteEvent> activityInvites;
  final StreamSink<DiscordSocialCallState> activityCalls;

  Future<Object?> handle(String method, Object? arguments) async {
    if (method == 'authenticationGrantChanged') {
      await persistGrant(arguments);
      authentications.add(await currentAuthentication());
      return null;
    }
    if (method == 'authenticationExpired') {
      await clearGrant();
      authentications.add(DiscordSocialSdkAuthentication.signedOut);
      return null;
    }
    if (method == 'socialMessageChanged' || method == 'socialMessageDeleted') {
      try {
        dmEvents.add(DiscordSocialDmMapper.event(method, arguments));
      } on FormatException {
        throw const DiscordSocialSdkException('invalid_dm_event');
      }
      return null;
    }
    if (method == 'socialUserUpdated') {
      try {
        relationshipUpdates.add(
          DiscordSocialRelationshipUpdate(
            userId: DiscordSocialSdkResponseCodec.requiredIdentifier(
              arguments,
              'user_id',
            ),
          ),
        );
      } on ArgumentError {
        throw const DiscordSocialSdkException('invalid_relationship_event');
      }
      return null;
    }
    if (method == 'socialActivityInviteChanged') {
      try {
        activityInvites.add(DiscordSocialActivityMapper.event(arguments));
      } on Object {
        throw const DiscordSocialSdkException('invalid_activity_event');
      }
      return null;
    }
    if (method == 'socialActivityCallChanged') {
      try {
        activityCalls.add(DiscordSocialCallMapper.state(arguments));
      } on Object {
        throw const DiscordSocialSdkException('invalid_activity_call_event');
      }
      return null;
    }
    throw MissingPluginException('Unknown Social SDK event: $method');
  }
}
