#!/bin/bash
# =============================================================================
# Adversarial (red-team) test suite for the guardrail library.
#
# run-tests.sh asks:      "does the guard fire on the documented pattern?"
# run-vuln-tests.sh asks: "can the same destructive effect get PAST the guard?"
#
# Every case here is an evasion attempt. A case expecting exit 2 is an attack
# the library must refuse. A case expecting exit 0 is a DOCUMENTED NON-GOAL --
# pinned so a silent behaviour change shows up as a failure, and explained in
# SECURITY.md. Nothing in this file is aspirational.
#
# Usage:
#   bash run-vuln-tests.sh            # run the suite
#   bash run-vuln-tests.sh --count    # print the assertion count (badge source)
#
# Exit 0 = every attack refused and every non-goal still pinned.
# Exit 1 = at least one evasion succeeded.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECKS_DIR="$SCRIPT_DIR/checks"
PASS=0; FAIL=0; COUNT_ONLY=0
FAILED_CASES=""

[ "$1" = "--count" ] && COUNT_ONLY=1

say() { [ "$COUNT_ONLY" -eq 1 ] || printf '%s\n' "$1"; }
section() { [ "$COUNT_ONLY" -eq 1 ] || printf '\n=== %s ===\n' "$1"; }

# probe <expected-exit> <check-name> <description>
# Runs one check against the currently exported HOOK_* environment.
probe() {
  local expected=$1 check=$2 desc="$3" actual
  bash "$CHECKS_DIR/${check}.sh" >/dev/null 2>&1
  actual=$?
  if [ "$actual" -eq "$expected" ]; then
    PASS=$((PASS+1))
    [ "$COUNT_ONLY" -eq 1 ] || printf '  PASS: %s\n' "$desc"
  else
    FAIL=$((FAIL+1))
    FAILED_CASES="${FAILED_CASES}  - [${check}] ${desc} (expected exit ${expected}, got ${actual})"$'\n'
    [ "$COUNT_ONLY" -eq 1 ] || printf '  FAIL: %s  (expected exit %d, got %d)\n' "$desc" "$expected" "$actual"
  fi
}

# bash_probe <expected> <check> <command> <description>
bash_probe() {
  export HOOK_TOOL_NAME="Bash" HOOK_COMMAND="$3"
  probe "$1" "$2" "$4"
}

# ps_probe <expected> <check> <command> <description>
ps_probe() {
  export HOOK_TOOL_NAME="PowerShell" HOOK_COMMAND="$3"
  probe "$1" "$2" "$4"
}

# json_payload <tool> <file-path> <content>
json_payload() {
  node -e 'const a=process.argv.slice(1);process.stdout.write(JSON.stringify({tool_name:a[0],tool_input:{file_path:a[1],content:a[2],new_string:a[2],old_string:""}}))' "$1" "$2" "$3"
}

# write_probe <expected> <check> <file-path> <content> <description>
write_probe() {
  export HOOK_TOOL_NAME="Write" HOOK_FILE_PATH="$3" HOOK_COMMAND=""
  HOOK_INPUT_JSON=$(json_payload Write "$3" "$4"); export HOOK_INPUT_JSON
  probe "$1" "$2" "$5"
}

# edit_probe <expected> <check> <file-path> <new-string> <description>
edit_probe() {
  export HOOK_TOOL_NAME="Edit" HOOK_FILE_PATH="$3" HOOK_COMMAND=""
  HOOK_INPUT_JSON=$(json_payload Edit "$3" "$4"); export HOOK_INPUT_JSON
  probe "$1" "$2" "$5"
}

# frag <piece>... -- join fragments into one string
#
# A test fixture that looks exactly like a real credential is a real problem:
# GitHub push protection scans this file and rejects the push, and every fork
# and mirror inherits that. Allow-listing each fake secret is the wrong fix --
# it trains people to click through secret warnings.
#
# So every provider-format fixture below is assembled at run time from
# fragments. The value the guard receives is a complete, well-formed token, but
# no contiguous token literal ever exists in this file for a scanner to match.
# Keep it that way: do not "simplify" these back into single string literals.
frag() {
  local out="" piece
  for piece in "$@"; do out="${out}${piece}"; done
  printf '%s' "$out"
}

# dispatch_probe <expected> <payload-json> <description>
# Drives the real pre-tool-use.sh dispatcher end to end, so a tool name the
# dispatcher does not route is caught here even when the check itself is sound.
dispatch_probe() {
  local expected=$1 payload=$2 desc="$3" actual
  printf '%s' "$payload" | bash "$SCRIPT_DIR/pre-tool-use.sh" >/dev/null 2>&1
  actual=$?
  if [ "$actual" -eq "$expected" ]; then
    PASS=$((PASS+1))
    [ "$COUNT_ONLY" -eq 1 ] || printf '  PASS: %s\n' "$desc"
  else
    FAIL=$((FAIL+1))
    FAILED_CASES="${FAILED_CASES}  - [dispatcher] ${desc} (expected exit ${expected}, got ${actual})"$'\n'
    [ "$COUNT_ONLY" -eq 1 ] || printf '  FAIL: %s  (expected exit %d, got %d)\n' "$desc" "$expected" "$actual"
  fi
}

say "Adversarial guardrail suite -- every case below is an evasion attempt."

# -----------------------------------------------------------------------------
section "A1. rm -rf -- flag obfuscation"

bash_probe 2 check-rm-rf 'rm --recursive --force /tmp/x' 'long flags: rm --recursive --force'
bash_probe 2 check-rm-rf 'rm --force --recursive /tmp/x' 'long flags reversed'
bash_probe 2 check-rm-rf 'rm --recursive -f /tmp/x' 'mixed long --recursive + short -f'
bash_probe 2 check-rm-rf 'rm -r --force /tmp/x' 'mixed short -r + long --force'
bash_probe 2 check-rm-rf 'rm -R -f /tmp/x' 'uppercase -R'
bash_probe 2 check-rm-rf 'rm -v -r -f /tmp/x' 'interleaved unrelated flag'
bash_probe 2 check-rm-rf 'rm -rf --no-preserve-root /' 'no-preserve-root on /'
bash_probe 2 check-rm-rf 'rm --no-preserve-root -r -f /' 'no-preserve-root, split flags'
bash_probe 2 check-rm-rf "$(printf 'rm\t-rf\t/tmp/x')" 'tab-separated flags'
bash_probe 2 check-rm-rf 'rm    -rf     /tmp/x' 'runs of spaces'

# -----------------------------------------------------------------------------
section "A2. rm -rf -- binary indirection and chaining"

bash_probe 2 check-rm-rf '/bin/rm -rf /tmp/x' 'absolute path /bin/rm'
bash_probe 2 check-rm-rf '/usr/bin/rm -rf /tmp/x' 'absolute path /usr/bin/rm'
bash_probe 2 check-rm-rf '\rm -rf /tmp/x' 'backslash-escaped rm (alias bypass)'
bash_probe 2 check-rm-rf 'sudo rm -rf /tmp/x' 'sudo prefix'
bash_probe 2 check-rm-rf 'env rm -rf /tmp/x' 'env prefix'
bash_probe 2 check-rm-rf 'command rm -rf /tmp/x' 'command builtin prefix'
bash_probe 2 check-rm-rf 'echo ok && rm -rf /tmp/x' 'chained after &&'
bash_probe 2 check-rm-rf 'echo ok; rm -rf /tmp/x' 'chained after ;'
bash_probe 2 check-rm-rf 'echo ok || rm -rf /tmp/x' 'chained after ||'
bash_probe 2 check-rm-rf "$(printf 'echo ok\nrm -rf /tmp/x')" 'second line of a multi-line command'
bash_probe 2 check-rm-rf 'find /tmp/x -type f | xargs rm -rf' 'piped into xargs rm'
bash_probe 2 check-rm-rf 'bash -c "rm -rf /tmp/x"' 'wrapped in bash -c'

# -----------------------------------------------------------------------------
section "A3. Recursive delete by another name"

bash_probe 2 check-rm-rf 'find /tmp/x -delete' 'find -delete'
bash_probe 2 check-rm-rf 'find /tmp/x -type f -delete' 'find -type f -delete'

# -----------------------------------------------------------------------------
section "A4. rm -rf -- legitimate commands must stay allowed"

bash_probe 0 check-rm-rf 'rm /tmp/one-file.txt' 'plain rm allowed'
bash_probe 0 check-rm-rf 'rm -f /tmp/one-file.txt' 'rm -f (non-recursive) allowed'
bash_probe 0 check-rm-rf 'rm -r /tmp/emptydir' 'rm -r (non-forced) allowed'
bash_probe 0 check-rm-rf 'grep -rf patterns.txt src/' 'grep -rf is not rm'
bash_probe 0 check-rm-rf 'cat docs/block-rm-rf.md' 'rm-rf inside a filename allowed'
bash_probe 0 check-rm-rf 'find /tmp/x -name "*.log"' 'find without -delete allowed'
bash_probe 0 check-rm-rf 'npm run format' 'unrelated command allowed'

# -----------------------------------------------------------------------------
section "A5. PowerShell / CMD delete aliases"

ps_probe 2 check-rm-rf 'rd -Recurse -Force C:\tmp\x' 'rd alias (Remove-Item)'
ps_probe 2 check-rm-rf 'rmdir -Recurse -Force C:\tmp\x' 'rmdir as PowerShell alias'
ps_probe 2 check-rm-rf 'del -Recurse -Force C:\tmp\x' 'del alias'
ps_probe 2 check-rm-rf 'erase -Recurse -Force C:\tmp\x' 'erase alias'
ps_probe 2 check-rm-rf 'Remove-Item -Recurse -Force C:\tmp\x' 'canonical form still blocked'
ps_probe 2 check-rm-rf 'rd /s /q C:\tmp\x' 'cmd-style rd /s /q'
ps_probe 2 check-rm-rf 'del /s /q C:\tmp\x' 'cmd-style del /s /q'
ps_probe 2 check-rm-rf 'Remove-Item C:\tmp\x -Recurse -Force' 'flags trailing the path'
ps_probe 2 check-rm-rf 'REMOVE-ITEM -RECURSE -FORCE C:\tmp\x' 'all-caps cmdlet'
ps_probe 0 check-rm-rf 'Remove-Item C:\tmp\one-file.txt' 'PowerShell single-file delete allowed'
ps_probe 0 check-rm-rf 'Get-ChildItem -Recurse -Force C:\tmp' 'Get-ChildItem -Recurse -Force allowed'

# -----------------------------------------------------------------------------
section "B1. git -- subcommand prefix evasion"

bash_probe 2 check-dangerous-git 'git -c user.name=x push origin main' 'git -c ... push'
bash_probe 2 check-dangerous-git 'git --no-pager push origin main' 'git --no-pager push'
bash_probe 2 check-dangerous-git 'git -C /tmp/repo push origin main' 'git -C <dir> push'
bash_probe 2 check-dangerous-git 'git -c core.hooksPath=/dev/null push' 'git -c disabling hooks, then push'
bash_probe 2 check-dangerous-git 'git -c x=y reset --hard HEAD~1' 'git -c ... reset --hard'
bash_probe 2 check-dangerous-git 'git --git-dir=/tmp/r/.git push origin main' 'git --git-dir=... push'

# -----------------------------------------------------------------------------
section "B2. git -- destructive equivalents"

bash_probe 2 check-dangerous-git 'git branch --delete --force feature/x' 'branch --delete --force'
bash_probe 2 check-dangerous-git 'git branch -d -f feature/x' 'branch -d -f'
bash_probe 2 check-dangerous-git 'git restore .' 'git restore . (modern checkout -- .)'
bash_probe 2 check-dangerous-git 'git restore --worktree .' 'git restore --worktree .'
bash_probe 2 check-dangerous-git 'git checkout .' 'git checkout . without --'
bash_probe 2 check-dangerous-git 'git checkout --force main' 'git checkout --force'
bash_probe 2 check-dangerous-git 'git stash clear' 'git stash clear'
bash_probe 2 check-dangerous-git 'git stash drop' 'git stash drop'
bash_probe 2 check-dangerous-git 'git reflog expire --expire=now --all' 'reflog expire (destroys recovery)'
bash_probe 2 check-dangerous-git 'git update-ref -d refs/heads/main' 'update-ref -d (branch deletion)'

# -----------------------------------------------------------------------------
section "B3. git -- allowed operations must stay allowed"

bash_probe 0 check-dangerous-git 'git status' 'git status allowed'
bash_probe 0 check-dangerous-git 'git commit -m "msg"' 'git commit allowed'
bash_probe 0 check-dangerous-git 'git log --oneline -5' 'git log allowed'
bash_probe 0 check-dangerous-git 'git diff --stat' 'git diff allowed'
bash_probe 0 check-dangerous-git 'git branch -d merged-branch' 'branch -d (safe delete) allowed'
bash_probe 0 check-dangerous-git 'git restore --staged file.txt' 'restore --staged (unstage only) allowed'
bash_probe 0 check-dangerous-git 'git checkout -b feature/new' 'checkout -b allowed'
bash_probe 0 check-dangerous-git 'git stash list' 'stash list allowed'
bash_probe 0 check-dangerous-git 'git add -A' 'git add allowed'
bash_probe 0 check-dangerous-git 'git fetch --all' 'git fetch allowed'

# -----------------------------------------------------------------------------
section "C1. SQL -- tautology WHERE defeats the row-scope guard"

bash_probe 2 check-production-guard 'psql -c "DELETE FROM users WHERE 1=1"' 'DELETE ... WHERE 1=1'
bash_probe 2 check-production-guard 'psql -c "DELETE FROM users WHERE true"' 'DELETE ... WHERE true'
bash_probe 2 check-production-guard "psql -c \"DELETE FROM users WHERE 'a'='a'\"" "DELETE ... WHERE 'a'='a'"
bash_probe 2 check-production-guard 'psql -c "UPDATE users SET admin=1 WHERE 1=1"' 'UPDATE ... WHERE 1=1'
bash_probe 2 check-production-guard 'psql -c "DELETE FROM users WHERE 1 = 1"' 'tautology with spaces'

# -----------------------------------------------------------------------------
section "C2. SQL -- unguarded destructive statements"

bash_probe 2 check-production-guard 'psql -c "DROP DATABASE production"' 'DROP DATABASE'
bash_probe 2 check-production-guard 'psql -c "DROP SCHEMA public CASCADE"' 'DROP SCHEMA ... CASCADE'
bash_probe 2 check-production-guard 'psql -c "TRUNCATE users"' 'TRUNCATE without the TABLE keyword'
bash_probe 2 check-production-guard 'psql -c "UPDATE public.users SET admin=1"' 'schema-qualified UPDATE, no WHERE'
bash_probe 2 check-production-guard 'psql -c "UPDATE \"users\" SET admin=1"' 'quoted table name, no WHERE'
bash_probe 2 check-production-guard 'psql -c "DELETE FROM users; -- WHERE is only a comment"' 'WHERE present only as a comment'
bash_probe 2 check-production-guard 'psql -c "DELETE FROM audit; SELECT 1 WHERE x=1"' 'WHERE belongs to a different statement'
bash_probe 2 check-production-guard "$(printf 'psql -c "DELETE\nFROM users"')" 'DELETE and FROM split across lines'
bash_probe 2 check-production-guard 'psql -c "delete from users"' 'lowercase SQL'

# -----------------------------------------------------------------------------
section "C3. SQL -- scoped statements must stay allowed"

bash_probe 0 check-production-guard 'psql -c "DELETE FROM users WHERE id = 42"' 'scoped DELETE allowed'
bash_probe 0 check-production-guard 'psql -c "UPDATE users SET name = $1 WHERE id = 42"' 'scoped UPDATE allowed'
bash_probe 0 check-production-guard 'psql -c "SELECT * FROM users"' 'SELECT allowed'
bash_probe 0 check-production-guard 'psql -c "CREATE TABLE t (id int)"' 'CREATE TABLE allowed'
bash_probe 0 check-production-guard 'grep -r "DROP TABLE" migrations/' 'searching for the phrase allowed'

# -----------------------------------------------------------------------------
section "D1. Sensitive files -- case and naming evasion"

write_probe 2 check-sensitive-files '/proj/.ENV' 'X=1' 'uppercase .ENV'
write_probe 2 check-sensitive-files '/proj/.Env.Production' 'X=1' 'mixed-case .Env.Production'
write_probe 2 check-sensitive-files '/proj/server.PEM' 'x' 'uppercase .PEM extension'
write_probe 2 check-sensitive-files '/proj/.envrc' 'export X=1' '.envrc (direnv secrets)'
write_probe 2 check-sensitive-files '/home/u/.aws/credentials' 'x' '.aws/credentials (no .json suffix)'
write_probe 2 check-sensitive-files '/home/u/.netrc' 'x' '.netrc'
write_probe 2 check-sensitive-files '/home/u/.git-credentials' 'x' '.git-credentials'
write_probe 2 check-sensitive-files '/home/u/.npmrc' '//r:_authToken=x' '.npmrc (auth token)'
write_probe 2 check-sensitive-files '/proj/server.ppk' 'x' '.ppk (PuTTY private key)'
write_probe 2 check-sensitive-files '/proj/.env' 'X=1' 'canonical .env still blocked'
write_probe 0 check-sensitive-files '/proj/.env.example' 'X=' '.env.example allowed'
write_probe 0 check-sensitive-files '/proj/src/main.js' 'const x = 1' 'ordinary source file allowed'
write_probe 0 check-sensitive-files '/proj/README.md' '# docs' 'markdown allowed'

# -----------------------------------------------------------------------------
section "D2. Secret literals -- pattern evasion"

# Provider-format fixtures, assembled at run time -- see frag() above.
AWS_TEMP=$(frag 'ASIA' 'IOSFODNN7' 'EXAMPLE')
AWS_PERM=$(frag 'AKIA' 'IOSFODNN7' 'EXAMPLE')
GH_PAT=$(frag 'ghp' '_1234567890' 'abcdefghijklmnopqrstuvwx')
SLACK_TOK=$(frag 'xoxb' '-123456789012-' 'abcdefghijklmnop')
GOOGLE_KEY=$(frag 'AIza' 'SyA1234567890' 'abcdefghijklmnopqrstu')
STRIPE_KEY=$(frag 'sk' '_live_' '1234567890abcdefghijklmn')
PGP_BLOCK=$(frag '-----BEGIN ' 'PGP PRIVATE KEY BLOCK' '-----')
PK_BLOCK=$(frag '-----BEGIN ' 'PRIVATE KEY' '-----')

write_probe 2 check-secrets-write '/proj/cfg.py' 'password = "hunter2xyz"' 'quoted password literal'
write_probe 2 check-secrets-write '/proj/cfg.sh' 'DB_PASSWORD=hunter2xyz' 'unquoted password assignment'
write_probe 2 check-secrets-write '/proj/cfg.py' "aws_key = \"$AWS_TEMP\"" 'ASIA temporary AWS key'
write_probe 2 check-secrets-write '/proj/cfg.py' "tok = \"$GH_PAT\"" 'GitHub personal access token'
write_probe 2 check-secrets-write '/proj/cfg.py' "tok = \"$SLACK_TOK\"" 'Slack bot token'
write_probe 2 check-secrets-write '/proj/cfg.py' "k = \"$GOOGLE_KEY\"" 'Google API key'
write_probe 2 check-secrets-write '/proj/cfg.py' "k = \"$STRIPE_KEY\"" 'Stripe live secret key'
write_probe 2 check-secrets-write '/proj/k.txt' "$PGP_BLOCK" 'PGP private key block'
write_probe 2 check-secrets-write '/proj/k.txt' "$PK_BLOCK" 'unlabelled private key block'
write_probe 2 check-secrets-write '/proj/cfg.py' "AWS_KEY = \"$AWS_PERM\"" 'AKIA AWS key still blocked'
edit_probe 2 check-secrets-write '/proj/cfg.py' 'api_key = "abcdef1234567890"' 'Edit new_string scanned'

# -----------------------------------------------------------------------------
section "D3. Secret literals -- exemption abuse"

write_probe 2 check-secrets-write '/proj/src/.claudette/cfg.py' 'password = "hunter2xyz"' 'dir merely starting with .claude not exempt'
write_probe 2 check-secrets-write '/proj/latest/cfg.py' 'password = "hunter2xyz"' 'dir containing "test" not exempt'
write_probe 2 check-secrets-write '/proj/contest/cfg.py' 'password = "hunter2xyz"' 'dir ending in "test" not exempt'
write_probe 0 check-secrets-write '/proj/test/fixture.py' 'password = "hunter2xyz"' 'real test dir exempt (by design)'
write_probe 0 check-secrets-write '/proj/cfg.py.example' 'password = "changeme"' '.example exempt (by design)'
write_probe 0 check-secrets-write '/proj/src/main.js' 'const port = 8080' 'clean source allowed'
write_probe 0 check-secrets-write '/proj/cfg.py' 'password = os.environ["DB_PASSWORD"]' 'env-var reference allowed'
write_probe 0 check-secrets-write '/proj/cfg.py' 'password = ""' 'empty password allowed'

# -----------------------------------------------------------------------------
section "E1. Tool-name evasion -- the dispatcher must route every mutating tool"

dispatch_probe 2 "$(json_payload NotebookEdit /proj/.env 'X=1')" 'NotebookEdit to .env is routed'
dispatch_probe 2 "$(json_payload MultiEdit /proj/.env 'X=1')" 'MultiEdit to .env is routed'
dispatch_probe 2 "$(json_payload Update /proj/.env 'X=1')" 'Update to .env is routed'
dispatch_probe 2 "$(json_payload Write /proj/.env 'X=1')" 'Write to .env is routed'
dispatch_probe 2 "$(json_payload Edit /proj/.env 'X=1')" 'Edit to .env is routed'
dispatch_probe 2 "$(json_payload NotebookEdit /proj/cfg.py 'password = "hunter2xyz"')" 'NotebookEdit secret literal is routed'
dispatch_probe 0 "$(json_payload Write /proj/src/main.js 'const x = 1')" 'clean Write passes the dispatcher'
dispatch_probe 0 "$(json_payload Read /proj/.env '')" 'Read of .env is not a write (allowed)'

# -----------------------------------------------------------------------------
section "E2. Dispatcher -- malformed and hostile payloads must not crash open"

dispatch_probe 0 'not json at all' 'non-JSON payload exits cleanly'
dispatch_probe 0 '' 'empty payload exits cleanly'
dispatch_probe 0 '{}' 'empty object exits cleanly'
dispatch_probe 0 '{"tool_name":"Bash"}' 'missing tool_input exits cleanly'
dispatch_probe 2 '{"tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/x"}}' 'well-formed Bash payload still blocks'
dispatch_probe 0 '{"tool_name":"Bash","tool_input":{"command":"$(rm -rf /tmp/x)"}}' 'payload is never eval-ed by the dispatcher'

# -----------------------------------------------------------------------------
section "F1. macOS destructive -- flag obfuscation"

bash_probe 2 check-macos-destructive 'srm --recursive /tmp/x' 'srm --recursive (long flag)'
bash_probe 2 check-macos-destructive 'srm -r /tmp/x' 'srm -r still blocked'
bash_probe 2 check-macos-destructive 'diskutil eraseDisk JHFS+ Blank /dev/disk2' 'diskutil eraseDisk blocked'
bash_probe 2 check-macos-destructive 'diskutil apfs deleteContainer disk2' 'diskutil apfs deleteContainer'
bash_probe 0 check-macos-destructive 'diskutil list' 'diskutil list allowed'
bash_probe 0 check-macos-destructive 'defaults delete com.example.app key' 'scoped defaults delete allowed'

# -----------------------------------------------------------------------------
section "F2. Homebrew -- flag obfuscation"

bash_probe 2 check-homebrew 'brew uninstall --force wget' 'brew uninstall --force blocked'
bash_probe 2 check-homebrew 'brew remove -f wget' 'brew remove -f blocked'
bash_probe 0 check-homebrew 'brew uninstall wget' 'plain brew uninstall allowed'
bash_probe 0 check-homebrew 'brew install wget' 'brew install allowed'

# -----------------------------------------------------------------------------
section "G. Documented non-goals -- pinned, not aspirational (see SECURITY.md)"
# A static text guard cannot resolve values only the shell knows at run time.
# These cases assert the CURRENT behaviour so a change becomes visible; they are
# not claims of protection. Defence in depth for these is the git-level hook and
# server-side branch protection, not string matching.

bash_probe 0 check-rm-rf 'RF="-rf"; rm $RF /tmp/x' 'flags held in a variable not caught (non-goal)'
bash_probe 0 check-rm-rf 'eval "$(printf "rm -%s /tmp/x" rf)"' 'runtime string assembly not caught (non-goal)'
bash_probe 0 check-rm-rf 'echo cm0gLXJmIC8= | base64 -d | sh' 'base64-encoded command not caught (non-goal)'
bash_probe 0 check-secrets-write 'x' 'ignores Bash tool (wrong-tool guard)'
write_probe 0 check-secrets-write '/proj/cfg.py' 'p = "hun" + "ter2xyz"' 'string concatenation not caught (non-goal)'
write_probe 0 check-rm-rf '/proj/x' 'rm -rf /' 'command guard ignores Write payloads (by design)'

# -----------------------------------------------------------------------------
if [ "$COUNT_ONLY" -eq 1 ]; then
  echo $((PASS + FAIL))
  exit 0
fi

TOTAL=$((PASS + FAIL))
printf '\n'
printf '%s\n' '================================================================'
printf '  Adversarial suite: %d/%d refused as expected\n' "$PASS" "$TOTAL"
printf '%s\n' '================================================================'

if [ "$FAIL" -gt 0 ]; then
  printf '\n%d evasion(s) succeeded:\n\n' "$FAIL"
  printf '%s' "$FAILED_CASES"
  printf '\n'
  exit 1
fi

printf '\nNo evasion succeeded.\n'
exit 0
