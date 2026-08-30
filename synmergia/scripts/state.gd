## State - Base state class for the state machine
class_name State
extends Node

const StateMachine = preload("res://scripts/state_machine.gd")
var state_machine: StateMachine

func enter(_data: Dictionary = {}) -> void:
	pass

func exit() -> void:
	pass

func update(_delta: float) -> void:
	pass

func physics_update(_delta: float) -> void:
	pass
