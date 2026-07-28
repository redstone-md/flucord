import 'dart:async';

import 'package:flucord/src/application/message_component_controller.dart';
import 'package:flucord/src/domain/message_component.dart';
import 'package:flucord/src/presentation/widgets/message_component_row.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    MessageComponentController controller,
    List<MessageActionRow> rows, {
    List<String>? links,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(
        body: ListenableBuilder(
          listenable: controller,
          builder: (_, _) => MessageComponentRows(
            controller: controller,
            rows: rows,
            messageId: 'message-1',
            applicationId: 'app-1',
            messageFlags: 64,
            onOpenLink: (url) => links?.add(url),
          ),
        ),
      ),
    ),
  );

  testWidgets('a message with no components renders nothing', (tester) async {
    final repository = _FakeRepository();
    final controller = MessageComponentController(() => repository)
      ..show(channelId: 'channel-1');
    addTearDown(controller.dispose);
    addTearDown(repository.close);

    await pump(tester, controller, const []);

    expect(
      find.byKey(const ValueKey('message-components-message-1')),
      findsNothing,
    );
  });

  testWidgets('presses a button and sends the flags with it', (tester) async {
    final repository = _FakeRepository();
    final controller = MessageComponentController(() => repository)
      ..show(channelId: 'channel-1', guildId: 'guild-1');
    addTearDown(controller.dispose);
    addTearDown(repository.close);

    await pump(tester, controller, const [
      MessageActionRow(
        components: [
          MessageComponent(
            type: 2,
            customId: 'confirm',
            label: 'Confirm',
            style: MessageButtonStyle.primary,
            emojiName: '✅',
          ),
          MessageComponent(
            type: 2,
            customId: 'delete',
            label: 'Delete',
            style: MessageButtonStyle.danger,
          ),
          MessageComponent(
            type: 2,
            customId: 'ok',
            label: 'Fine',
            style: MessageButtonStyle.success,
          ),
          MessageComponent(type: 2, customId: 'plain', label: 'Plain'),
        ],
      ),
    ]);

    expect(find.text('Confirm'), findsOne);
    await tester.tap(find.byKey(const ValueKey('component-confirm-Confirm')));
    await tester.pumpAndSettle();

    expect(repository.presses.single, ('message-1', 'confirm', 64));
  });

  testWidgets('a link button opens rather than interacting', (tester) async {
    final repository = _FakeRepository();
    final controller = MessageComponentController(() => repository)
      ..show(channelId: 'channel-1');
    addTearDown(controller.dispose);
    addTearDown(repository.close);
    final links = <String>[];

    await pump(tester, controller, const [
      MessageActionRow(
        components: [
          MessageComponent(
            type: 2,
            customId: '',
            label: 'Open',
            style: MessageButtonStyle.link,
            url: 'https://example.com',
          ),
        ],
      ),
    ], links: links);

    await tester.tap(find.byKey(const ValueKey('component--Open')));
    await tester.pumpAndSettle();

    expect(links, ['https://example.com']);
    expect(repository.presses, isEmpty);
  });

  testWidgets('a disabled button cannot be pressed', (tester) async {
    final repository = _FakeRepository();
    final controller = MessageComponentController(() => repository)
      ..show(channelId: 'channel-1');
    addTearDown(controller.dispose);
    addTearDown(repository.close);

    await pump(tester, controller, const [
      MessageActionRow(
        components: [
          MessageComponent(
            type: 2,
            customId: 'x',
            label: 'Nope',
            isDisabled: true,
          ),
        ],
      ),
    ]);

    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('component-x-Nope')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('a button with only an emoji still has a label', (tester) async {
    final repository = _FakeRepository();
    final controller = MessageComponentController(() => repository)
      ..show(channelId: 'channel-1');
    addTearDown(controller.dispose);
    addTearDown(repository.close);

    await pump(tester, controller, const [
      MessageActionRow(
        components: [
          MessageComponent(type: 2, customId: 'e', emojiName: '🎉'),
          MessageComponent(type: 2, customId: 'blank'),
        ],
      ),
    ]);

    expect(find.text('🎉'), findsOne);
    expect(find.text('Button'), findsOne);
  });

  testWidgets('a string select sends what was chosen', (tester) async {
    final repository = _FakeRepository();
    final controller = MessageComponentController(() => repository)
      ..show(channelId: 'channel-1');
    addTearDown(controller.dispose);
    addTearDown(repository.close);

    await pump(tester, controller, const [
      MessageActionRow(
        components: [
          MessageComponent(
            type: 3,
            customId: 'pick',
            placeholder: 'Choose one',
            options: [
              MessageSelectOption(value: 'a', label: 'Apple'),
              MessageSelectOption(value: 'b', label: 'Pear'),
            ],
          ),
        ],
      ),
    ]);

    await tester.tap(find.byKey(const ValueKey('component-select-pick')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pear').last);
    await tester.pumpAndSettle();

    // Records hold the list by reference, so the fields are compared apart.
    expect(repository.selections.single.$1, 'pick');
    expect(repository.selections.single.$2, ['b']);
  });

  testWidgets('a select this surface cannot resolve is shown disabled', (
    tester,
  ) async {
    final repository = _FakeRepository();
    final controller = MessageComponentController(() => repository)
      ..show(channelId: 'channel-1');
    addTearDown(controller.dispose);
    addTearDown(repository.close);

    await pump(tester, controller, const [
      MessageActionRow(
        components: [
          // A user select is resolved against the server directory, which the
          // message surface has no picker for.
          MessageComponent(
            type: 5,
            customId: 'who',
            placeholder: 'Pick a member',
          ),
          MessageComponent(type: 3, customId: 'empty'),
        ],
      ),
    ]);

    expect(find.text('Pick a member'), findsOne);
    expect(find.text('Unsupported menu'), findsOne);
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('component-select-who')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('a modal collects what the application asked for', (
    tester,
  ) async {
    late BuildContext dialogContext;
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              dialogContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    final result = MessageModalDialog.show(
      dialogContext,
      const ModalDefinition(
        customId: 'form',
        title: 'Report',
        applicationId: 'app-1',
        nonce: 'n-1',
        fields: [
          ModalField(
            customId: 'reason',
            label: 'Reason',
            isRequired: true,
            isParagraph: true,
            maxLength: 200,
          ),
          ModalField(
            customId: 'extra',
            label: 'Anything else',
            value: 'prefilled',
            placeholder: 'Optional',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Report'), findsOne);
    // What the application prefilled is there to edit.
    expect(find.text('prefilled'), findsOne);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('modal-submit')))
          .onPressed,
      isNull,
    );

    await tester.enterText(
      find.byKey(const ValueKey('modal-field-reason')),
      'spam',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('modal-submit')));
    await tester.pumpAndSettle();

    expect(await result, {'reason': 'spam', 'extra': 'prefilled'});
  });

  testWidgets('a modal with no title still names itself', (tester) async {
    late BuildContext dialogContext;
    await tester.pumpWidget(
      MaterialApp(
        theme: FlucordTheme.dark,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              dialogContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    final result = MessageModalDialog.show(
      dialogContext,
      const ModalDefinition(
        customId: 'form',
        title: '',
        applicationId: 'app-1',
        nonce: 'n-1',
        fields: [ModalField(customId: 'note', label: 'Note')],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Form'), findsOne);
    await tester.tap(find.byKey(const ValueKey('modal-cancel')));
    await tester.pumpAndSettle();

    expect(await result, isNull);
  });
}

final class _FakeRepository implements MessageComponentRepository {
  final StreamController<ModalDefinition> _modals =
      StreamController.broadcast();
  final List<(String, String, int)> presses = [];
  final List<(String, List<String>)> selections = [];

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
    if (component.isSelect) {
      selections.add((component.customId, values));
      return;
    }
    presses.add((messageId, component.customId, messageFlags));
  }

  @override
  Future<void> submitModal(
    ModalDefinition modal, {
    required String channelId,
    required Map<String, String> values,
    String? guildId,
  }) async {}

  Future<void> close() => _modals.close();
}
