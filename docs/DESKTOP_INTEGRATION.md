# Desktop integration

Flucord registers channel links and forwards them to the existing app instance:

```text
flucord://channels/{serverId}/{channelId}
```

The same scheme receives the state-validated OAuth callback at
`flucord://oauth/discord/callback`; channel navigation and authorization are
parsed as separate routes.

Windows dynamically registers the scheme and forwards a second invocation to
the existing native window. macOS declares `flucord` in `CFBundleURLTypes` and
uses the native plugin event path. Linux uses a unique GTK application and a
native method channel to forward later invocations to the first process.

Linux packages must install `linux/dev.flucord.app.desktop` where the desktop
environment can index it. For an executable available on `PATH`:

```bash
install -Dm644 linux/dev.flucord.app.desktop \
  ~/.local/share/applications/dev.flucord.app.desktop
xdg-mime default dev.flucord.app.desktop x-scheme-handler/flucord
update-desktop-database ~/.local/share/applications
```

Incoming messages raise native Windows, macOS, and Linux notifications while
their channel is not focused. One shared controller describes system events
and falls back to poll, sticker, attachment, or embed content for bodyless
messages. Clicking a notification restores the window and opens its channel.

On Windows, local_notifier gives the process the AppUserModelID `Flucord` and
keeps a Start Menu shortcut for it at
`%APPDATA%\Microsoft\Windows\Start Menu\Programs\Flucord.lnk`. The taskbar
button takes its icon from that shortcut, and the plugin never checks where
it points. So on every start, before Flutter runs, the runner points the
shortcut at the running exe if it points anywhere else
(`windows/runner/start_menu_shortcut.cpp`). The installer's Start Menu
shortcut carries the same ID, and the uninstaller removes both.

The native tray lifecycle runs on all three desktop platforms. Its Open item
and tooltip/menu label reflect the local unread-channel count, and Quit performs
deterministic teardown. Window close hides only after tray creation succeeds;
if initialization fails, normal close remains available. Linux requires an
AppIndicator package and, on GNOME, its corresponding shell extension.

## Windows updates

Windows builds update through WinSparkle (the `auto_updater` package). The
updater starts only when a build carries an HTTPS appcast address. Then the
tray offers **Check for updates**, and WinSparkle also checks once a day.

The release workflow (`.github/workflows/release.yml`) builds this address in:

```text
https://github.com/redstone-md/flucord/releases/latest/download/appcast.xml
```

GitHub sends that address to the `appcast.xml` asset of the latest release.
The workflow writes the appcast with `tool/write_appcast.dart`. It has one
item: the release's setup, its full pubspec version (such as `0.0.29+29`) and
its signature. WinSparkle compares that version with the exe's version, which
Flutter stamps from the same pubspec version. So a build older than the latest
release is offered the update, and the updated build is not offered it again.
WinSparkle runs the setup with no arguments, so the person sees the normal
setup wizard. The wizard closes the running Flucord and offers to start the
new one.

A build made without the address, such as a plain `flutter build windows`,
never checks for updates. To try a feed by hand:

```powershell
flutter build windows --release `
  --dart-define=FLUCORD_UPDATE_FEED_URL=https://updates.example.com/appcast.xml
```

### The signing key

WinSparkle installs an update only if its DSA signature checks out against
`dsa_pub.pem`. That file is checked in and built into the exe as the `DSAPub`
resource (`windows/runner/Runner.rc`). The private half is the repository
secret `FLUCORD_UPDATE_DSA_PRIVATE_KEY`. A person creates the pair once:

1. Make the pair with OpenSSL, in an empty folder outside the repository.
   This is what WinSparkle's own `bin/generate_keys.bat` does:

   ```powershell
   openssl dsaparam -out dsaparam.pem 4096
   openssl gendsa -out dsa_priv.pem dsaparam.pem
   openssl dsa -in dsa_priv.pem -pubout -out dsa_pub.pem
   Remove-Item dsaparam.pem
   ```

2. Commit the new `dsa_pub.pem` at the repository root.
3. Add the full text of `dsa_priv.pem` as the repository secret
   `FLUCORD_UPDATE_DSA_PRIVATE_KEY` (Settings, Secrets and variables, Actions).
4. Back up `dsa_priv.pem` somewhere safe, such as a password manager, then
   delete the loose file. Git ignores `dsa_priv.pem`; never commit it.

If the private key is lost, builds that carry the old `dsa_pub.pem` can no
longer be updated. Their users have to install a build with the new key by
hand.

The workflow signs the setup the way WinSparkle's `bin/sign_update.bat` does:
a DSA signature of the setup's SHA-1, in Base64. It checks the signature with
the checked-in `dsa_pub.pem` and stops the release if they do not match.
Without the secret the release still ships, but with a warning in the run and
no `appcast.xml`, so no installed build is offered it.

The installer is the release workflow's Inno Setup build of
`windows/installer/flucord.iss`. The script also accepts `/VERYSILENT` for an
unattended install.
