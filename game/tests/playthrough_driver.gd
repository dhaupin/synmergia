## Playthrough driver - the full real gameplay loop on the planar world
## (spawn -> target -> kill -> loot -> equip -> repair -> NPC menu), driven
## through the game's own input pipeline and asserted on live node state.
##
## Run rendered (real 3D + screenshots):
##   xvfb-run -a godot --path game --script res://tests/playthrough_driver.gd
## Headless also boots the world, so the loop runs either way:
##   godot --headless --path game --script res://tests/playthrough_driver.gd
## Shots: /tmp/play/playthrough_*.png
##
## DELEGATION REQUIRED: the world boot's suspended signal handler
## (StarterKitService's deferred grant timer) strands SceneTree-script awaits
## in Godot 4.7.2, so the staged flow lives on a plain Node runner
## (playthrough_driver_runner.gd) spawned into the tree here. See
## globe_driver.gd for the same pattern.
extends SceneTree

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("/tmp/play")
	_run.call_deferred()

func _run() -> void:
	await process_frame
	await process_frame
	var Runner := load("res://tests/playthrough_driver_runner.gd")
	var runner: Node = Runner.new()
	runner.name = "PlaythroughDriverRunner"
	root.add_child(runner)
