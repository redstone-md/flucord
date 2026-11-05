#ifndef RUNNER_START_MENU_SHORTCUT_H_
#define RUNNER_START_MENU_SHORTCUT_H_

// Points the notification plugin's Start Menu shortcut at this executable.
//
// local_notifier (WinToast) owns
// %APPDATA%\Microsoft\Windows\Start Menu\Programs\<app_name>.lnk and ties it
// to the AppUserModelID <app_name>. Windows draws the taskbar button from that
// shortcut, but WinToast checks only the ID, never the target. A shortcut left
// by a build that is gone therefore gives the taskbar a generic icon.
//
// Call once on start, with COM initialized and before the plugin runs. A
// shortcut that is missing is left for WinToast to create.
void RepairStartMenuShortcut(const wchar_t* app_name);

#endif  // RUNNER_START_MENU_SHORTCUT_H_
