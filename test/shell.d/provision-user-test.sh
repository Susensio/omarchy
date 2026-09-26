#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
mkdir -p "$mock_bin" "$test_tmp/home" "$test_tmp/home/.hermes/profiles/james"

for command in xdg-user-dirs-update xdg-settings xdg-mime; do
  printf '#!/bin/bash\nexit 0\n' >"$mock_bin/$command"
done
chmod +x "$mock_bin"/*

# Provisioning prepends $OMARCHY_PATH/bin, which shadows a mock for anything
# Omarchy ships, so the install suite is stubbed out at its path instead. The
# real one rethemes the session it runs in: hyprctl reload against the live
# compositor, gsettings against the live desktop, and a global Node install.
mkdir -p "$test_tmp/install/user"
: >"$test_tmp/install/user/all.sh"

HOME="$test_tmp/home" PATH="$mock_bin:$ROOT/bin:$PATH" OMARCHY_PATH="$ROOT" \
  OMARCHY_INSTALL="$test_tmp/install" bash "$ROOT/bin/omarchy-provision-user" >/dev/null ||
  fail "omarchy-provision-user finishes"

for skill in omarchy diagnose-crash; do
  link="$test_tmp/home/.gemini/config/skills/$skill"
  [[ -L $link && $(readlink "$link") == "$ROOT/default/agents/skills/$skill" ]] ||
    fail "omarchy-provision-user provisions the $skill skill for Antigravity"

  link="$test_tmp/home/.hermes/skills/$skill"
  [[ -L $link && $(readlink "$link") == "$ROOT/default/agents/skills/$skill" ]] ||
    fail "omarchy-provision-user provisions the $skill skill for Hermes"

  link="$test_tmp/home/.hermes/profiles/james/skills/$skill"
  [[ -L $link && $(readlink "$link") == "$ROOT/default/agents/skills/$skill" ]] ||
    fail "omarchy-provision-user provisions the $skill skill for a Hermes profile"
done

pass "omarchy-provision-user provisions Antigravity and Hermes skills"

cat >"$mock_bin/xdg-user-dirs-update" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$OMARCHY_TEST_XDG_LOG"
SH

provision_home() {
  local home=$1
  HOME="$home" PATH="$mock_bin:$ROOT/bin:$PATH" OMARCHY_PATH="$ROOT" OMARCHY_INSTALL="$test_tmp/install" \
    OMARCHY_TEST_XDG_LOG="$home/xdg.log" bash "$ROOT/bin/omarchy-provision-user" --force >/dev/null ||
    fail "omarchy-provision-user finishes"
}

fresh_home="$test_tmp/fresh-home"
mkdir -p "$fresh_home"
provision_home "$fresh_home"
grep -qxF -- "--set PROJECTS $fresh_home/Projects" "$fresh_home/xdg.log" || fail "new users get ~/Projects as XDG_PROJECTS_DIR"
[[ -d $fresh_home/Projects ]] || fail "new users get a ~/Projects directory"
pass "omarchy-provision-user creates and registers ~/Projects"

work_home="$test_tmp/work-home"
mkdir -p "$work_home/.config" "$work_home/Work"
printf 'XDG_PROJECTS_DIR="$HOME/Work"\n' >"$work_home/.config/user-dirs.dirs"
provision_home "$work_home"
! grep -q -- '--set PROJECTS' "$work_home/xdg.log" || fail "a rerun keeps the projects directory already chosen"
[[ ! -e $work_home/Projects ]] || fail "a rerun does not create ~/Projects next to the chosen directory"
pass "omarchy-provision-user --force keeps an existing projects directory"
