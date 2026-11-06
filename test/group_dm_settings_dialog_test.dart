import 'package:flucord/src/domain/chat_models.dart';
import 'package:flucord/src/presentation/profile_image_picker.dart';
import 'package:flucord/src/presentation/widgets/group_direct_message_settings_dialog.dart';
import 'package:flucord/src/theme/flucord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _group = ConversationChannel(
  id: '400000000000000031',
  spaceId: CommunitySpace.directMessagesId,
  name: 'Raid night',
  topic: '',
  kind: ChannelKind.text,
  isGroupDirectMessage: true,
);

final class _Picker implements ProfileImagePicker {
  const _Picker(this._answer);

  final Future<ProfileImageSelection?> Function() _answer;

  @override
  Future<ProfileImageSelection?> pick() => _answer();
}

/// Opens the dialog for [_group] and answers the icons it was asked to set.
Future<List<String?>> _pumpDialog(
  WidgetTester tester,
  ProfileImagePicker picker,
) async {
  final icons = <String?>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: FlucordTheme.dark,
      home: Scaffold(
        body: GroupDirectMessageSettingsDialog(
          channel: _group,
          recipients: const [],
          isOwner: true,
          onRename: (_) async => true,
          onSetIcon: (dataUri) async {
            icons.add(dataUri);
            return true;
          },
          onRemove: (_) async => true,
          imagePicker: picker,
        ),
      ),
    ),
  );
  return icons;
}

void main() {
  testWidgets('a picked image becomes the group icon', (tester) async {
    final icons = await _pumpDialog(
      tester,
      _Picker(
        () async => const ProfileImageSelection(
          name: 'icon.png',
          dataUri: 'data:image/png;base64,iVBORw0K',
          byteCount: 8,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('group-dm-change-icon')));
    await tester.pumpAndSettle();

    expect(icons, ['data:image/png;base64,iVBORw0K']);
  });

  testWidgets('a file that is not an image says why and changes nothing', (
    tester,
  ) async {
    final icons = await _pumpDialog(
      tester,
      _Picker(
        () async => throw const ProfileImageRejected(
          ProfileImageRejection.unsupportedFormat,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('group-dm-change-icon')));
    await tester.pumpAndSettle();

    expect(icons, isEmpty);
    expect(find.text('Choose a PNG, JPEG, GIF or WebP image.'), findsOneWidget);
  });
}
