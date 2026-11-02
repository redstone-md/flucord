# Issue tracker: itsaplan

Issues and specs for this repo live in itsaplan, in the project with the key `FLUCORD`. Use the `mcp__itsaplan__*` tools for all operations. This doc uses the short names, so `create_issue` means `mcp__itsaplan__create_issue`.

## Ids

An issue has two numbers, and they differ:

- **Identifier**: `FLUCORD-42`. People write this one. The `42` is the `sequenceNumber`.
- **Numeric id**: the `id` field in the result of `get_issue_by_number`. Most tools take this one, as `issueId`, `parentId` or `targetIssueId`.

Get all other ids from `get_project` with `projectKey: "FLUCORD"`: columns, issue types, labels and members. Ids belong to one project, so never reuse them from another project and never hardcode them.

Pick a column by its `stateType`, never by its name. The state types are `backlog`, `unstarted`, `started`, `completed` and `canceled`. An issue is **open** while its column is not `completed` or `canceled`.

## Conventions

- **Create an issue**: `create_issue` with `projectKey`, `title`, `columnId` and `description`. Add `labelIds` and `typeId` when they apply.
- **Read an issue**: `get_issue_by_number` with `projectKey` and `sequenceNumber`. This gives the body, labels, links, parent and subtasks, but no comments. Read the comments with `list_issue_activity`, with `issueId` and `filter: "comments"`.
- **List issues**: `list_issues` with `projectKey` and field filters such as `columnId`, `labelIds`, `assigneeUserId` or `parentId`. Results come most recently updated first, 50 by default and 500 at most. There is no filter for open or closed, so compare each `columnId` with the columns from `get_project`. The rows have no body and no links. To search by text, use `search_issues` with `projectKey` and `q`.
- **Comment on an issue**: `add_comment` with `issueId` and `body`. To answer a comment, add its id as `replyToId`.
- **Close an issue**: `update_issue` with `issueId` and the `columnId` of a `completed` column. Use a `canceled` column if the work will not be done. If the close needs an explanation, call `add_comment` first.
- **Apply or remove labels**: `update_issue` with `labelIds`. This replaces the whole list, so send the labels the issue already has as well.
- **Set a parent**: `parentId` on `create_issue` or `update_issue`, with the parent's numeric id. Send `null` to detach. The parent must be in the same project and must not be a subtask itself, and an issue with subtasks cannot become one. So there is only one level of nesting. List the children with `list_issues` and `parentId`.
- **Set a blocker**: `link_issues` with `issueId` set to the blocker, `targetIssueId` set to the blocked issue, and `kind: "blocks"`. Both issues must be in the same project. Remove the edge with `unlink_issues`, with `issueId` and the link's `id` as `linkId`.
- **Read blockers**: `get_issue_by_number` or `get_issue`, then look at `links`. The blockers of an issue are the links with `kind: "blocks"` and `direction: "inward"`. The issues it blocks have `direction: "outward"`. An issue is unblocked when the `columnId` of every blocker is `completed` or `canceled`.

In text, refer to an issue as `FLUCORD-42`, not `#42`.

If a tool refuses the bare key because several teams use it, pass the project's `ref` from `list_projects` instead.

## Pull requests as a triage surface

**PRs as a request surface: no.** _(Set to `yes` if this repo treats external PRs as feature requests; `/triage` reads this flag.)_

Code and pull requests stay on GitHub, so itsaplan tools do not reach them. When the flag is `yes`, PRs use the `gh pr` commands and GitHub's own labels:

- **Read a PR**: `gh pr view <number> --comments` and `gh pr diff <number>` for the diff.
- **List external PRs for triage**: `gh pr list --state open --json number,title,body,labels,author,authorAssociation,comments` then keep only `authorAssociation` of `CONTRIBUTOR`, `FIRST_TIME_CONTRIBUTOR`, or `NONE` (drop `OWNER`/`MEMBER`/`COLLABORATOR`).
- **Comment / label / close**: `gh pr comment`, `gh pr edit --add-label`/`--remove-label`, `gh pr close`.

A bare `#42` is a PR. An issue always has the form `FLUCORD-42`.

## When a skill says "publish to the issue tracker"

Create an itsaplan issue in the project `FLUCORD`.

## When a skill says "fetch the relevant ticket"

Read it as in **Read an issue** above.

## Wayfinding operations

Used by `/wayfinder`. The **map** is a single issue, and its **tickets** are its subtasks.

The `wayfinder:` labels are not in the project yet. Before the first use, check `labels` in `get_project`, and call `create_label` with `projectKey` and `name` for each one that is missing.

- **Map**: an issue with the label `wayfinder:map` and no parent, holding the map body. Create it as in **Create an issue**.
- **Child ticket**: an issue with `parentId` set to the map's numeric id. Labels: `wayfinder:<type>` (`research`, `prototype`, `grilling` or `task`). Once claimed, the ticket is assigned to the driving dev. A ticket cannot have its own subtasks.
- **Blocking**: see **Set a blocker** and **Read blockers** above. This is the tracker's native relation, so no line in the body is needed.
- **Frontier query**: `list_issues` with `parentId` set to the map's numeric id and `limit: 500`. Keep the open rows with no `assigneeUserId` and no `delegateUserId`. For each one that is left, read its blockers and drop it if any blocker is open. Map order is the lowest `sequenceNumber` first, so that one wins.
- **Claim**: `update_issue` with `assigneeUserId` set to `user.id` from `get_current_user`, and the `columnId` of a `started` column. This is the session's first write.
- **Resolve**: `add_comment` with the answer, then close the ticket as in **Close an issue**, then add a line with the gist to the map's Decisions so far. `update_issue` replaces the whole `description`, so read the map again just before you write and send its full body with the new line.
- **Links**: the tool results give no issue URL. Where the skill asks for a link, write the name and the identifier: `Ticket title (FLUCORD-42)`.
