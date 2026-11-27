#!/usr/bin/env bash
# smoke.sh - the outside-in acceptance walk: play the wasm build by LABEL only,
# the way a screen-reader user does, and fail if the game cannot be played.
#
#   sh scripts/agent_play/smoke.sh            # local web/ export
#   TARGET=live sh scripts/agent_play/smoke.sh
#
# Every step is a label an AT would announce plus a state the game must reach.
# No step measures distance or sleeps for a fixed time: the wasm build runs at
# a few fps under software GL, so a fixed wall is a race, not a test.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${HERE}/../.." && pwd)"
PLAY="node ${HERE}/play.mjs"
TARGET="${TARGET:-local}"
STAMP="$(date +%H%M%S)"
USER_NAME="scout${STAMP}"
PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); echo "PASS: $1"; }
no() { FAIL=$((FAIL + 1)); echo "FAIL: $1"; }

# step <what> <command...>  -- runs a play command, fails on a "no:" answer
step() {
	local what="$1"
	shift
	if "$@" >/tmp/agent_play_step.log 2>&1; then
		ok "$what"
	else
		no "$what"
		sed -n '1,6p' /tmp/agent_play_step.log
	fi
}

echo "=== agent_play smoke (target=${TARGET}) ==="
# Start from a cold session: the walk assumes the boot screen, and a leftover
# session may be in the world already.
$PLAY quit >/dev/null 2>&1
rm -f "${TMPDIR:-/tmp}/syn_agent_play.json"
step "the game boots to a labelled surface" $PLAY look
step "the start button is announced"        $PLAY wait 'label:Start playing' --timeout 120
step "Start playing opens the login"        $PLAY act "Start playing"
step "the login scene arrives"              $PLAY wait 'scene:Login' --timeout 120
step "the register form opens"              $PLAY act "Create a new account"
step "the register form is announced"       $PLAY wait 'label:Create account and enter' --timeout 60
step "the username field takes a write"     $PLAY act "Username input field" --verb set_value --value "$USER_NAME"
step "the password field takes a write"     $PLAY act "Password input field" --verb set_value --value "hunter2hunter2"
step "the email field takes a write"        $PLAY act "Email input field" --verb set_value --value "${USER_NAME}@example.com"
step "registration lands in the lobby"      $PLAY act "Create account and enter"
step "the lobby offers character creation"  $PLAY wait 'label:Create New' --timeout 180
step "character creation opens"             $PLAY act "Create New"
step "species are announced"                $PLAY wait 'label:Choose Akkan' --timeout 180
step "a species is chosen"                  $PLAY act "Choose Akkan"
step "classes are announced with a role"    $PLAY wait 'label:Play Attacker' --timeout 120

# A screen reader picks a class by its announced role, so the roles must
# differ. The cards once all announced the scene placeholder ("Melee DPS").
$PLAY look >/tmp/agent_play_classes.log 2>&1
ROLES=$(grep -E '^  Play [A-Za-z]+ - ' /tmp/agent_play_classes.log \
	| sed -E 's/^  Play [A-Za-z]+ - //' | sort -u | wc -l | tr -d ' ')
if [ "${ROLES:-0}" -ge 3 ]; then
	ok "the classes announce ${ROLES} distinct roles"
else
	no "the classes announce ${ROLES} distinct roles (need >= 3)"
	grep -E '^  Play ' /tmp/agent_play_classes.log | head -6
fi
step "a class is chosen"                    $PLAY act "Play Attacker"
step "the world can be entered"             $PLAY act "Enter World"
step "the world is reached"                 $PLAY wait in_world --timeout 240
step "the body moves when told to"          $PLAY move forward
step "movement is a state transition"       $PLAY wait moving --timeout 60
step "the body stops when told to"          $PLAY halt
step "stopping is a state transition"       $PLAY wait still --timeout 60

if [ "${KEEP_SESSION:-0}" != "1" ]; then
	$PLAY quit >/dev/null 2>&1
fi

echo "=== ${PASS} passed, ${FAIL} failed ==="
[ "$FAIL" -eq 0 ] || exit 1
