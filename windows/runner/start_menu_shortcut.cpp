#include "start_menu_shortcut.h"

#include <windows.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <wrl/client.h>

#include <string>

using Microsoft::WRL::ComPtr;

namespace {

// The same path WinToast builds in defaultShellLinkPath.
std::wstring ShortcutPath(const wchar_t* app_name) {
  wchar_t app_data[MAX_PATH];
  const DWORD length =
      ::GetEnvironmentVariableW(L"APPDATA", app_data, MAX_PATH);
  if (length == 0 || length >= MAX_PATH) {
    return {};
  }
  return std::wstring(app_data) +
         L"\\Microsoft\\Windows\\Start Menu\\Programs\\" + app_name + L".lnk";
}

}  // namespace

void RepairStartMenuShortcut(const wchar_t* app_name) {
  const std::wstring shortcut = ShortcutPath(app_name);
  if (shortcut.empty() ||
      ::GetFileAttributesW(shortcut.c_str()) == INVALID_FILE_ATTRIBUTES) {
    return;
  }

  wchar_t executable[MAX_PATH];
  const DWORD length = ::GetModuleFileNameW(nullptr, executable, MAX_PATH);
  if (length == 0 || length >= MAX_PATH) {
    return;
  }

  ComPtr<IShellLinkW> link;
  ComPtr<IPersistFile> file;
  if (FAILED(::CoCreateInstance(CLSID_ShellLink, nullptr,
                                CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&link))) ||
      FAILED(link.As(&file)) ||
      FAILED(file->Load(shortcut.c_str(), STGM_READWRITE))) {
    return;
  }

  // Reading the target is cheap; the file is written only when it is wrong.
  wchar_t target[MAX_PATH] = L"";
  if (link->GetPath(target, MAX_PATH, nullptr, 0) == S_OK &&
      ::CompareStringOrdinal(target, -1, executable, -1, TRUE) == CSTR_EQUAL) {
    return;
  }

  std::wstring directory(executable);
  directory.resize(directory.find_last_of(L'\\'));
  if (FAILED(link->SetPath(executable)) ||
      FAILED(link->SetWorkingDirectory(directory.c_str())) ||
      FAILED(link->SetIconLocation(executable, 0)) ||
      FAILED(file->Save(shortcut.c_str(), TRUE))) {
    return;
  }
  // Tells the shell to drop what it cached for the old target.
  ::SHChangeNotify(SHCNE_UPDATEITEM, SHCNF_PATHW, shortcut.c_str(), nullptr);
}
