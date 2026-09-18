# Working constraints

These are constraints, not preferences. They are not suggestions to weigh against
other considerations. Violating one is an error, the same as a failing test.

## 1. No meta-commentary outside direct conversation

Meta-commentary is any statement about the work's own history, process, or
authorship. It belongs in conversation with the user and nowhere else — not in
code, not in comments, not in documents, not in commit messages.

Never write:

- "This resolves what was previously open."
- "Previously this used X; it now uses Y."
- "As noted earlier / see above / this section explains why this document exists."
- "Corrected from the earlier draft."
- `# This used to return a tuple but was changed`
- A section whose subject is the document rather than the subject matter.

A document states what is true. A comment states what the code does or why it
must do it. Neither narrates how it came to be written. If the history matters
to the reader, it is in version control.

Writing the rule is not the same as following it. Before finishing any file,
re-read it for sentences whose subject is the document, the code, or a previous
version of either.

## 2. No output-filtering shell commands

Enforced by `.claude/hooks/block-filter-pipes.py`. Blocked in Bash: `grep`,
`head`, `tail`, `sed`, `awk`, `cut`, `sort`, `uniq`, `tr`, `column`, `less`,
`more`, `fold`, `nl`, `rg`, `ag`, `ack`.

They discard or buffer output before it is seen, which hides the part that
mattered. Instead:

- Run the command and read all of its output.
- Capture large output: `<command> | tee /tmp/out.txt`, then Read the file.
  `tee` is allowed because it preserves the stream and the file can be re-read
  without re-running the command.
- Search files with the Grep and Glob tools.
- Read part of a file with Read's `offset` and `limit`.

## 3. Everything runs in a container

`mix` is not run on the host. Dependencies and build artifacts live in named
Docker volumes compiled against the image's OTP, and the database is reachable
only on the compose network. A host-side `mix` command will fail to resolve the
hostname `db`, which is the intended behaviour.

    docker compose up -d                      # start db + app
    docker compose run --rm app mix test      # or any other mix task
    docker compose run --rm app mix precommit # the full gate
    docker compose logs -f app                # server output

The host publishes one port: **4100**, mapped to Phoenix's 4000 inside the
container. Postgres is not published at all. Both defaults were already taken
on this machine — 4000 by `homelab-iab`, 5432 by the homelab Postgres — and
nothing in that stack may be disturbed.

Source is bind-mounted, so edits on the host reload in the running container
without a restart.

## 4. Errors surface. Nothing is hidden from the user.

There are no other clients, servers, or consuming systems. Nothing depends on
this that must be kept from falling over. Errors are how the system is
understood, so they must reach the user intact.

Never write:

- A `rescue`, `catch`, or `try` that returns a default in place of the error.
- A catch-all clause that swallows an unmatched value.
- A retry that hides a persistent failure behind eventual success.
- A fallback path taken silently when the intended path fails.
- "For backwards compatibility" — there is nothing to be compatible with.
- A default value substituted for data that should have been present.

Let it raise. Let it crash. A loud failure in the right place is worth more
than a quiet success in the wrong one.

This is not a licence to skip error handling that the user asked for, and it
does not apply to conditions that are genuinely expected and specified — a
missing optional file, a deliberately nullable field. The distinction is
whether the condition is part of the design or a surprise. Surprises surface.

## 5. Do not assume. Verify, or say you did not.

- Do not state a fact about a package, a version, an API, or a file without
  having read it in this session. Read it.
- Do not report a claim as unverified when verifying it is available. Verify it.
- Do not report work as complete when part of it was skipped. Say what was
  skipped and why.
- Do not describe a result you have not seen, including from a subagent.
- When two sources disagree, resolve it directly rather than reporting the
  disagreement.

## 6. Scope

Do what was asked. Ask when a choice would materially change the work and the
answer is not inferable. Do not widen scope, and do not narrow it silently — if
part of the work is blocked, complete the rest and say plainly what was left.
