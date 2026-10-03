#!/bin/bash
#
# The keyboard-backlight system-sleep hook turns an ASUS backlight off before
# hibernation and must turn it back on after resume, through the same
# omarchy-brightness-keyboard off/restore the lock screen uses. Its migration
# must refresh only an unmodified copy of the previous hook.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

hook="$ROOT/default/systemd/system-sleep/keyboard-backlight"
migration="$ROOT/migrations/1790666054.sh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

stub_bin="$test_dir/bin"
calls="$test_dir/calls"
mkdir -p "$stub_bin"

cat >"$stub_bin/omarchy-brightness-keyboard" <<'STUB'
#!/bin/bash
echo "$*" >>"${CALLS:?}"
STUB
chmod +x "$stub_bin/omarchy-brightness-keyboard"

# Run a copy pointed at a fake LED class, so the shipped hook keeps its fixed path.
leds="$test_dir/leds"
hook_copy="$test_dir/keyboard-backlight"
mkdir -p "$leds/asus::kbd_backlight"
sed "s|/sys/class/leds/|$leds/|" "$hook" >"$hook_copy"

run_hook() {
  : >"$calls"
  CALLS="$calls" SYSTEMD_SLEEP_ACTION="$3" PATH="$stub_bin:$PATH" bash "$hook_copy" "$1" "$2" ||
    fail "hook exits cleanly for $1 $2 ${3:-}"
  paste -sd, "$calls"
}

[[ $(grep -Fc '/sys/class/leds/' "$hook") == 1 && $(grep -Fc "$leds/" "$hook_copy") == 1 ]] ||
  fail "hook copy points at the fake LED class"
[[ $(run_hook pre suspend-then-hibernate hibernate) == "off" ]] ||
  fail "hook turns the backlight off before the hibernate phase"
[[ $(run_hook post suspend-then-hibernate hibernate) == "restore" ]] ||
  fail "hook restores the backlight after the hibernate phase"
[[ $(run_hook pre hibernate "") == "off" && $(run_hook post hibernate "") == "restore" ]] ||
  fail "hook falls back to its second argument without SYSTEMD_SLEEP_ACTION"
for action in suspend suspend-after-failed-hibernate; do
  [[ -z $(run_hook pre suspend-then-hibernate "$action") && -z $(run_hook post suspend-then-hibernate "$action") ]] ||
    fail "hook leaves the backlight alone for $action"
done
pass "hook pairs off before hibernation with restore after it"

# Only the ASUS controller hangs S4, so other keyboards, and machines with none, are left alone.
rm -rf "$leds"/*
mkdir -p "$leds/dell::kbd_backlight"
[[ -z $(run_hook pre hibernate hibernate) && -z $(run_hook post hibernate hibernate) ]] ||
  fail "hook leaves a non-ASUS keyboard backlight alone"
rm -rf "$leds"/*
[[ -z $(run_hook pre hibernate hibernate) && -z $(run_hook post hibernate hibernate) ]] ||
  fail "hook does nothing without a keyboard backlight"
mkdir -p "$leds/asus:rgb:kbd_backlight"
[[ $(run_hook pre hibernate hibernate) == "off" ]] ||
  fail "hook recognises every ASUS keyboard LED name"
pass "hook acts only on an ASUS keyboard backlight"

# The migration replaces only an unmodified copy of the previous hook.
sleep_dir="$test_dir/system-sleep"
installed="$sleep_dir/keyboard-backlight"
migration_copy="$test_dir/migration.sh"
mkdir -p "$sleep_dir"

[[ $(grep -Fxc 'hook=/usr/lib/systemd/system-sleep/keyboard-backlight' "$migration") == 1 ]] ||
  fail "migration names one literal hook path"
sed \
  -e "s|hook=/usr/lib/systemd/system-sleep/keyboard-backlight|hook=$installed|" \
  -e "s|/usr/bin/install -m 0755 -o root -g root|/usr/bin/install -m 0755|" \
  "$migration" >"$migration_copy"

cat >"$stub_bin/sudo" <<'STUB'
#!/bin/bash
exec "$@"
STUB
chmod +x "$stub_bin/sudo"

run_migration() {
  OMARCHY_PATH="$ROOT" PATH="$stub_bin:$PATH" bash -euo pipefail "$migration_copy" >/dev/null
}

cat >"$installed" <<'PREVIOUS'
#!/bin/bash

# Turn off keyboard backlight before hibernate to prevent hang on power-off.
# The ASUS keyboard controller can block S4 shutdown if LEDs are active.

sleep_action=${SYSTEMD_SLEEP_ACTION:-$2}

if [[ $1 == "pre" && $sleep_action == "hibernate" ]]; then
  device=""
  for candidate in /sys/class/leds/*kbd_backlight*; do
    if [[ -e "$candidate" ]]; then
      device="$(basename "$candidate")"
      break
    fi
  done

  if [[ -n "$device" ]]; then
    brightnessctl -d "$device" set 0 >/dev/null 2>&1
  fi
fi
PREVIOUS
chmod 0755 "$installed"

run_migration || fail "migration runs against the previous stock hook"
cmp -s "$hook" "$installed" || fail "migration installs the current hook over the previous stock copy"
[[ $(stat -c '%a' "$installed") == 755 ]] || fail "migration keeps the hook executable"
run_migration || fail "migration reruns cleanly"
cmp -s "$hook" "$installed" || fail "migration is idempotent"
pass "migration refreshes the previous stock hook"

printf '#!/bin/bash\n# local change\n' >"$installed"
run_migration || fail "migration runs against a modified hook"
[[ $(<"$installed") == $'#!/bin/bash\n# local change' ]] || fail "migration leaves a modified hook alone"
rm "$installed"
run_migration || fail "migration runs without hibernation set up"
[[ ! -e $installed ]] || fail "migration does not install the hook where hibernation was never set up"
pass "migration leaves modified and absent hooks alone"
