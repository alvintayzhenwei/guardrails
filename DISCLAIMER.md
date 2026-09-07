# Disclaimer

**Read this before you rely on this software for anything you cannot afford to
lose.**

## No warranty, no liability

This software is distributed under the [MIT License](LICENSE), which states in
terms that govern your use of it:

> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
> AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
> LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
> OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
> SOFTWARE.

Nothing in this repository — not the README, not the test results, not the CI
badges, not the threat model in [SECURITY.md](SECURITY.md) — creates a warranty,
a guarantee, a service-level commitment, or a duty of care of any kind. By
installing or using this software you accept that the entire risk of doing so is
yours.

## This is one layer, not a solution

This project is a set of pattern-matching hooks. It reads the text of a tool
call and refuses the ones matching the patterns it knows about. That is the
whole of what it does.

It is **not**:

- a sandbox
- an access-control system
- a backup
- a substitute for code review
- a substitute for server-side branch protection
- a compliance or certification artifact
- a guarantee that any particular command will be stopped

It **will not catch everything, and it is not intended to.** A static text guard
cannot resolve what a shell will only assemble at run time. Commands whose
destructive flags live in a variable, are built by string concatenation, or
arrive base64-encoded and piped to `sh` pass straight through. These limits are
inherent to the approach, not defects awaiting a fix; several are pinned as
explicit non-goals in `run-vuln-tests.sh` and listed in
[SECURITY.md](SECURITY.md#threat-model).

**A layer that stops many mistakes is worth more than no layer. It is worth less
than a backup.** Do not let its presence change how you protect your data.

## What the tests and badges do and do not mean

This repository publishes a 149-case adversarial test suite and green CI badges.
They mean exactly one thing: **the cases written down in those suites behaved as
recorded, on the runners, at the time they ran.**

They do not mean the software is secure, complete, correct, fit for your purpose,
or that no bypass exists. A test suite demonstrates the presence of the
behaviours it tests. It cannot demonstrate the absence of every other behaviour.
The 65 bypasses that suite found in guards that had previously passed their own
tests are the plainest possible evidence of that.

## It can fail silently, by design

If the hook library cannot be resolved, the loader **exits successfully and your
session continues with no protection at all.** This is deliberate: a broken
guardrail install must not stop you from working. The practical consequence is
that **the absence of a block does not mean a command was checked and approved.**
It may mean nothing checked it.

Never treat "no warning appeared" as confirmation that an operation is safe.

## Your responsibilities

If you install this, you remain solely responsible for:

- keeping working backups, tested by restoring them
- server-side branch protection on branches that matter
- reviewing what an AI agent does in your repositories
- credential hygiene, rotation, and keeping secrets out of source control
- deciding whether this software is appropriate for your environment
- any consequence of using, misusing, or relying on it

## Third-party components

Claude Code, `git`, `bash`, `node`, and any MCP servers you configure are
independent software governed by their own terms. This project neither controls
nor makes representations about their behaviour. "Claude" and "Claude Code" are
products of Anthropic; this is an unaffiliated, independent project.

## No professional advice, no relationship

The contents of this repository, including [SECURITY.md](SECURITY.md), are
engineering notes. They are not legal, security, compliance, or professional
advice, and using this software creates no advisory, support, or contractual
relationship with the authors.

## If you cannot accept these terms

Do not install or use this software. Continued use is your acceptance of
everything above.
