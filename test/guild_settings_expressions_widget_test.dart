import 'package:flucord/src/application/guild_settings_controller.dart';
import 'package:flucord/src/domain/workspace_permissions.dart';
import 'dart:typed_data';

import 'package:flucord/src/domain/guild_expression_errors.dart';
import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/presentation/expression_file_picker.dart';
import 'package:flucord/src/presentation/widgets/guild_settings_expressions_section.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_expression_repository.dart';
import 'support/guild_settings_fixtures.dart';

/// Answers the picker without a file dialog, with a valid PNG so the codec
/// accepts it.
final class _StubFilePicker implements ExpressionFilePicker {
  _StubFilePicker(this.selections);

  final List<ExpressionFileSelection> selections;
  int calls = 0;

  @override
  Future<ExpressionFileSelection?> pick(ExpressionKind kind) async {
    calls++;
    return selections.length > calls - 1 ? selections[calls - 1] : null;
  }
}

/// A small PNG, the four tag bytes the codec reads plus padding so the file
/// is not empty.
final _pngBytes = () {
  final bytes = Uint8List.fromList(List<int>.generate(64, (index) => index));
  bytes.setAll(0, const [0x89, 0x50, 0x4e, 0x47]);
  return bytes;
}();

ExpressionFileSelection _png(String name) =>
    ExpressionFileCodec.encode(ExpressionKind.emoji, name, _pngBytes);

void main() {
  testWidgets('the page names the three kinds and their upload buttons', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = FakeExpressionRepository();
    final controller = _controller(repository);
    addTearDown(controller.dispose);

    await _pump(tester, controller);

    expect(find.text('EMOJI'), findsOneWidget);
    expect(find.text('STICKERS'), findsOneWidget);
    expect(find.text('SOUNDS'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('guild-expressions-upload-emoji')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('guild-expressions-upload-sticker')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('guild-expressions-upload-sound')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('guild-expressions-emoji-empty')),
      findsOneWidget,
    );
    expect(controller.emoji, isEmpty);
  });

  testWidgets(
    'an emoji upload goes through the picker, the name and the route',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = FakeExpressionRepository();
      final controller = _controller(repository);
      addTearDown(controller.dispose);
      final picker = _StubFilePicker([_png('spark.png')]);
      await _pump(tester, controller, picker: picker);

      await tester.tap(
        find.byKey(const ValueKey('guild-expressions-upload-emoji')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('guild-expression-name-field')),
        'forge_spark',
      );
      await tester.tap(
        find.byKey(const ValueKey('guild-expression-name-confirm')),
      );
      await tester.pumpAndSettle();

      expect(repository.uploads.single.name, 'forge_spark');
      expect(repository.uploads.single.dataUri, startsWith('data:image/png'));
      expect(
        find.byKey(const ValueKey('guild-expression-emoji-emoji-0')),
        findsOneWidget,
      );
      expect(find.text(':forge_spark:'), findsOneWidget);
    },
  );

  testWidgets('a delete button removes the row', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = FakeExpressionRepository()
      ..emojiByGuild[guildId] = [
        const GuildEmoji(id: 'e1', spaceId: guildId, name: 'spark'),
      ];
    final controller = _controller(repository);
    addTearDown(controller.dispose);
    await controller.openSection(GuildSettingsSection.expressions);
    await _pump(tester, controller);
    expect(find.text(':spark:'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('guild-expression-emoji-delete-e1')),
    );
    await tester.pumpAndSettle();

    expect(repository.deletes.single, (kind: 'emoji', id: 'e1'));
    expect(find.text(':spark:'), findsNothing);
    expect(
      find.byKey(const ValueKey('guild-expressions-emoji-empty')),
      findsOneWidget,
    );
  });

  testWidgets('an oversized file is refused before anything is sent', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = FakeExpressionRepository();
    final controller = _controller(repository);
    addTearDown(controller.dispose);

    await _pump(tester, controller, picker: _RefusingPicker());
    await tester.tap(
      find.byKey(const ValueKey('guild-expressions-upload-emoji')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Emoji images must be under 256 KB.'), findsOneWidget);
    expect(repository.calls, isEmpty);
    expect(repository.uploads, isEmpty);
  });

  testWidgets('a limit refusal is said in the banner', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = FakeExpressionRepository(
      refuseNextUpload: GuildExpressionKind.emoji,
    );
    final controller = _controller(repository);
    addTearDown(controller.dispose);
    final picker = _StubFilePicker([_png('spark.png')]);
    await _pump(tester, controller, picker: picker);

    await tester.tap(
      find.byKey(const ValueKey('guild-expressions-upload-emoji')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('guild-expression-name-field')),
      'one_too_many',
    );
    await tester.tap(
      find.byKey(const ValueKey('guild-expression-name-confirm')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('guild-settings-action-error')),
      findsOneWidget,
    );
    expect(find.text('This server has no emoji slots left.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('guild-expressions-emoji-empty')),
      findsOneWidget,
    );
  });
}

final class _RefusingPicker implements ExpressionFilePicker {
  @override
  Future<ExpressionFileSelection?> pick(ExpressionKind kind) async =>
      throw const ExpressionFileRejected(
        ExpressionFileRejection.tooLarge,
        ExpressionKind.emoji,
      );
}

GuildSettingsController _controller(FakeExpressionRepository repository) =>
    GuildSettingsController(
      FakeGuildManagementRepository(),
      WorkspacePermissions(
        guildWorkspace(),
        memberId: moderatorId,
      ).administrationOf(guildId),
      guildId: guildId,
      expressions: repository,
    );

/// Hosts the page the way the settings window does: listening to the
/// controller, so a finished upload or delete repaints the rows.
Future<void> _pump(
  WidgetTester tester,
  GuildSettingsController controller, {
  ExpressionFilePicker? picker,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: ListenableBuilder(
        listenable: controller,
        builder: (_, _) => GuildSettingsExpressionsSection(
          controller: controller,
          filePicker: picker ?? const NativeExpressionFilePicker(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
