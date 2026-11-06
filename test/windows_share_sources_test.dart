import 'package:flucord/src/data/video/windows_share_sources.dart';
import 'package:flutter_test/flutter_test.dart';

/// An ordinary application window, the kind Alt+Tab lists.
const _editor = WindowFacts(
  title: 'notes.txt - Editor',
  className: 'Notepad',
  isVisible: true,
  isMinimized: false,
  isCloaked: false,
  isToolWindow: false,
  isAppWindow: false,
  hasOwner: false,
  isOwnProcess: false,
  width: 800,
  height: 600,
);

WindowFacts _editorWith({
  String? title,
  String? className,
  bool? isVisible,
  bool? isMinimized,
  bool? isCloaked,
  bool? isToolWindow,
  bool? isAppWindow,
  bool? hasOwner,
  bool? isOwnProcess,
  int? width,
}) => WindowFacts(
  title: title ?? _editor.title,
  className: className ?? _editor.className,
  isVisible: isVisible ?? _editor.isVisible,
  isMinimized: isMinimized ?? _editor.isMinimized,
  isCloaked: isCloaked ?? _editor.isCloaked,
  isToolWindow: isToolWindow ?? _editor.isToolWindow,
  isAppWindow: isAppWindow ?? _editor.isAppWindow,
  hasOwner: hasOwner ?? _editor.hasOwner,
  isOwnProcess: isOwnProcess ?? _editor.isOwnProcess,
  width: width ?? _editor.width,
  height: _editor.height,
);

void main() {
  test('an ordinary application window can be shared', () {
    expect(_editor.isShareable, isTrue);
  });

  test('what Alt+Tab hides is not offered', () {
    // Hidden, minimized, on another virtual desktop (cloaked), untitled,
    // tool windows and owned pop-ups, and the desktop itself.
    expect(_editorWith(isVisible: false).isShareable, isFalse);
    expect(_editorWith(isMinimized: true).isShareable, isFalse);
    expect(_editorWith(isCloaked: true).isShareable, isFalse);
    expect(_editorWith(title: '  ').isShareable, isFalse);
    expect(_editorWith(isToolWindow: true).isShareable, isFalse);
    expect(_editorWith(hasOwner: true).isShareable, isFalse);
    expect(_editorWith(className: 'Progman').isShareable, isFalse);
    expect(_editorWith(width: 0).isShareable, isFalse);
  });

  test('a window that asks for the task bar is offered even when owned', () {
    expect(
      _editorWith(
        hasOwner: true,
        isToolWindow: true,
        isAppWindow: true,
      ).isShareable,
      isTrue,
    );
  });

  test('this client is never offered as a source', () {
    expect(_editorWith(isOwnProcess: true).isShareable, isFalse);
  });
}
