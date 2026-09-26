#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

new_home() {
  local home="$test_tmp/$1"
  mkdir -p "$home/.config"
  printf '%s\n' "$home"
}

# omarchy-agent starts in the projects directory when launched from $HOME
mock_bin="$test_tmp/bin"
mkdir -p "$mock_bin"
cat >"$mock_bin/omarchy-default-agent" <<'SH'
#!/bin/bash
echo pi
SH
cat >"$mock_bin/pi" <<'SH'
#!/bin/bash
pwd >"$OMARCHY_TEST_AGENT_CWD"
SH
chmod +x "$mock_bin/omarchy-default-agent" "$mock_bin/pi"

agent_cwd() {
  local home=$1
  rm -f "$test_tmp/agent-cwd"
  (
    cd "$home"
    env -u XDG_PROJECTS_DIR HOME="$home" PATH="$mock_bin:$ROOT/bin:$PATH" \
      OMARCHY_TEST_AGENT_CWD="$test_tmp/agent-cwd" omarchy-agent --inline
  )
  cat "$test_tmp/agent-cwd"
}

home=$(new_home agent-work)
mkdir -p "$home/Work"
printf 'XDG_PROJECTS_DIR="$HOME/Work"\n' >"$home/.config/user-dirs.dirs"
[[ $(agent_cwd "$home") == "$home/Work" ]] || fail "agent starts in the configured projects directory"

home=$(new_home agent-default)
mkdir -p "$home/Projects"
[[ $(agent_cwd "$home") == "$home/Projects" ]] || fail "agent starts in ~/Projects when no key is set"

home=$(new_home agent-missing)
printf 'XDG_PROJECTS_DIR="$HOME/Gone"\n' >"$home/.config/user-dirs.dirs"
[[ $(agent_cwd "$home") == "$home" ]] || fail "agent stays in \$HOME when the projects directory is missing"

home=$(new_home agent-reset)
printf 'XDG_PROJECTS_DIR="$HOME/"\n' >"$home/.config/user-dirs.dirs"
[[ $(agent_cwd "$home") == "$home" ]] || fail "agent stays in \$HOME when the key was reset to it"
pass "agent launcher starts in the projects directory from \$HOME"

# The migration keeps ~/Work as the projects directory on existing installs
require_command xdg-user-dirs-update

migration=$(grep -lF 'Keep ~/Work as the projects directory' "$ROOT"/migrations/*.sh)
[[ -n $migration ]] || fail "projects directory migration exists"

migrate() {
  local home=$1
  env -u XDG_PROJECTS_DIR HOME="$home" XDG_CONFIG_HOME="$home/.config" \
    bash -euo pipefail "$migration" >>"$home/migration.log"
}

projects_key() {
  local home=$1
  grep '^XDG_PROJECTS_DIR=' "$home/.config/user-dirs.dirs"
}

# Runs the switch command the migration printed, as the user would paste it
run_switch_hint() {
  local home=$1
  local hint
  hint=$(grep -F 'mv -T' "$home/migration.log") || fail "migration prints the switch command"
  env -u XDG_PROJECTS_DIR HOME="$home" XDG_CONFIG_HOME="$home/.config" bash -c "$hint" 2>/dev/null
}

home=$(new_home only-work)
mkdir -p "$home/Work/app"
migrate "$home"
[[ $(projects_key "$home") == 'XDG_PROJECTS_DIR="$HOME/Work"' ]] || fail "existing ~/Work becomes the projects directory"
[[ -d $home/Work/app && ! -e $home/Projects ]] || fail "migration leaves ~/Work in place and creates no ~/Projects"
migrate "$home"
[[ $(projects_key "$home") == 'XDG_PROJECTS_DIR="$HOME/Work"' ]] || fail "rerunning the migration keeps ~/Work"
pass "installs with ~/Work keep it as the projects directory"

run_switch_hint "$home" || fail "the switch command moves ~/Work to ~/Projects"
[[ -d $home/Projects/app && ! -e $home/Work ]] || fail "the switch command renames ~/Work to ~/Projects"
[[ $(projects_key "$home") == 'XDG_PROJECTS_DIR="$HOME/Projects"' ]] || fail "the switch command points the key at ~/Projects"
pass "the printed switch command moves ~/Work to ~/Projects"

home=$(new_home both-empty)
mkdir -p "$home/Work/app" "$home/Projects"
migrate "$home"
run_switch_hint "$home" || fail "the switch command replaces an empty ~/Projects"
[[ -d $home/Projects/app && ! -e $home/Projects/Work ]] || fail "the switch command never nests ~/Work inside ~/Projects"
pass "the switch command replaces an empty ~/Projects"

home=$(new_home both)
mkdir -p "$home/Work/app" "$home/Projects/other"
printf 'XDG_PROJECTS_DIR="$HOME/Projects"\n' >"$home/.config/user-dirs.dirs"
migrate "$home"
[[ $(projects_key "$home") == 'XDG_PROJECTS_DIR="$HOME/Work"' ]] || fail "~/Work wins over the xdg-user-dirs ~/Projects default"
[[ -d $home/Work/app && -d $home/Projects/other ]] || fail "migration leaves both directories in place"
! run_switch_hint "$home" || fail "the switch command refuses a ~/Projects that has files"
[[ -d $home/Work/app && -d $home/Projects/other && ! -e $home/Projects/Work ]] ||
  fail "a refused switch leaves both directories as they were"
[[ $(projects_key "$home") == 'XDG_PROJECTS_DIR="$HOME/Work"' ]] || fail "a refused switch keeps the key on ~/Work"
pass "with both ~/Work and a used ~/Projects, the switch command refuses and changes nothing"

home=$(new_home reset)
mkdir -p "$home/Work"
printf 'XDG_PROJECTS_DIR="$HOME/"\n' >"$home/.config/user-dirs.dirs"
migrate "$home"
[[ $(projects_key "$home") == 'XDG_PROJECTS_DIR="$HOME/Work"' ]] || fail "a key reset to the home directory is repaired"
pass "a projects key xdg-user-dirs reset to \$HOME is repaired"

home=$(new_home custom)
mkdir -p "$home/Work" "$home/code"
printf 'XDG_PROJECTS_DIR="$HOME/code"\n' >"$home/.config/user-dirs.dirs"
migrate "$home"
[[ $(projects_key "$home") == 'XDG_PROJECTS_DIR="$HOME/code"' ]] || fail "a custom projects directory is respected"
pass "a custom projects directory is left alone"

home=$(new_home no-work)
migrate "$home"
[[ $(projects_key "$home") == 'XDG_PROJECTS_DIR="$HOME/Projects"' ]] || fail "installs without ~/Work get ~/Projects"
[[ ! -e $home/Work ]] || fail "migration does not create ~/Work"
! grep -qF 'mv -T' "$home/migration.log" || fail "installs without ~/Work get no switch hint"
pass "installs without ~/Work default to ~/Projects"
