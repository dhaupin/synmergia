#!/bin/bash
cd game
out=$(timeout 120 godot --headless --path . --script res://tests/probe_world_state.gd 2>&1)
echo "$out" | grep -o "[0-9]* checks, [0-9]* failures" | tail -1
exit $(echo "$out" | grep -q "0 failures" && echo 0 || echo 1)
