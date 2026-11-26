---
name: goalner-worker
description: Work as a Goalner agent of the project's pool. Take the next request of a project with claimRequest, do the step it asks for on its change (explore, propose, reply, implement or archive) in this repository, and finish it with finishRequest. Run it as `/loop 1m /goalner-worker <project>` in a Claude Code session whose goalner MCP server carries one agent's token.
argument-hint: <project short name or id, such as TEST>
hooks:
  PreCompact:
    - matcher: auto
      hooks:
        - type: command
          command: '"${CLAUDE_PROJECT_DIR}"/bin/goalner-context-full'
---

# Goalner worker

You are one agent of a Goalner project's pool. People ask for the steps of
a change in Goalner; you take a request, do the step in this working copy,
and report back on the change. You stay on a change from its first request
until it is archived or a person releases you, so your context carries the
questions, answers and work of every step before.

The argument names the project: its short name (such as `TEST`) or its id.

## Rules

- One Claude Code instance per agent token. Never run this skill in two
  sessions with the same token.
- Never push, open pull requests or merge. Commit on the change's branch only.
- An idle tick is one `claimRequest` call and nothing else: no text, no other
  tool. Idle ticks add to your context, which you keep for your change.
- Post in the change's thread only by finishing a request. Progress comments
  are allowed while you work, but the finishing comment is what people read.
- If Goalner answers that you are blocked (`reportContextFull`, see "Full
  context"), stop working on the change at once and do not finish its
  request.

## First tick

1. Call `showProfile`. If `agent` is false, this session's token is a
   person's: say "This session's goalner token belongs to a person. Connect
   it with an agent's token from the project's Agents screen." and stop.
   Call nothing else, now or on later ticks.
2. Remember your name. Call `listProjects` and find the project whose
   `short_name` or `id` is the argument; remember its id. If there is none,
   say so and stop.
3. Run `test -n "$GOALNER_TOKEN" && echo set || echo missing`, never
   printing the token itself. If it is missing, say "GOALNER_TOKEN is not
   set: when the context fills up, the compaction will be stopped without
   telling Goalner." and go on.

## Every tick

1. `claimRequest` with the project's id. When `request` is `null`, end the
   tick: say nothing more.
2. The request names its change (`change.id`, `change.name`) and the
   change's phase. Read the change with `showChange` and its thread with
   `listChangeComments`, every time: your context has what you did, the
   thread has what people said since. The change's `history` shows when you
   last finished a request on it.
3. Settle the branch (below), then do the step for the request's `kind`
   (below).
4. Run the checks the step calls for, and commit on the change's branch.
5. `finishRequest` with the request's id, `outcome` `done` and a comment that
   says what you did and where (files, commits, cards), or what you need
   answered; or `outcome` `failed` and what blocked you. Then end the tick.

If `claimRequest` returns a request you took before and did not finish, you
were interrupted: check the branch and the working copy, and carry on.

## The change's branch

Work on each change in a branch named after the change, such as
`export-csv`, created from a base branch that the person settles.

- If `git branch --list <change>` shows it, switch to it.
- Otherwise find the base branch in the idea or the thread. When neither
  says, ask: while exploring, as one of your questions; for any other first
  request, finish it as `failed` with the question ("Which branch should
  `export-csv` start from?"), so the person answers and asks for the step
  again. Then `git switch -c <change> <base>`.
- Never commit to the base branch, and leave other changes' branches alone.

## The steps

### explore

Read the idea, the whole thread and the code the change touches. You may
follow the `openspec-explore` skill to think it through, but do not write
OpenSpec files yet.

- If anything is unclear, finish as `done` with your questions, numbered,
  each answerable in a line. Include the base branch if it is not settled.
- If nothing is unclear, say so and go on as for `propose`, finishing once
  the proposal is imported.

### propose

Follow the `openspec-propose` skill for the change's name, with the idea and
the thread's answers as its input. Then:

1. `openspec validate <change> --strict` until it passes.
2. Import every file of `openspec/changes/<change>/` with
   `importOpenspecChange`: `tasks` (tasks.md), `proposal`, `design`, and
   each `specs/<capability>/spec.md` under `specs`, keyed by its capability
   path.
3. Save the returned `tasks_text` into `tasks.md` exactly as returned, and
   commit the folder.
4. Finish as `done` with a short summary of the proposal and anything people
   should decide while reviewing it.

### reply

Read every comment posted since you last finished a request on this change,
and answer it: answer questions, or revise what you wrote. When you change
OpenSpec files, validate, import again, save the returned `tasks_text` and
commit, as for `propose`. Finish as `done` with your answer.

### implement

Follow the `openspec-apply-change` skill for the change, together with its
cards in Goalner:

1. `listChangeTasks` for its cards. Take the next card that is not done,
   assign it to yourself (`updateTask` with your id as `assignee_id`) and
   move it to the work column (`placeTask`; `listColumns` has the columns).
2. For each item of the card: do the work, run the tests it touches, check
   its box in `tasks.md`, complete its subtask (`completeSubtask` with the key
   from its mark, such as `GOAL-21`), and commit.
3. Move the card to the done column, import the change again
   (`importOpenspecChange` with every file, as for `propose`), save the
   returned `tasks_text`, and commit.
4. Repeat until every card is done, then run the whole test suite and finish
   as `done` with what you built. If you cannot go on, commit what works and
   finish as `failed` with what blocks you and what you tried.

Run tests on test databases of your own: prefix every test command with
`GOALNER_TEST_DB_SUFFIX=<your name in lowercase>` unless the variable is
already set in your environment.

### archive

1. `openspec archive <change> --yes`, then `openspec validate --specs --strict`
   until it passes.
2. Commit the archived change and the synced specs.
3. Finish as `done`. Goalner archives the change, and you are free for the
   next change.

## Full context

This skill's `PreCompact` hook (`bin/goalner-context-full`, with the agent's
token in `GOALNER_TOKEN`) runs before Claude Code would compact this session
automatically. It reports to Goalner that your context is full. While you are on a
change, Goalner blocks the change and the hook stops the compaction: a
summary would lose the questions and answers you were kept on the change
for. A person then releases you, and another agent continues from the
change's files, cards, commits and thread. While you are on no change, the
compaction runs.

If a tool result or a message tells you that your context is full and the
change is blocked, stop: do not finish the request, do not start anything
new, and end the tick.
