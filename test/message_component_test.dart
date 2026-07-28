import 'dart:async';

import 'package:flucord/src/application/message_component_controller.dart';
import 'package:flucord/src/data/discord/discord_message_component_service.dart';
import 'package:flucord/src/domain/message_component.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mapper', () {
    test('reads buttons and selects out of an action row', () {
      final rows = DiscordMessageComponentMapper.readRows([
        {
          'type': 1,
          'components': [
            {
              'type': 2,
              'style': 1,
              'custom_id': 'confirm',
              'label': 'Confirm',
              'emoji': {'name': '✅'},
            },
            {
              'type': 2,
              'style': 5,
              'url': 'https://example.com',
              'label': 'Open',
            },
            {
              'type': 3,
              'custom_id': 'pick',
              'placeholder': 'Choose',
              'min_values': 1,
              'max_values': 2,
              'options': [
                {'value': 'a', 'label': 'A', 'default': true},
                {'value': 'b', 'description': 'Second'},
                {'label': 'no value'},
              ],
            },
            // Not something that can be pressed.
            {'type': 4, 'custom_id': 'text'},
            // A non-link button with no custom id can never be answered.
            {'type': 2, 'style': 1, 'label': 'Broken'},
            // A link button with no url points nowhere.
            {'type': 2, 'style': 5, 'label': 'Nowhere'},
            {'no': 'type'},
          ],
        },
      ]);

      final components = rows.single.components;
      expect(components.length, 3);
      final confirm = components.first;
      expect(confirm.isButton, isTrue);
      expect(confirm.style, MessageButtonStyle.primary);
      expect(confirm.emojiName, '✅');
      expect(confirm.isActionable, isTrue);

      final link = components[1];
      expect(link.isLink, isTrue);
      expect(link.url, 'https://example.com');
      expect(link.customId, isEmpty);
      expect(link.isActionable, isTrue);

      final select = components.last;
      expect(select.isSelect, isTrue);
      expect(select.placeholder, 'Choose');
      expect(select.maxValues, 2);
      expect(select.options.map((option) => option.value), ['a', 'b']);
      expect(select.options.first.isDefault, isTrue);
      expect(select.options.last.displayLabel, 'b');
      expect(select.options.first.description, isEmpty);
    });

    test('walks the containers Components V2 nests rows in', () {
      final rows = DiscordMessageComponentMapper.readRows([
        {
          'type': 17,
          'components': [
            {
              'type': 9,
              'components': [
                {
                  'type': 1,
                  'components': [
                    {'type': 2, 'style': 2, 'custom_id': 'deep'},
                  ],
                },
              ],
            },
          ],
        },
      ]);

      // A message whose buttons sit inside a container would otherwise render
      // as having none.
      expect(rows.single.components.single.customId, 'deep');
    });

    test('a row with nothing actionable is not a row', () {
      expect(
        DiscordMessageComponentMapper.readRows([
          {
            'type': 1,
            'components': [
              {'type': 4, 'custom_id': 'text'},
            ],
          },
        ]),
        isEmpty,
      );
      expect(DiscordMessageComponentMapper.readRows('nonsense'), isEmpty);
      expect(DiscordMessageComponentMapper.readRows(null), isEmpty);
    });

    test('a disabled component is not actionable', () {
      final component = DiscordMessageComponentMapper.readComponent(const {
        'type': 2,
        'style': 3,
        'custom_id': 'x',
        'disabled': true,
      })!;

      expect(component.isActionable, isFalse);
      expect(component.style, MessageButtonStyle.success);
    });

    test('maps every button style Discord numbers', () {
      expect(MessageButtonStyle.fromWire(1), MessageButtonStyle.primary);
      expect(MessageButtonStyle.fromWire(2), MessageButtonStyle.secondary);
      expect(MessageButtonStyle.fromWire(3), MessageButtonStyle.success);
      expect(MessageButtonStyle.fromWire(4), MessageButtonStyle.danger);
      expect(MessageButtonStyle.fromWire(5), MessageButtonStyle.link);
      expect(MessageButtonStyle.fromWire(6), MessageButtonStyle.premium);
      expect(MessageButtonStyle.fromWire(null), MessageButtonStyle.secondary);
      expect(MessageButtonStyle.danger.wireValue, 4);
    });

    test('reads a modal, and refuses one with nothing to fill in', () {
      final modal = DiscordMessageComponentMapper.readModal(const {
        'custom_id': 'form',
        'title': 'Report',
        'application_id': 'app-1',
        'nonce': 'n-1',
        'components': [
          {
            'type': 1,
            'components': [
              {
                'type': 4,
                'custom_id': 'reason',
                'label': 'Reason',
                'style': 2,
                'required': true,
                'value': 'prefilled',
                'placeholder': 'Why are you reporting this?',
                'max_length': 200,
              },
              {'type': 2, 'custom_id': 'not a field'},
              {'type': 4, 'label': 'no id'},
            ],
          },
        ],
      })!;

      expect(modal.title, 'Report');
      expect(modal.applicationId, 'app-1');
      expect(modal.nonce, 'n-1');
      final field = modal.fields.single;
      expect(field.customId, 'reason');
      expect(field.isRequired, isTrue);
      expect(field.isParagraph, isTrue);
      expect(field.value, 'prefilled');
      expect(field.placeholder, 'Why are you reporting this?');
      expect(field.maxLength, 200);

      expect(
        DiscordMessageComponentMapper.readModal(const {'custom_id': 'form'}),
        isNull,
      );
      expect(DiscordMessageComponentMapper.readModal(const {}), isNull);
    });
  });

  group('service', () {
    test('a button press names the message it was on', () async {
      final transport = _FakeTransport();
      final service = DiscordMessageComponentService(
        transport,
        sessionId: () => 'session-1',
        nonce: () => 'nonce-1',
      );
      addTearDown(service.close);

      await service.activate(
        channelId: 'channel-1',
        messageId: 'message-1',
        applicationId: 'app-1',
        guildId: 'guild-1',
        messageFlags: 64,
        component: const MessageComponent(type: 2, customId: 'confirm'),
      );

      final body = transport.interactions.single;
      expect(body['type'], 3);
      expect(body['message_id'], 'message-1');
      expect(body['message_flags'], 64);
      expect(body['guild_id'], 'guild-1');
      expect(body['session_id'], 'session-1');
      expect(body['nonce'], 'nonce-1');
      expect(body['data'], {'component_type': 2, 'custom_id': 'confirm'});
    });

    test('a select carries what was chosen', () async {
      final transport = _FakeTransport();
      final service = DiscordMessageComponentService(
        transport,
        sessionId: () => 'session-1',
      );
      addTearDown(service.close);

      await service.activate(
        channelId: 'channel-1',
        messageId: 'message-1',
        applicationId: 'app-1',
        component: const MessageComponent(type: 3, customId: 'pick'),
        values: const ['a'],
      );

      final data =
          transport.interactions.single['data']! as Map<String, Object?>;
      expect(data['values'], ['a']);
      // A DM names no guild.
      expect(transport.interactions.single.containsKey('guild_id'), isFalse);
    });

    test('a link button and a dead component are refused', () async {
      final transport = _FakeTransport();
      final service = DiscordMessageComponentService(
        transport,
        sessionId: () => 'session-1',
      );
      addTearDown(service.close);

      await expectLater(
        service.activate(
          channelId: 'c',
          messageId: 'm',
          applicationId: 'a',
          component: const MessageComponent(
            type: 2,
            customId: '',
            style: MessageButtonStyle.link,
            url: 'https://example.com',
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        service.activate(
          channelId: 'c',
          messageId: 'm',
          applicationId: 'a',
          component: const MessageComponent(
            type: 2,
            customId: 'x',
            isDisabled: true,
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(transport.interactions, isEmpty);
    });

    test('nothing is sent without a gateway session', () async {
      final transport = _FakeTransport();
      final service = DiscordMessageComponentService(
        transport,
        sessionId: () => null,
      );
      addTearDown(service.close);

      await expectLater(
        service.activate(
          channelId: 'c',
          messageId: 'm',
          applicationId: 'a',
          component: const MessageComponent(type: 2, customId: 'x'),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('a modal submission reuses the nonce it was opened with', () async {
      final transport = _FakeTransport();
      final service = DiscordMessageComponentService(
        transport,
        sessionId: () => 'session-1',
      );
      addTearDown(service.close);
      const modal = ModalDefinition(
        customId: 'form',
        title: 'Report',
        applicationId: 'app-1',
        nonce: 'n-1',
        fields: [
          ModalField(customId: 'reason', isRequired: true),
          ModalField(customId: 'extra'),
        ],
      );

      await service.submitModal(
        modal,
        channelId: 'channel-1',
        guildId: 'guild-1',
        values: const {'reason': 'spam'},
      );

      final body = transport.interactions.single;
      expect(body['type'], 5);
      expect(body['guild_id'], 'guild-1');
      expect(body['nonce'], 'n-1');
      final data = body['data']! as Map<String, Object?>;
      expect(data['custom_id'], 'form');
      // Every field is sent, empty ones included, in a row apiece.
      expect(data['components'], [
        {
          'type': 1,
          'components': [
            {'type': 4, 'custom_id': 'reason', 'value': 'spam'},
          ],
        },
        {
          'type': 1,
          'components': [
            {'type': 4, 'custom_id': 'extra', 'value': ''},
          ],
        },
      ]);
    });

    test('a modal with no nonce gets one', () async {
      final transport = _FakeTransport();
      final service = DiscordMessageComponentService(
        transport,
        sessionId: () => 'session-1',
        nonce: () => 'fresh',
      );
      addTearDown(service.close);

      await service.submitModal(
        const ModalDefinition(
          customId: 'form',
          title: '',
          applicationId: 'app-1',
          nonce: '',
          fields: [ModalField(customId: 'reason')],
        ),
        channelId: 'channel-1',
        values: const {},
      );

      expect(transport.interactions.single['nonce'], 'fresh');
    });

    test('a modal missing a required field is refused', () async {
      final transport = _FakeTransport();
      final service = DiscordMessageComponentService(
        transport,
        sessionId: () => 'session-1',
      );
      addTearDown(service.close);

      await expectLater(
        service.submitModal(
          const ModalDefinition(
            customId: 'form',
            title: '',
            applicationId: 'app-1',
            nonce: 'n',
            fields: [ModalField(customId: 'reason', isRequired: true)],
          ),
          channelId: 'channel-1',
          values: const {'reason': '   '},
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(transport.interactions, isEmpty);
    });

    test('publishes the modal an application opens', () async {
      final service = DiscordMessageComponentService(
        _FakeTransport(),
        sessionId: () => 'session-1',
      );
      final seen = <ModalDefinition>[];
      final subscription = service.modals.listen(seen.add);
      addTearDown(subscription.cancel);

      expect(
        service.accept('INTERACTION_MODAL_CREATE', const {
          'custom_id': 'form',
          'components': [
            {
              'type': 1,
              'components': [
                {'type': 4, 'custom_id': 'reason'},
              ],
            },
          ],
        }),
        isNotNull,
      );
      expect(service.accept('MESSAGE_CREATE', const {}), isNull);
      expect(service.accept('INTERACTION_MODAL_CREATE', const {}), isNull);
      await Future<void>.delayed(Duration.zero);

      expect(seen.single.customId, 'form');

      await service.close();
      await service.close();
    });
  });

  group('controller', () {
    test('a transport that cannot interact does nothing', () async {
      final controller = MessageComponentController(() => null);
      addTearDown(controller.dispose);
      controller.show(channelId: 'channel-1');

      expect(controller.isSupported, isFalse);
      expect(
        await controller.activate(
          messageId: 'm',
          applicationId: 'a',
          component: const MessageComponent(type: 2, customId: 'x'),
        ),
        isFalse,
      );
      expect(await controller.submitModal(const {}), isFalse);
    });

    test('presses a button in the conversation on screen', () async {
      final repository = _FakeRepository();
      final controller = MessageComponentController(() => repository);
      addTearDown(controller.dispose);
      addTearDown(repository.close);
      controller.show(channelId: 'channel-1', guildId: 'guild-1');

      expect(
        await controller.activate(
          messageId: 'message-1',
          applicationId: 'app-1',
          component: const MessageComponent(type: 2, customId: 'confirm'),
          messageFlags: 64,
        ),
        isTrue,
      );

      final press = repository.presses.single;
      expect(press.channelId, 'channel-1');
      expect(press.guildId, 'guild-1');
      expect(press.messageId, 'message-1');
      expect(press.messageFlags, 64);
      expect(controller.isBusy('message-1'), isFalse);
    });

    test('a link or dead component is not sent', () async {
      final repository = _FakeRepository();
      final controller = MessageComponentController(() => repository);
      addTearDown(controller.dispose);
      addTearDown(repository.close);
      controller.show(channelId: 'channel-1');

      expect(
        await controller.activate(
          messageId: 'm',
          applicationId: 'a',
          component: const MessageComponent(
            type: 2,
            customId: '',
            style: MessageButtonStyle.link,
            url: 'https://example.com',
          ),
        ),
        isFalse,
      );
      expect(repository.presses, isEmpty);
    });

    test('a second press on the same message is refused', () async {
      final gate = Completer<void>();
      final repository = _FakeRepository(gate: gate);
      final controller = MessageComponentController(() => repository);
      addTearDown(controller.dispose);
      addTearDown(repository.close);
      controller.show(channelId: 'channel-1');
      const component = MessageComponent(type: 2, customId: 'x');

      final first = controller.activate(
        messageId: 'message-1',
        applicationId: 'app-1',
        component: component,
      );
      expect(controller.isBusy('message-1'), isTrue);
      // Another message is not blocked by this one.
      expect(controller.isBusy('message-2'), isFalse);
      expect(
        await controller.activate(
          messageId: 'message-1',
          applicationId: 'app-1',
          component: component,
        ),
        isFalse,
      );

      gate.complete();
      expect(await first, isTrue);
    });

    test('a rejected press is reported', () async {
      final repository = _FakeRepository(fail: true);
      final controller = MessageComponentController(() => repository);
      addTearDown(controller.dispose);
      addTearDown(repository.close);
      controller.show(channelId: 'channel-1');

      expect(
        await controller.activate(
          messageId: 'm',
          applicationId: 'a',
          component: const MessageComponent(type: 2, customId: 'x'),
        ),
        isFalse,
      );

      expect(controller.error, isNotNull);
      expect(controller.isBusy('m'), isFalse);
    });

    test('holds the modal an application opens until it is answered', () async {
      final repository = _FakeRepository();
      final controller = MessageComponentController(() => repository);
      addTearDown(controller.dispose);
      addTearDown(repository.close);
      controller.show(channelId: 'channel-1');
      expect(controller.isSupported, isTrue);

      repository.openModal(_modal);
      await Future<void>.delayed(Duration.zero);
      expect(controller.pendingModal?.customId, 'form');

      expect(await controller.submitModal(const {'reason': 'spam'}), isTrue);
      expect(repository.submissions.single.$2, {'reason': 'spam'});
      expect(controller.pendingModal, isNull);
    });

    test('dismissing the modal answers nothing', () async {
      final repository = _FakeRepository();
      final controller = MessageComponentController(() => repository);
      addTearDown(controller.dispose);
      addTearDown(repository.close);
      controller.show(channelId: 'channel-1');

      repository.openModal(_modal);
      await Future<void>.delayed(Duration.zero);

      controller
        ..dismissModal()
        // Dismissing twice is what a closed dialog does on the way out.
        ..dismissModal();

      expect(controller.pendingModal, isNull);
      expect(await controller.submitModal(const {}), isFalse);
      expect(repository.submissions, isEmpty);
    });

    test('a rejected submission keeps the modal open', () async {
      final repository = _FakeRepository(fail: true);
      final controller = MessageComponentController(() => repository);
      addTearDown(controller.dispose);
      addTearDown(repository.close);
      controller.show(channelId: 'channel-1');
      repository.openModal(_modal);
      await Future<void>.delayed(Duration.zero);

      expect(await controller.submitModal(const {'reason': 'spam'}), isFalse);

      expect(controller.error, isNotNull);
      expect(controller.pendingModal, isNotNull);
    });

    test('swapping the transport drops a modal from the old one', () async {
      var repository = _FakeRepository();
      final first = repository;
      addTearDown(first.close);
      final controller = MessageComponentController(() => repository);
      addTearDown(controller.dispose);
      controller.show(channelId: 'channel-1');
      repository.openModal(_modal);
      await Future<void>.delayed(Duration.zero);
      expect(controller.pendingModal, isNotNull);

      repository = _FakeRepository();
      addTearDown(() => repository.close());

      expect(controller.isSupported, isTrue);
      expect(controller.pendingModal, isNull);
    });
  });
}

const _modal = ModalDefinition(
  customId: 'form',
  title: 'Report',
  applicationId: 'app-1',
  nonce: 'n-1',
  fields: [ModalField(customId: 'reason')],
);

final class _FakeTransport implements DiscordComponentTransport {
  final List<Map<String, Object?>> interactions = [];

  @override
  Future<void> postInteraction(Map<String, Object?> body) async =>
      interactions.add(body);
}

final class _Press {
  const _Press({
    required this.channelId,
    required this.messageId,
    required this.messageFlags,
    this.guildId,
  });

  final String channelId;
  final String messageId;
  final int messageFlags;
  final String? guildId;
}

final class _FakeRepository implements MessageComponentRepository {
  _FakeRepository({this.fail = false, this.gate});

  final bool fail;
  final Completer<void>? gate;
  final StreamController<ModalDefinition> _modals =
      StreamController.broadcast();
  final List<_Press> presses = [];
  final List<(ModalDefinition, Map<String, String>)> submissions = [];

  void openModal(ModalDefinition modal) => _modals.add(modal);

  @override
  Stream<ModalDefinition> get modals => _modals.stream;

  @override
  Future<void> activate({
    required String channelId,
    required String messageId,
    required String applicationId,
    required MessageComponent component,
    String? guildId,
    int messageFlags = 0,
    List<String> values = const [],
  }) async {
    await gate?.future;
    if (fail) throw StateError('rejected');
    presses.add(
      _Press(
        channelId: channelId,
        messageId: messageId,
        messageFlags: messageFlags,
        guildId: guildId,
      ),
    );
  }

  @override
  Future<void> submitModal(
    ModalDefinition modal, {
    required String channelId,
    required Map<String, String> values,
    String? guildId,
  }) async {
    if (fail) throw StateError('rejected');
    submissions.add((modal, values));
  }

  Future<void> close() => _modals.close();
}
