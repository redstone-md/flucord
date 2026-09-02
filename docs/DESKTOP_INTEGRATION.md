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

The native tray lifecycle runs on all three desktop platforms. Its Open item
and tooltip/menu label reflect the local unread-channel count, and Quit performs
deterministic teardown. Window close hides only after tray creation succeeds;
if initialization fails, normal close remains available. Linux requires an
AppIndicator package and, on GNOME, its corresponding shell extension.

Automatic updates are disabled unless a release is built with an HTTPS
WinSparkle appcast:

```powershell
flutter build windows --release `
  --dart-define=FLUCORD_UPDATE_FEED_URL=https://updates.example.com/appcast.xml
```

The checked-in `dsa_pub.pem` verifies Windows update signatures. The matching
`dsa_priv.pem` is ignored by Git and must be backed up as a release secret. Sign
each installer before adding its signature to the appcast:

```powershell
dart run auto_updater:sign_update .\build\distribution\flucord-windows-x64-setup-v0.0.8.exe
```

The installer is the release workflow's Inno Setup build of
`windows/installer/flucord.iss`; WinSparkle runs it with `/VERYSILENT`, which
the script accepts.
