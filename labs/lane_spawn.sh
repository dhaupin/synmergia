#!/usr/bin/env bash
# lane_spawn.sh -- drive the OpenHands subagent lanes from the shell.
#
# The `start_child_conversation` tool is not in this profile, but the endpoint
# it wraps is reachable from inside the sandbox: the local agent server
# ($OH_INTERNAL_SERVER_URL) accepts the SESSION_API_KEY it was booted with
# (read from PID 1's environ -- the shell's own OH_LLM_API_KEY_REFRESH_HEADERS
# key is NOT the server key and returns 401).
#
#   lane_spawn.sh spawn "<task>" "<title>"      -> prints the child id
#   lane_spawn.sh spawn-file <brief.md> <title> -> spawn from a file
#   lane_spawn.sh send   <child_id> <brief.md>  -> RE-USE a finished lane: post
#                                                  the brief as the next user
#                                                  message and run it (keeps the
#                                                  lane's context; no new convo)
#   lane_spawn.sh status <child_id>             -> execution_status
#   lane_spawn.sh final  <child_id>             -> the agent's final response
#   lane_spawn.sh wait   <child_id> [tries]     -> poll until finished
#   lane_spawn.sh rm     <child_id>             -> delete the child
#
# A lane gets `isolation: worktree` (its own git checkout off the parent HEAD)
# so parallel lanes cannot collide on files. The parent merges + runs the full
# gate once at the end (shared files: runner DEFAULT_SET, AGENTS.md, TASKS.md).
set -u

SRV="${OH_INTERNAL_SERVER_URL:-http://127.0.0.1:60000}"
KEY="$(tr '\0' '\n' < /proc/1/environ 2>/dev/null | grep '^SESSION_API_KEY=' | cut -d= -f2-)"
PARENT="${OH_PARENT_CONVERSATION:-eb2b9fa00c004351addab24a36804986}"

if [ -z "$KEY" ]; then
    echo "lane_spawn: no SESSION_API_KEY in PID 1 environ" >&2
    exit 2
fi

api() { curl -s -m 120 -H "X-Session-API-Key: $KEY" -H "Accept: application/json" "$@"; }

cmd="${1:-}"; shift || true

case "$cmd" in
    spawn)
        task="$1"; title="${2:-lane}"
        body=$(python3 -c 'import json,sys;print(json.dumps({"task":sys.argv[1],"title":sys.argv[2],"isolation":"worktree"}))' "$task" "$title")
        api -X POST -H "Content-Type: application/json" -d "$body" "$SRV/api/conversations/$PARENT/children" \
            | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d.get("conversation_id") or d.get("id") or d)'
        ;;
    spawn-file)
        # spawn-file <brief.md> <title> -- the brief is read verbatim from a file
        # so multi-line, quote-heavy briefs never fight the shell.
        task="$(cat "$1")"; title="${2:-lane}"
        body=$(python3 -c 'import json,sys;print(json.dumps({"task":sys.argv[1],"title":sys.argv[2],"isolation":"worktree"}))' "$task" "$title")
        api -X POST -H "Content-Type: application/json" -d "$body" "$SRV/api/conversations/$PARENT/children" \
            | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d.get("conversation_id") or d.get("id") or d)'
        ;;
    send)
        # send <child_id> <brief.md> -- RE-USE a finished lane: append the brief
        # as the next user message and start a run, in the lane's OWN context.
        id="$1"; content="$(cat "$2")"
        body=$(python3 -c 'import json,sys;print(json.dumps({"role":"user","content":[{"type":"text","text":sys.argv[1]}],"run":True}))' "$content")
        api -X POST -H "Content-Type: application/json" -d "$body" "$SRV/api/conversations/$id/events" >/dev/null && echo "sent to $id"
        ;;
    status)
        api "$SRV/api/conversations/$1" \
            | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d.get("execution_status") or d.get("status") or d)'
        ;;
    final)
        api "$SRV/api/conversations/$1/agent_final_response" \
            | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d.get("response") if isinstance(d,dict) else d)'
        ;;
    wait)
        id="$1"; tries="${2:-60}"
        for i in $(seq 1 "$tries"); do
            st=$(api "$SRV/api/conversations/$id" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d.get("execution_status") or d.get("status") or "?")' 2>/dev/null)
            echo "  [$i] $st"
            case "$st" in finished|error|failed|stopped) break;; esac
            sleep 10
        done
        ;;
    rm)
        api -X DELETE "$SRV/api/conversations/$1" >/dev/null && echo "deleted $1"
        ;;
    *)
        echo "usage: lane_spawn.sh {spawn|status|final|wait|rm} ..." >&2
        exit 1
        ;;
esac
