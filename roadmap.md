# Flucord Roadmap

## Product intent

Flucord is a native Flutter desktop messaging client. The first tracer bullet
targets Windows and proves the core navigation and messaging loop without a
browser runtime or dependency on Discord's private user API.

## Architecture constraints

- Keep every source file below 500 lines.
- Keep remote/server state behind an asynchronous repository contract.
- Keep synchronous workspace state in a separate controller.
- Keep domain models independent from Flutter widgets.
- Keep the initial transport deterministic and local so the UI and tests do not
  depend on network access.
- Add real transports as repository implementations, not widget changes.

## Tracer bullet

- Native Windows Flutter runner.
- Server and channel navigation.
- Searchable message history.
- Message composition and local sending.
- Member presence panel.
- Light and dark themes.
- Loading, empty, and error states.
- Unit and widget coverage for the primary interaction loop.

## Later increments

1. Completed: persisted SQLite cache, secure bot credentials, REST API v10,
   Gateway heartbeat/resume, live message create/update, and offline fallback.
2. Completed: multipart attachments, replies, reaction add/remove, inline
   edits, confirmed deletes, active thread discovery, live Gateway updates,
   and SQLite v2 migration.
3. Completed: paginated pins with the 2026 `PIN_MESSAGES` permission, guild
   member and role loading, initial/live presence, typing expiry/throttling,
   and local unread/mention state.
4. Notifications, tray integration, deep links, and auto-update.
5. Voice rooms, device selection, screen sharing, and media diagnostics.
6. macOS and Linux packaging after Windows behavior stabilizes.

## Protocol safety

- Use only documented Discord bot REST and Gateway contracts.
- Never accept personal account tokens or impersonate official client headers.
- Store bot credentials with the operating system credential vault.
- Keep rate-limit handling and Gateway reconnect behavior covered by tests.
- Add OAuth2 only for scopes explicitly supported by Discord's public API.

## Non-goals for the tracer bullet

- Calling Discord's undocumented user endpoints.
- Voice, video, screen sharing, or overlay support.

These non-goals applied to the first local tracer bullet. Private user
endpoints remain outside the product contract.
