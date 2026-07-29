import 'dart:async';

import 'package:flucord/src/application/guild_member_list_controller.dart';
import 'package:flucord/src/domain/guild_member_list.dart';
import 'package:flucord/src/domain/guild_member_list_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const debounce = Duration(milliseconds: 1);
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 10));

  GuildMemberList listOf({
    String guildId = 'guild-1',
    String listId = 'everyone',
    int version = 1,
  }) => GuildMemberList(
    guildId: guildId,
    listId: listId,
    rows: const [GuildMemberListGroupRow(groupId: 'online', count: 0)],
    groups: const [GuildMemberListGroup(id: 'online', count: 0, index: 0)],
    memberCount: 1,
    onlineCount: 1,
    version: version,
  );

  test('subscribes the head page as soon as a channel is watched', () {
    final repository = _FakeMemberListRepository()
      ..listIds['channel-1'] = 'everyone';
    final controller = GuildMemberListController(() => repository);
    addTearDown(controller.dispose);
    var notifications = 0;
    controller.addListener(() => notifications++);

    controller.viewChannel(guildId: 'guild-1', channelId: 'channel-1');

    expect(controller.listId, 'everyone');
    expect(controller.channelId, 'channel-1');
    expect(controller.list, isNull);
    expect(controller.isLoaded, isFalse);
    expect(repository.subscribed, hasLength(1));
    expect(repository.subscribed.single.$1, 'guild-1');
    expect(repository.subscribed.single.$2, 'channel-1');
    expect(repository.subscribed.single.$3, [
      [0, 99],
    ]);
    expect(notifications, 1);
  });

  test('adopts a roster the transport already holds', () {
    final repository = _FakeMemberListRepository()
      ..listIds['channel-1'] = 'everyone'
      ..cached['everyone'] = listOf();
    final controller = GuildMemberListController(() => repository);
    addTearDown(controller.dispose);

    controller.viewChannel(guildId: 'guild-1', channelId: 'channel-1');

    expect(controller.list?.version, 1);
    expect(controller.isLoaded, isTrue);
  });

  test('watching the same channel again subscribes nothing new', () {
    final repository = _FakeMemberListRepository();
    final controller = GuildMemberListController(() => repository);
    addTearDown(controller.dispose);

    controller
      ..viewChannel(guildId: 'guild-1', channelId: 'channel-1')
      ..viewChannel(guildId: 'guild-1', channelId: 'channel-1');

    expect(repository.subscribed, hasLength(1));
    expect(repository.unsubscribed, isEmpty);
  });

  test('switching channels releases the previous subscription', () {
    final repository = _FakeMemberListRepository();
    final controller = GuildMemberListController(() => repository);
    addTearDown(controller.dispose);

    controller
      ..viewChannel(guildId: 'guild-1', channelId: 'channel-1')
      ..viewChannel(guildId: 'guild-1', channelId: 'channel-2');

    expect(repository.unsubscribed, [('guild-1', 'channel-1')]);
    expect(repository.subscribed.last.$2, 'channel-2');
  });

  test('a channel outside a guild leaves the panel empty', () {
    final repository = _FakeMemberListRepository()
      ..listIds['channel-1'] = 'everyone'
      ..cached['everyone'] = listOf();
    final controller = GuildMemberListController(() => repository);
    addTearDown(controller.dispose);

    controller
      ..viewChannel(guildId: 'guild-1', channelId: 'channel-1')
      ..viewChannel(guildId: 'guild-1', channelId: null);

    expect(controller.list, isNull);
    expect(controller.listId, isNull);
    expect(controller.isLoaded, isFalse);
    expect(repository.unsubscribed, [('guild-1', 'channel-1')]);
  });

  test('scrolling subscribes the pages the viewport reaches', () async {
    final repository = _FakeMemberListRepository();
    final controller = GuildMemberListController(
      () => repository,
      scrollDebounce: debounce,
    );
    addTearDown(controller.dispose);
    controller.viewChannel(guildId: 'guild-1', channelId: 'channel-1');

    controller
      ..updateViewport(scrollOffset: 0, viewportHeight: 440, rowHeight: 44)
      // Only the last position within the debounce window is sent.
      ..updateViewport(
        scrollOffset: 44 * 250,
        viewportHeight: 440,
        rowHeight: 44,
      );
    await settle();

    expect(repository.subscribed, hasLength(2));
    expect(repository.subscribed.last.$3, [
      [0, 99],
      [200, 299],
    ]);
  });

  test('a viewport report without a watched channel does nothing', () async {
    final repository = _FakeMemberListRepository();
    final controller = GuildMemberListController(
      () => repository,
      scrollDebounce: debounce,
    );
    addTearDown(controller.dispose);

    controller.updateViewport(
      scrollOffset: 0,
      viewportHeight: 440,
      rowHeight: 44,
    );
    await settle();

    expect(repository.subscribed, isEmpty);
  });

  test('applies updates for the watched list only', () async {
    final repository = _FakeMemberListRepository()
      ..listIds['channel-1'] = 'everyone';
    final controller = GuildMemberListController(() => repository);
    addTearDown(controller.dispose);
    controller.viewChannel(guildId: 'guild-1', channelId: 'channel-1');
    var notifications = 0;
    controller.addListener(() => notifications++);

    repository
      ..publish(listOf(listId: '3141592653'))
      ..publish(listOf(guildId: 'guild-2'))
      ..publish(listOf(version: 7));
    await settle();

    expect(controller.list?.version, 7);
    expect(notifications, 1);
  });

  test('a transport without member lists leaves the panel empty', () {
    final controller = GuildMemberListController(() => null);
    addTearDown(controller.dispose);

    controller.viewChannel(guildId: 'guild-1', channelId: 'channel-1');

    expect(controller.list, isNull);
    expect(controller.listId, isNull);
  });

  test('a swapped transport is rebound and resubscribed', () async {
    var repository = _FakeMemberListRepository();
    final first = repository;
    final controller = GuildMemberListController(() => repository);
    addTearDown(controller.dispose);
    controller.viewChannel(guildId: 'guild-1', channelId: 'channel-1');

    repository = _FakeMemberListRepository();
    controller.viewChannel(guildId: 'guild-1', channelId: 'channel-1');
    first.publish(listOf());
    await settle();

    expect(repository.subscribed, hasLength(1));
    expect(controller.list, isNull);
  });

  test('clearing releases the subscription', () {
    final repository = _FakeMemberListRepository();
    final controller = GuildMemberListController(() => repository);
    addTearDown(controller.dispose);

    controller
      ..viewChannel(guildId: 'guild-1', channelId: 'channel-1')
      ..clear();

    expect(repository.unsubscribed, [('guild-1', 'channel-1')]);
    expect(controller.list, isNull);
  });

  test('a disposed controller stops touching the transport', () async {
    final repository = _FakeMemberListRepository();
    final controller = GuildMemberListController(
      () => repository,
      scrollDebounce: debounce,
    );
    controller.viewChannel(guildId: 'guild-1', channelId: 'channel-1');
    controller.dispose();

    controller
      ..viewChannel(guildId: 'guild-1', channelId: 'channel-2')
      ..updateViewport(scrollOffset: 0, viewportHeight: 440, rowHeight: 44);
    repository.publish(listOf());
    await settle();

    expect(repository.subscribed, hasLength(1));
    expect(controller.list, isNull);
  });
}

final class _FakeMemberListRepository implements GuildMemberListRepository {
  final StreamController<GuildMemberList> _updates =
      StreamController.broadcast();
  final List<(String, String, List<List<int>>)> subscribed = [];
  final List<(String, String)> unsubscribed = [];
  final Map<String, String> listIds = {};
  final Map<String, GuildMemberList> cached = {};

  void publish(GuildMemberList list) => _updates.add(list);

  @override
  Stream<GuildMemberList> get memberListUpdates => _updates.stream;

  @override
  String memberListIdFor({
    required String guildId,
    required String channelId,
  }) => listIds[channelId] ?? 'everyone';

  @override
  GuildMemberList? memberListFor({
    required String guildId,
    required String listId,
  }) => cached[listId];

  @override
  void subscribeMemberRanges({
    required String guildId,
    required String channelId,
    required List<List<int>> ranges,
  }) => subscribed.add((
    guildId,
    channelId,
    ranges.map(List<int>.from).toList(growable: false),
  ));

  @override
  void unsubscribeMemberRanges({
    required String guildId,
    required String channelId,
  }) => unsubscribed.add((guildId, channelId));

  /// What the surface asked to search for, so a test can check it asked.
  final List<(String, String)> searches = [];

  @override
  void searchGuildMembers({
    required String guildId,
    required String query,
    int limit = 25,
  }) => searches.add((guildId, query));
}
