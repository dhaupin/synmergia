## spy_node.gd - test-only input stream logger (attached by test_touch_live.gd).
## Also watches the polled "attack" action every frame: presses injected
## via Input.action_press() bypass the event stream, so the _input logger
## alone cannot see them (the ghost attack press that broke P5 was of
## exactly that kind).
extends Node

var _last_attack: bool = false
var _phase: String = "boot"

func set_phase(p: String) -> void:
	_phase = p

func _input(event: InputEvent) -> void:
	if event is InputEventAction \
			or event is InputEventKey \
			or event is InputEventMouseButton \
			or event is InputEventScreenTouch:
		print("[spy t=%.2f] %s" % [Time.get_ticks_msec() / 1000.0, event.as_text()])
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		print("[spy-dev t=%.2f] mouse device=%d button=%d pressed=%s" % [
			Time.get_ticks_msec() / 1000.0, mb.device, mb.button_index, str(mb.pressed)])
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		print("[spy-dev t=%.2f] touch device=%d idx=%d pressed=%s" % [
			Time.get_ticks_msec() / 1000.0, st.device, st.index, str(st.pressed)])

func _process(_delta: float) -> void:
	var now := Input.is_action_pressed("attack")
	if now != _last_attack:
		print("[ghost t=%.2f phase=%s] attack action %s" % [
			Time.get_ticks_msec() / 1000.0, _phase, ("PRESSED" if now else "RELEASED")])
		_last_attack = now
