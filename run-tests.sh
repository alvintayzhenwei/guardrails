#!/bin/bash
# Test harness for the guardrail library. Run from the repo root.
# Exit 0 = all pass. Exit 1 = at least one failure.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECKS_DIR="$SCRIPT_DIR/checks"
PASS=0; FAIL=0

chk() {
  local expected=$1 actual=$2 desc="$3"
  if [ "$actual" -eq "$expected" ]; then
    printf "  PASS: %s\n" "$desc"; PASS=$((PASS+1))
  else
    printf "  FAIL: %s  (expected exit %d, got %d)\n" "$desc" "$expected" "$actual"
    FAIL=$((FAIL+1))
  fi
}

# ── check-rm-rf ──────────────────────────────────────────────────────────────
echo ""
echo "=== check-rm-rf ==="

export HOOK_TOOL_NAME="Bash"
export HOOK_COMMAND="rm -rf /tmp/foo"
bash "$CHECKS_DIR/check-rm-rf.sh" >/dev/null 2>&1; chk 2 $? "blocks rm -rf"

export HOOK_COMMAND="rm -fr /tmp/foo"
bash "$CHECKS_DIR/check-rm-rf.sh" >/dev/null 2>&1; chk 2 $? "blocks rm -fr"

export HOOK_COMMAND="rm -r -f /tmp/foo"
bash "$CHECKS_DIR/check-rm-rf.sh" >/dev/null 2>&1; chk 2 $? "blocks rm -r -f"

export HOOK_COMMAND="rm /tmp/foo.txt"
bash "$CHECKS_DIR/check-rm-rf.sh" >/dev/null 2>&1; chk 0 $? "allows plain rm"

export HOOK_TOOL_NAME="Write"; export HOOK_COMMAND=""
bash "$CHECKS_DIR/check-rm-rf.sh" >/dev/null 2>&1; chk 0 $? "ignores non-Bash tool"

# PowerShell patterns
export HOOK_TOOL_NAME="PowerShell"
export HOOK_COMMAND="Remove-Item -Recurse -Force C:\Users\foo\tmp"
bash "$CHECKS_DIR/check-rm-rf.sh" >/dev/null 2>&1; chk 2 $? "blocks Remove-Item -Recurse -Force"

export HOOK_COMMAND="Remove-Item -Force -Recurse C:\Users\foo\tmp"
bash "$CHECKS_DIR/check-rm-rf.sh" >/dev/null 2>&1; chk 2 $? "blocks Remove-Item -Force -Recurse"

export HOOK_COMMAND="ri -Recurse -Force C:\Users\foo\tmp"
bash "$CHECKS_DIR/check-rm-rf.sh" >/dev/null 2>&1; chk 2 $? "blocks ri -Recurse -Force"

export HOOK_COMMAND="Remove-Item -r -fo C:\Users\foo\tmp"
bash "$CHECKS_DIR/check-rm-rf.sh" >/dev/null 2>&1; chk 2 $? "blocks Remove-Item -r -fo (short flags)"

export HOOK_COMMAND="rmdir /S /Q C:\Users\foo\tmp"
bash "$CHECKS_DIR/check-rm-rf.sh" >/dev/null 2>&1; chk 2 $? "blocks rmdir /S /Q"

export HOOK_COMMAND="Remove-Item -Recurse C:\Users\foo\tmp"
bash "$CHECKS_DIR/check-rm-rf.sh" >/dev/null 2>&1; chk 0 $? "allows Remove-Item without -Force"

export HOOK_COMMAND="Remove-Item C:\Users\foo\tmp"
bash "$CHECKS_DIR/check-rm-rf.sh" >/dev/null 2>&1; chk 0 $? "allows Remove-Item with no flags"

export HOOK_COMMAND='Remove-Item -Recurse:$true -Force C:\Users\foo\tmp'
bash "$CHECKS_DIR/check-rm-rf.sh" >/dev/null 2>&1; chk 2 $? "blocks Remove-Item -Recurse:true -Force"

export HOOK_COMMAND='Remove-Item -Recurse -Force:$true C:\Users\foo\tmp'
bash "$CHECKS_DIR/check-rm-rf.sh" >/dev/null 2>&1; chk 2 $? "blocks Remove-Item -Recurse -Force:true"

# ── check-dangerous-git ──────────────────────────────────────────────────────
echo ""
echo "=== check-dangerous-git ==="

export HOOK_TOOL_NAME="Bash"

export HOOK_COMMAND="git push origin main"
bash "$CHECKS_DIR/check-dangerous-git.sh" >/dev/null 2>&1; chk 2 $? "blocks git push"

export HOOK_COMMAND="git push --force origin main"
bash "$CHECKS_DIR/check-dangerous-git.sh" >/dev/null 2>&1; chk 2 $? "blocks git push --force"

export HOOK_COMMAND="git reset --hard HEAD~1"
bash "$CHECKS_DIR/check-dangerous-git.sh" >/dev/null 2>&1; chk 2 $? "blocks git reset --hard"

export HOOK_COMMAND="git branch -D feature/old"
bash "$CHECKS_DIR/check-dangerous-git.sh" >/dev/null 2>&1; chk 2 $? "blocks git branch -D"

export HOOK_COMMAND="git clean -fd"
bash "$CHECKS_DIR/check-dangerous-git.sh" >/dev/null 2>&1; chk 2 $? "blocks git clean -fd"

export HOOK_COMMAND="git checkout -- ."
bash "$CHECKS_DIR/check-dangerous-git.sh" >/dev/null 2>&1; chk 2 $? "blocks git checkout -- ."

export HOOK_COMMAND="git status"
bash "$CHECKS_DIR/check-dangerous-git.sh" >/dev/null 2>&1; chk 0 $? "allows git status"

export HOOK_COMMAND="git fetch origin"
bash "$CHECKS_DIR/check-dangerous-git.sh" >/dev/null 2>&1; chk 0 $? "allows git fetch"

export HOOK_COMMAND="git log --oneline -10"
bash "$CHECKS_DIR/check-dangerous-git.sh" >/dev/null 2>&1; chk 0 $? "allows git log"

export HOOK_COMMAND="git diff HEAD"
bash "$CHECKS_DIR/check-dangerous-git.sh" >/dev/null 2>&1; chk 0 $? "allows git diff"

export HOOK_TOOL_NAME="PowerShell"
export HOOK_COMMAND="git push origin main"
bash "$CHECKS_DIR/check-dangerous-git.sh" >/dev/null 2>&1; chk 2 $? "PowerShell: blocks git push"

export HOOK_COMMAND="git status"
bash "$CHECKS_DIR/check-dangerous-git.sh" >/dev/null 2>&1; chk 0 $? "PowerShell: allows git status"

# ── check-sensitive-files ────────────────────────────────────────────────────
echo ""
echo "=== check-sensitive-files ==="

export HOOK_TOOL_NAME="Write"

export HOOK_FILE_PATH="/project/.env"
bash "$CHECKS_DIR/check-sensitive-files.sh" >/dev/null 2>&1; chk 2 $? "blocks .env"

export HOOK_FILE_PATH="/project/.env.local"
bash "$CHECKS_DIR/check-sensitive-files.sh" >/dev/null 2>&1; chk 2 $? "blocks .env.local"

export HOOK_FILE_PATH="/project/.env.production"
bash "$CHECKS_DIR/check-sensitive-files.sh" >/dev/null 2>&1; chk 2 $? "blocks .env.production"

export HOOK_FILE_PATH="/project/certs/server.pem"
bash "$CHECKS_DIR/check-sensitive-files.sh" >/dev/null 2>&1; chk 2 $? "blocks .pem"

export HOOK_FILE_PATH="/project/certs/server.key"
bash "$CHECKS_DIR/check-sensitive-files.sh" >/dev/null 2>&1; chk 2 $? "blocks .key"

export HOOK_FILE_PATH="/project/keystore.jks"
bash "$CHECKS_DIR/check-sensitive-files.sh" >/dev/null 2>&1; chk 2 $? "blocks .jks"

export HOOK_FILE_PATH="/project/credentials.json"
bash "$CHECKS_DIR/check-sensitive-files.sh" >/dev/null 2>&1; chk 2 $? "blocks credentials.json"

export HOOK_FILE_PATH="/project/secrets.json"
bash "$CHECKS_DIR/check-sensitive-files.sh" >/dev/null 2>&1; chk 2 $? "blocks secrets.json"

export HOOK_FILE_PATH="/project/keys/id_rsa"
bash "$CHECKS_DIR/check-sensitive-files.sh" >/dev/null 2>&1; chk 2 $? "blocks id_rsa"

export HOOK_FILE_PATH="/project/src/main/resources/application.yml"
bash "$CHECKS_DIR/check-sensitive-files.sh" >/dev/null 2>&1; chk 0 $? "allows application.yml"

export HOOK_FILE_PATH="/project/src/Config.java"
bash "$CHECKS_DIR/check-sensitive-files.sh" >/dev/null 2>&1; chk 0 $? "allows .java file"

export HOOK_TOOL_NAME="Bash"; export HOOK_FILE_PATH="/project/.env"
bash "$CHECKS_DIR/check-sensitive-files.sh" >/dev/null 2>&1; chk 0 $? "ignores Bash tool"

# ── check-secrets-write ──────────────────────────────────────────────────────
echo ""
echo "=== check-secrets-write ==="

export HOOK_TOOL_NAME="Write"

export HOOK_FILE_PATH="/project/src/Config.java"
export HOOK_INPUT_JSON='{"tool_name":"Write","tool_input":{"file_path":"/project/src/Config.java","content":"String password = \"supersecret123\";\n"}}'
bash "$CHECKS_DIR/check-secrets-write.sh" >/dev/null 2>&1; chk 2 $? "blocks password literal"

export HOOK_INPUT_JSON='{"tool_name":"Write","tool_input":{"file_path":"/project/src/Config.java","content":"String apiKey = \"abcdefghij1234567890\";\n"}}'
bash "$CHECKS_DIR/check-secrets-write.sh" >/dev/null 2>&1; chk 2 $? "blocks api_key literal"

export HOOK_INPUT_JSON='{"tool_name":"Write","tool_input":{"file_path":"/project/src/Config.java","content":"// Bearer eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiJ1c2VyMTIzNDU2Nzg5MCJ9.somesig\n"}}'
bash "$CHECKS_DIR/check-secrets-write.sh" >/dev/null 2>&1; chk 2 $? "blocks Bearer token"

export HOOK_INPUT_JSON='{"tool_name":"Write","tool_input":{"file_path":"/project/src/Config.java","content":"-----BEGIN RSA PRIVATE KEY-----\nMIIEpAIBAAKCAQEA...\n-----END RSA PRIVATE KEY-----\n"}}'
bash "$CHECKS_DIR/check-secrets-write.sh" >/dev/null 2>&1; chk 2 $? "blocks private key block"

export HOOK_INPUT_JSON='{"tool_name":"Write","tool_input":{"file_path":"/project/src/Config.java","content":"String awsKey = \"AKIAIOSFODNN7EXAMPLE\";\n"}}'
bash "$CHECKS_DIR/check-secrets-write.sh" >/dev/null 2>&1; chk 2 $? "blocks AWS access key"

export HOOK_INPUT_JSON='{"tool_name":"Write","tool_input":{"file_path":"/project/src/Config.java","content":"String password = System.getenv(\"DB_PASSWORD\");\n"}}'
bash "$CHECKS_DIR/check-secrets-write.sh" >/dev/null 2>&1; chk 0 $? "allows env var reference"

export HOOK_FILE_PATH="/project/test/fixtures/user.json"
export HOOK_INPUT_JSON='{"tool_name":"Write","tool_input":{"file_path":"/project/test/fixtures/user.json","content":"{\"password\":\"testpassword123\"}"}}'
bash "$CHECKS_DIR/check-secrets-write.sh" >/dev/null 2>&1; chk 0 $? "allows secrets in test fixtures"

export HOOK_FILE_PATH="/project/config.example"
export HOOK_INPUT_JSON='{"tool_name":"Write","tool_input":{"file_path":"/project/config.example","content":"DB_PASSWORD=\"changeme\""}}'
bash "$CHECKS_DIR/check-secrets-write.sh" >/dev/null 2>&1; chk 0 $? "allows secrets in .example template"

# ── check-production-guard ───────────────────────────────────────────────────
echo ""
echo "=== check-production-guard ==="

export HOOK_TOOL_NAME="Bash"

export HOOK_COMMAND="psql -c 'DROP TABLE users;'"
bash "$CHECKS_DIR/check-production-guard.sh" >/dev/null 2>&1; chk 2 $? "blocks DROP TABLE"

export HOOK_COMMAND="psql -c 'TRUNCATE TABLE sessions;'"
bash "$CHECKS_DIR/check-production-guard.sh" >/dev/null 2>&1; chk 2 $? "blocks TRUNCATE TABLE"

export HOOK_COMMAND="psql -c 'DELETE FROM audit_log;'"
bash "$CHECKS_DIR/check-production-guard.sh" >/dev/null 2>&1; chk 2 $? "blocks DELETE FROM without WHERE"

export HOOK_COMMAND="psql -c 'UPDATE users SET active = false;'"
bash "$CHECKS_DIR/check-production-guard.sh" >/dev/null 2>&1; chk 2 $? "blocks UPDATE SET without WHERE"

export HOOK_COMMAND="psql -c 'DELETE FROM sessions WHERE expired = true;'"
bash "$CHECKS_DIR/check-production-guard.sh" >/dev/null 2>&1; chk 0 $? "allows DELETE with WHERE"

export HOOK_COMMAND="psql -c 'UPDATE users SET active = false WHERE id = 1;'"
bash "$CHECKS_DIR/check-production-guard.sh" >/dev/null 2>&1; chk 0 $? "allows UPDATE with WHERE"

export HOOK_COMMAND="SELECT * FROM users;"
bash "$CHECKS_DIR/check-production-guard.sh" >/dev/null 2>&1; chk 0 $? "allows SELECT"

export HOOK_TOOL_NAME="Write"; export HOOK_COMMAND="DROP TABLE users"
bash "$CHECKS_DIR/check-production-guard.sh" >/dev/null 2>&1; chk 0 $? "ignores non-Bash tool"

export HOOK_TOOL_NAME="PowerShell"
export HOOK_COMMAND="psql -c 'DROP TABLE users;'"
bash "$CHECKS_DIR/check-production-guard.sh" >/dev/null 2>&1; chk 2 $? "PowerShell: blocks DROP TABLE"

export HOOK_COMMAND="SELECT * FROM users;"
bash "$CHECKS_DIR/check-production-guard.sh" >/dev/null 2>&1; chk 0 $? "PowerShell: allows SELECT"

# ── check-macos-destructive ──────────────────────────────────────────────────
echo ""
echo "=== check-macos-destructive ==="

export HOOK_TOOL_NAME="Bash"

export HOOK_COMMAND="diskutil eraseDisk APFS MyDisk disk2"
bash "$CHECKS_DIR/check-macos-destructive.sh" >/dev/null 2>&1; chk 2 $? "blocks diskutil eraseDisk"

export HOOK_COMMAND="diskutil eraseVolume APFS MyVol disk2s1"
bash "$CHECKS_DIR/check-macos-destructive.sh" >/dev/null 2>&1; chk 2 $? "blocks diskutil eraseVolume"

export HOOK_COMMAND="diskutil zeroDisk disk2"
bash "$CHECKS_DIR/check-macos-destructive.sh" >/dev/null 2>&1; chk 2 $? "blocks diskutil zeroDisk"

export HOOK_COMMAND="diskutil secureErase 0 disk2"
bash "$CHECKS_DIR/check-macos-destructive.sh" >/dev/null 2>&1; chk 2 $? "blocks diskutil secureErase"

export HOOK_COMMAND="srm -rf /tmp/foo"
bash "$CHECKS_DIR/check-macos-destructive.sh" >/dev/null 2>&1; chk 2 $? "blocks srm -rf"

export HOOK_COMMAND="srm -r /tmp/foo"
bash "$CHECKS_DIR/check-macos-destructive.sh" >/dev/null 2>&1; chk 2 $? "blocks srm -r"

export HOOK_COMMAND="launchctl bootout system/com.apple.something"
bash "$CHECKS_DIR/check-macos-destructive.sh" >/dev/null 2>&1; chk 2 $? "blocks launchctl bootout system/"

export HOOK_COMMAND="defaults delete"
bash "$CHECKS_DIR/check-macos-destructive.sh" >/dev/null 2>&1; chk 2 $? "blocks bare defaults delete"

export HOOK_COMMAND="diskutil info disk2"
bash "$CHECKS_DIR/check-macos-destructive.sh" >/dev/null 2>&1; chk 0 $? "allows diskutil info"

export HOOK_COMMAND="srm /tmp/single-file.txt"
bash "$CHECKS_DIR/check-macos-destructive.sh" >/dev/null 2>&1; chk 0 $? "allows srm without -r"

export HOOK_COMMAND="launchctl bootout user/501/com.myapp"
bash "$CHECKS_DIR/check-macos-destructive.sh" >/dev/null 2>&1; chk 0 $? "allows launchctl bootout user/"

export HOOK_COMMAND="defaults delete com.apple.finder"
bash "$CHECKS_DIR/check-macos-destructive.sh" >/dev/null 2>&1; chk 0 $? "allows defaults delete with domain"

export HOOK_COMMAND="defaults delete > /tmp/backup"
bash "$CHECKS_DIR/check-macos-destructive.sh" >/dev/null 2>&1; chk 2 $? "blocks defaults delete with redirect"

export HOOK_COMMAND="defaults delete; echo done"
bash "$CHECKS_DIR/check-macos-destructive.sh" >/dev/null 2>&1; chk 2 $? "blocks defaults delete with semicolon"

export HOOK_TOOL_NAME="Write"; export HOOK_COMMAND="diskutil eraseDisk APFS MyDisk disk2"
bash "$CHECKS_DIR/check-macos-destructive.sh" >/dev/null 2>&1; chk 0 $? "ignores non-Bash tool"

# ── check-homebrew ────────────────────────────────────────────────────────────
echo ""
echo "=== check-homebrew ==="

export HOOK_TOOL_NAME="Bash"

export HOOK_COMMAND="brew uninstall --force node"
bash "$CHECKS_DIR/check-homebrew.sh" >/dev/null 2>&1; chk 2 $? "blocks brew uninstall --force"

export HOOK_COMMAND="brew uninstall -f node"
bash "$CHECKS_DIR/check-homebrew.sh" >/dev/null 2>&1; chk 2 $? "blocks brew uninstall -f"

export HOOK_COMMAND="brew rm --force node"
bash "$CHECKS_DIR/check-homebrew.sh" >/dev/null 2>&1; chk 2 $? "blocks brew rm --force"

export HOOK_COMMAND="brew remove --force node"
bash "$CHECKS_DIR/check-homebrew.sh" >/dev/null 2>&1; chk 2 $? "blocks brew remove --force"

export HOOK_COMMAND="brew cleanup --prune=all"
bash "$CHECKS_DIR/check-homebrew.sh" >/dev/null 2>&1; chk 2 $? "blocks brew cleanup --prune=all"

export HOOK_COMMAND="brew uninstall node"
bash "$CHECKS_DIR/check-homebrew.sh" >/dev/null 2>&1; chk 0 $? "allows brew uninstall without --force"

export HOOK_COMMAND="brew install node"
bash "$CHECKS_DIR/check-homebrew.sh" >/dev/null 2>&1; chk 0 $? "allows brew install"

export HOOK_COMMAND="brew cleanup"
bash "$CHECKS_DIR/check-homebrew.sh" >/dev/null 2>&1; chk 0 $? "allows brew cleanup without --prune=all"

export HOOK_TOOL_NAME="Bash"
export HOOK_COMMAND="brew uninstall --force"
bash "$CHECKS_DIR/check-homebrew.sh" >/dev/null 2>&1; chk 2 $? "blocks brew uninstall --force (no package name)"

export HOOK_COMMAND="brew uninstall node --force"
bash "$CHECKS_DIR/check-homebrew.sh" >/dev/null 2>&1; chk 2 $? "blocks brew uninstall with --force at end"

export HOOK_TOOL_NAME="Write"; export HOOK_COMMAND="brew uninstall --force node"
bash "$CHECKS_DIR/check-homebrew.sh" >/dev/null 2>&1; chk 0 $? "ignores non-Bash tool"

# ── git-hooks/pre-push ───────────────────────────────────────────────────────
echo ""
echo "=== git-hooks/pre-push ==="

PPHOOK="$SCRIPT_DIR/git-hooks/pre-push"
Z="0000000000000000000000000000000000000000"
S="1111111111111111111111111111111111111111"
T="2222222222222222222222222222222222222222"
RURL="git@example.com:acme/app.git"

unset GUARDRAILS_ALLOW_PUSH_PROTECTED GUARDRAILS_PROTECTED_BRANCHES

# stdin format: <local-ref> <local-sha> <remote-ref> <remote-sha>
echo "refs/heads/main $S refs/heads/main $T" \
  | bash "$PPHOOK" origin "$RURL" >/dev/null 2>&1; chk 1 $? "blocks git push origin main"

echo "refs/heads/master $S refs/heads/master $T" \
  | bash "$PPHOOK" origin "$RURL" >/dev/null 2>&1; chk 1 $? "blocks push to master"

# the regression this guard exists for: bare `git push`, upstream is origin/main
echo "refs/heads/feature/x $S refs/heads/main $T" \
  | bash "$PPHOOK" origin "$RURL" >/dev/null 2>&1; chk 1 $? "blocks bare push whose upstream is main"

echo "HEAD $S refs/heads/main $T" \
  | bash "$PPHOOK" origin "$RURL" >/dev/null 2>&1; chk 1 $? "blocks git push origin HEAD:main"

echo "(delete) $Z refs/heads/main $T" \
  | bash "$PPHOOK" origin "$RURL" >/dev/null 2>&1; chk 1 $? "blocks deletion of main"

printf 'refs/heads/feature/x %s refs/heads/feature/x %s\nrefs/heads/feature/y %s refs/heads/main %s\n' \
  "$S" "$T" "$S" "$T" \
  | bash "$PPHOOK" origin "$RURL" >/dev/null 2>&1; chk 1 $? "blocks multi-ref push where one ref is main"

echo "refs/heads/feature/x $S refs/heads/feature/x $T" \
  | bash "$PPHOOK" origin "$RURL" >/dev/null 2>&1; chk 0 $? "allows push to a feature branch"

echo "refs/heads/maintenance $S refs/heads/maintenance $T" \
  | bash "$PPHOOK" origin "$RURL" >/dev/null 2>&1; chk 0 $? "allows branch merely prefixed with main"

echo "refs/tags/v1.0.0 $S refs/tags/v1.0.0 $Z" \
  | bash "$PPHOOK" origin "$RURL" >/dev/null 2>&1; chk 0 $? "allows tag push"

printf '' | bash "$PPHOOK" origin "$RURL" >/dev/null 2>&1; chk 0 $? "allows empty ref list"

echo "refs/heads/main $S refs/heads/main $T" \
  | GUARDRAILS_ALLOW_PUSH_PROTECTED=1 bash "$PPHOOK" origin "$RURL" >/dev/null 2>&1
chk 0 $? "override env allows deliberate push to main"

echo "refs/heads/develop $S refs/heads/develop $T" \
  | GUARDRAILS_PROTECTED_BRANCHES="develop" bash "$PPHOOK" origin "$RURL" >/dev/null 2>&1
chk 1 $? "custom protected list blocks develop"

echo "refs/heads/main $S refs/heads/main $T" \
  | GUARDRAILS_PROTECTED_BRANCHES="develop" bash "$PPHOOK" origin "$RURL" >/dev/null 2>&1
chk 0 $? "custom protected list allows main"

# ── summary ──────────────────────────────────────────────────────────────────
echo ""
echo "======================================="
printf "  Results: %d passed, %d failed\n" "$PASS" "$FAIL"
echo "======================================="
echo ""
[ $FAIL -gt 0 ] && exit 1 || exit 0
