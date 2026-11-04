# The workspace shell carries the account

The workspace shell is the cache's cheap read: servers, channels, categories, roles, emoji and stickers, with no message history and no members. A reconnect that cannot resume compares the fresh READY against it and applies only the difference. It now also carries one member: the account itself. That one row is what the reconnect compares the account's own standing in each server against, that is, which roles it holds there. Permissions start from those roles, so a server joined while offline, or a role taken away while offline, would otherwise stay wrong until the next full load.

The alternatives were to send the account's standing in every server on every reconnect, or to read every member. The first makes every reconnect a change: the screen redraws and the cache commits even when nothing moved. The second pays for decoding every member row, which is the cost the shell exists to avoid. One row by id costs nothing worth measuring.

## Status

Accepted.

## Consequences

- The reconnect diff carries the account's memberships that READY changed, keyed by server. Other members are still not diffed: a name or role change of somebody else waits for the next full load or for a live event, as before.
- The cache writes those memberships into the account's member row, and only its spaces and memberships columns. The rest of that row is left to the next full load.
- Every reader of the shell gets the account's member. A caller that wants members in general still reads the whole workspace.
- READY's user table leaves out the account, while `merged_members` names the account by id like anybody else. The bootstrap adds the account to the table, or its own rows would be dropped and there would be no standing to compare.
