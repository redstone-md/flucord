# Triage Labels

The skills speak in terms of five canonical triage roles. This file maps those roles to what the `FLUCORD` project in itsaplan really has. The project has one triage label: `ready-for-agent`.

| Role in mattpocock/skills | In our tracker                                                       | Meaning                                  |
| ------------------------- | -------------------------------------------------------------------- | ---------------------------------------- |
| `needs-triage`            | No label. An issue with no triage label waits for triage.            | Maintainer needs to evaluate this issue  |
| `needs-info`              | No label. Ask the question in a comment.                             | Waiting on reporter for more information |
| `ready-for-agent`         | The label `ready-for-agent`                                          | Fully specified, ready for an AFK agent  |
| `ready-for-human`         | No label. Assign the issue to a person.                              | Requires human implementation            |
| `wontfix`                 | No label. Say why in a comment, then move it to a `canceled` column. | Will not be actioned                     |

When a skill mentions a role (e.g. "apply the AFK-ready triage label"), do what this table says for that role. Do not create a label to fill a gap unless a person asks for it.

`labels` in `get_project` is the source of truth, and its ids are what `labelIds` takes. If the project's labels change, update this table. See `docs/agents/issue-tracker.md` for the operations.
