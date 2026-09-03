# Docker — Headless Smoke Tests

Run the Godot smoke test suite inside a Docker container, no GPU or display required.

## Quick Start

```bash
# Build the test image
docker build -f Dockerfile.test-headless -t synmergia:test .

# Run all smoke tests
docker run --rm synmergia:test

# Run only notification-related tests
docker run --rm synmergia:test notification
```

## Running Without Rebuilding

If you just want to run tests using the Godot binary already built (e.g. in
`tools/`), mount the project directory from the host:

```bash
docker build -f Dockerfile.test-headless -t synmergia:test .

docker run --rm \
  -v "$(pwd)/synmergia:/workspace/project/synmergia:ro" \
  synmergia:test
```

## On the Host (No Docker)

If Godot is installed locally, run the script directly:

```bash
GODOT=godot ./docker/test-headless.sh

# Or filter to specific tests
TEST_FILTER=notification GODOT=godot ./docker/test-headless.sh
```

## Test Coverage

| Test | Coverage |
|------|----------|
| `test_notification_frame.gd` | NotificationService frame (context, kind, dedupe) |
| `test_notification_toast.gd` | NotificationService → TooltipManager pipeline |
| `test_auto_response_signals.gd` | AutoResponseService signals and ActionType enum |
| `test_hud_integration.gd` | HudIntegrator handlers, CombatLog |
| `test_login_flow.gd` | Account + login + character flow |
| `test_islands.gd` | Core island logic (island_poc.gd) |

**Total: ~47 cases across 6 test files.**

Exit codes: `0` = all pass, `1` = one or more failed, `2` = Godot not found / error.
