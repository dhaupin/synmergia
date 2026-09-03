## Smoke tests for the Islands system.
##
## Run with:
##   godot --headless --quit-after 1 res://tests/test_islands.gd
##
## These tests do not boot the full project; they instantiate the
## registry, placeholder, and manager in a fresh SceneTree and verify
## the public API behaves as documented.
extends SceneTree

const _placeholder_scene := preload("res://ui/islands/island_placeholder.gd")
const _manager_scene := preload("res://ui/islands/island_manager.gd")
const _registry_scene := preload("res://ui/islands/island_registry.gd")

var _passed := 0
var _failed := 0


func _initialize() -> void:
	print("\n=== Islands POC tests ===\n")

	_test_registry_resolve_known()
	_test_registry_resolve_unknown()
	_test_registry_has()
	_test_registry_all_names()
	_test_registry_triggers()
	_test_placeholder_defaults()
	_test_placeholder_lifecycle()
	_test_manager_skips_empty_name()
	_test_manager_skips_unknown_island()
	_test_manager_idempotent()

	print("\n=== Results: %d passed, %d failed ===\n" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


# ---------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------

func _test_registry_resolve_known() -> void:
	var scene := IslandRegistry.resolve("cooldown_bar")
	_assert(scene != null, "registry resolves 'cooldown_bar'")


func _test_registry_resolve_unknown() -> void:
	var scene := IslandRegistry.resolve("not_a_real_island")
	_assert(scene == null, "registry returns null for unknown island")


func _test_registry_has() -> void:
	_assert(IslandRegistry.has("cooldown_bar"), "registry.has() returns true for known")
	_assert(not IslandRegistry.has("not_a_real_island"), "registry.has() returns false for unknown")


func _test_registry_all_names() -> void:
	var names := IslandRegistry.all_names()
	_assert(names.size() >= 8, "registry has at least 8 wired islands, got %d" % names.size())
	_assert("cooldown_bar" in names, "registry names includes 'cooldown_bar'")


func _test_registry_triggers() -> void:
	var triggered := IslandRegistry.islands_triggered_by("open my inventory please")
	_assert("inventory" in triggered, "'inventory' trigger fires for chat input")

	var trade_triggered := IslandRegistry.islands_triggered_by("/trade with Bob")
	_assert("trade" in trade_triggered, "'trade' trigger fires for chat input")

	var no_trigger := IslandRegistry.islands_triggered_by("hello world")
	_assert(no_trigger.is_empty(), "no triggers fire for generic input")


func _test_placeholder_defaults() -> void:
	var p := _placeholder_scene.new()
	root.add_child(p)
	_assert(p.island_name == "", "placeholder default name is empty")
	_assert(p.load_strategy == "eager", "placeholder default strategy is 'eager'")
	_assert(not p.is_mounted(), "placeholder starts unmounted")
	p.queue_free()


func _test_placeholder_lifecycle() -> void:
	var p := _placeholder_scene.new()
	p.island_name = "cooldown_bar"
	p.load_strategy = "eager"
	root.add_child(p)
	_assert(not p.is_mounted(), "placeholder is unmounted before mark")
	p.mark_mounted()
	_assert(p.is_mounted(), "placeholder is mounted after mark")
	p.queue_free()


func _test_manager_skips_empty_name() -> void:
	# Build a fresh sub-tree to isolate from prior tests' placeholders.
	var mgr := _manager_scene.new()
	var subtree := Node.new()
	root.add_child(subtree)
	subtree.add_child(mgr)

	var p := _placeholder_scene.new()
	p.island_name = ""
	subtree.add_child(p)

	var skipped: Array = []
	mgr.island_skipped.connect(func(name: String, reason: String) -> void:
		skipped.append([name, reason])
	)

	var count := mgr.mount_placeholders(subtree)
	_assert(count == 0, "manager mounts 0 when name is empty (got %d)" % count)
	_assert(skipped.size() >= 1, "manager emits at least one island_skipped for empty name (got %d)" % skipped.size())
	mgr.queue_free()


func _test_manager_skips_unknown_island() -> void:
	var mgr := _manager_scene.new()
	var subtree := Node.new()
	root.add_child(subtree)
	subtree.add_child(mgr)

	var p := _placeholder_scene.new()
	p.island_name = "definitely_not_real"
	subtree.add_child(p)

	var count := mgr.mount_placeholders(subtree)
	_assert(count == 0, "manager mounts 0 for unknown island")
	mgr.queue_free()


func _test_manager_idempotent() -> void:
	var mgr := _manager_scene.new()
	root.add_child(mgr)
	var p := _placeholder_scene.new()
	p.island_name = "cooldown_bar"
	p.load_strategy = "eager"
	root.add_child(p)

	# Note: we don't actually run mount_placeholders here because the
	# cooldown_bar.tscn scene may have its own autoload dependencies
	# that fail in a minimal SceneTree. Just verify the marker works.
	p.mark_mounted()
	_assert(p.is_mounted(), "placeholder is mounted after first mark")
	# Calling mount again should be a no-op
	var count := mgr.mount_placeholders(root)
	_assert(count == 0, "manager does not re-mount already-mounted placeholders")
	mgr.queue_free()


# ---------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------

func _assert(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("  [PASS] %s" % label)
	else:
		_failed += 1
		print("  [FAIL] %s" % label)
