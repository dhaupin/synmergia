## Globe driver - the full real-flow pass on the spherical world
## (prd-spherical-mvp.md, part 2). Boots the actual menu flow like a
## player, with the shape knob flipped so the spherical world loads,
## then walks the globe and HUD-panels on it.
##
## Run rendered (real 3D flow; headless skips the world scene):
##   GODOT_PROBE_XVFB=1 xvfb-run -a godot --path game --script res://tests/globe_driver.gd
## Shots: /tmp/play/globe_flow_*.png
##
## DELEGATION REQUIRED: the flow stages + awaits live on a plain Node
## runner (globe_driver_runner.gd) spawned here into the tree. A
## SceneTree-script coroutine STRANDS the moment the world boot's
## suspended signal handler (StarterKitService's deferred grant timer)
## returns -- Godot 4.7.2 does not resume SceneTree-script awaits after
## a suspended signal handler unwinds, so this script's flow stopped at
## stage 4 in every xvfb run. The node-based runner resumes across
## that boundary and prints the verdict + exit code itself.
extends SceneTree

var _fail: String = ""


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("/tmp/play")
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await process_frame

	# Rendered-only: GameManager skips world scene loads in headless
	# mode (no render context), so the flow cannot be exercised here.
	# Self-skip honestly instead of failing.
	if DisplayServer.get_name() == "headless":
		print("GLOBEDRIVER SKIP: rendered-only test (xvfb-run / full godot)")
		quit(0)
		return

	# Spherical world on (the S2 knob; GameManager branches on it).
	ProjectSettings.set_setting("synmergia/world/shape", "spherical")

	# Spawn the node-based runner and hand the whole flow over.
	var Runner := load("res://tests/globe_driver_runner.gd")
	var runner: Node = Runner.new()
	runner.name = "GlobeDriverRunner"
	root.add_child(runner)
	# The runner runs its own staged flow + verdict; this script just
	# stays alive until the runner quits the tree.
