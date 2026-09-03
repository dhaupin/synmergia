# Docker — Headless Smoke Tests

Run the Godot smoke test suite inside a Docker container, no GPU or display required.

## Quick Start

```bash
# Build the unified image (includes test tooling)
docker build -t synmergia .

# Run all smoke tests
docker run --rm -e START_MODE=test synmergia

# Run only notification-related tests
docker run --rm synmergia bash -c 'TEST_FILTER=notification /usr/local/bin/test-headless.sh'
```

## Test Modes

The entrypoint handles test execution:

```bash
# Via START_MODE (built into the unified image)
docker run --rm synmergia test

# Via the test-headless.sh script (run inside any container with Godot)
docker run --rm synmergia /usr/local/bin/test-headless.sh

# With TEST_FILTER
docker run --rm synmergia bash -c 'TEST_FILTER=notification /usr/local/bin/test-headless.sh'
```

## Running Tests from Host (No Docker)

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
