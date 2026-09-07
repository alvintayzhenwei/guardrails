# Security

This repository is a safety tool, so it owes you a clear account of what it
defends against, what it deliberately does not, and how you can check both
claims yourself without taking anyone's word for it.

> [!IMPORTANT]
> **This document is an engineering account, not a warranty.** Nothing in it —
> including the threat-model table below — is a guarantee that any particular
> command will be stopped, and none of it is legal, security, or compliance
> advice. The software is provided "as is" with no warranty and no liability
> under the [MIT License](LICENSE); see [DISCLAIMER.md](DISCLAIMER.md) for the
> full terms. The "in scope" column describes what the checks are *designed* to
> refuse, not what they are guaranteed to refuse.

## Reporting a vulnerability

Report privately through GitHub: **Security → Advisories → Report a
vulnerability** on this repository. That opens a private thread visible only to
the maintainers.

Please do not open a public issue for a guard bypass. A bypass in a tool people
rely on is worth a quiet fix first.

What helps most in a report:

- the exact `HOOK_COMMAND` or file path that got through
- which check should have caught it
- the platform and `bash --version`

Expect an acknowledgement within a week. There is no bounty; credit in the
release notes is offered unless you would rather not be named.

## What this tool is

A set of Claude Code hooks that inspect a tool call **before** it runs and
refuse the destructive ones. It exists to stop an agent from making an
expensive mistake at speed.

It is a **guardrail, not a sandbox, and not access control.** The distinction
matters for every claim below.

## Threat model

**In scope — what the checks are designed to refuse (designed to, not guaranteed
to; see [DISCLAIMER.md](DISCLAIMER.md)):**

| Threat | Defence |
|---|---|
| Agent runs a recursive force-delete | `check-rm-rf` — short, combined, uppercase, GNU long and PowerShell/CMD alias spellings, plus `find -delete` |
| Agent pushes to a protected branch | `check-dangerous-git` blocks the agent; `git-hooks/pre-push` blocks the git client itself |
| Agent discards uncommitted work | `check-dangerous-git` — `reset --hard`, `clean -f`, `checkout .`, `restore`, `stash drop/clear`, `reflog expire` |
| Agent runs unscoped destructive SQL | `check-production-guard` — including tautological `WHERE 1=1`, multi-line SQL and comment-faked scope |
| Agent writes a credential into source | `check-secrets-write` — assignment literals plus AWS/GitHub/Slack/Google/Stripe/GitLab/npm/OpenAI/Anthropic token formats |
| Agent writes to a key or env file | `check-sensitive-files` — matched case-insensitively, because macOS and Windows filesystems are |
| A new write-shaped tool appears | The dispatcher routes `*Edit`/`*Write` by glob, so an unfamiliar mutating tool is guarded by default rather than silently unguarded |
| An external MCP call leaves the machine unreviewed | `check-mcp-guardrail` surfaces the outbound payload for consent |

**Out of scope — the tool does not claim to stop these:**

1. **A determined human.** Every block is advisory to you. `git push
   --no-verify`, running the command in your own terminal, or deleting the hook
   all work. That is the design: guardrails restrain the agent, not its
   operator.
2. **Values the shell only resolves at run time.** A static text guard reads the
   command string, not the process the shell will build from it. Flags held in a
   variable (`RF="-rf"; rm $RF /x`), strings assembled at run time, and
   base64-piped-to-`sh` all get past it. These cases are pinned as explicit
   non-goals in section G of `run-vuln-tests.sh` so the behaviour is recorded
   rather than assumed.
3. **A malicious agent rather than a careless one.** The threat model is a
   capable agent making a mistake. An agent actively trying to defeat the guard
   has the whole of item 2 available.
4. **A compromised guardrail source.** `run-hooks.sh` can auto-clone the library
   from `$CLAUDE_GUARDRAILS_REPO`. If you do not control that remote, you are
   trusting whoever does. Fork it and repoint the variable — see
   [Configuration](README.md#configuration).
5. **Availability.** The loader **fails open**: if the library cannot be
   resolved it exits `0` with a warning rather than blocking your session. A
   broken install therefore means *no protection*, not *no work*. This is a
   deliberate trade and the reason the `.claude/hooks/run-hooks.sh` bootstrap is
   the one file you vendor and commit.

## Verify it yourself

Nothing here needs to be taken on trust. Both suites run offline in seconds:

```bash
bash run-tests.sh        # 95 assertions  — do the guards fire as documented?
bash run-vuln-tests.sh   # 149 assertions — can the same effect get past them?
```

`run-vuln-tests.sh` is the adversarial suite. Every case in it is an evasion
attempt: flag obfuscation, binary indirection, command chaining, alias
substitution, case tricks, tautological SQL, exemption abuse and tool-name
evasion. A case that expects exit `0` is a documented non-goal from the list
above, pinned so that a silent change in behaviour shows up as a failure.

The suite was written against the guards as they stood and initially found **65
successful evasions**, all of which are now closed. It also found three cases
where the guards blocked *legitimate* commands — `git branch -d` on a merged
branch, `grep "DROP TABLE"`, and writing `.env.example` — which are fixed too,
because a guard that cries wolf gets switched off.

## Supported versions

The `main` branch is the supported version. Machines using the per-user cache
pick up fixes on the next session after the cache TTL expires (24h by default);
`CLAUDE_GUARDRAILS_TTL=0` forces a refresh immediately.
