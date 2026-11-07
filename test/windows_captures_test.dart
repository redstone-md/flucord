import 'package:flucord/src/data/video/windows_captures.dart';
import 'package:flutter_test/flutter_test.dart';

/// An ordinary application window, the kind Alt+Tab lists.
const _editor = WindowFacts(
  title: 'notes.txt - Editor',
  className: 'Notepad',
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
    expect(_editor.isCapturable, isTrue);
  });

  test('what Alt+Tab hides is not offered', () {
    // Minimized, on another virtual desktop (cloaked), untitled, tool
    // windows and owned pop-ups, and the desktop itself.
    expect(_editorWith(isMinimized: true).isCapturable, isFalse);
    expect(_editorWith(isCloaked: true).isCapturable, isFalse);
    expect(_editorWith(title: '  ').isCapturable, isFalse);
    expect(_editorWith(isToolWindow: true).isCapturable, isFalse);
    expect(_editorWith(hasOwner: true).isCapturable, isFalse);
    expect(_editorWith(className: 'Progman').isCapturable, isFalse);
    expect(_editorWith(width: 0).isCapturable, isFalse);
  });

  test('a window that asks for the task bar is offered even when owned', () {
    expect(
      _editorWith(
        hasOwner: true,
        isToolWindow: true,
        isAppWindow: true,
      ).isCapturable,
      isTrue,
    );
  });

  test('this client is never offered as a source', () {
    expect(_editorWith(isOwnProcess: true).isCapturable, isFalse);
  });
}
