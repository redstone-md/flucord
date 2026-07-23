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

1. Persisted SQLite cache and authenticated backend transport.
2. Attachments, replies, reactions, edits, and threads.
3. Notifications, tray integration, deep links, and auto-update.
4. Voice rooms, device selection, screen sharing, and media diagnostics.
5. macOS and Linux packaging after Windows behavior stabilizes.

## Non-goals for the tracer bullet

- Calling Discord's undocumented user endpoints.
- Voice, video, screen sharing, or overlay support.
- Production authentication and credential storage.
