extends Node


func _ready() -> void:
	var packed_scene: PackedScene = load("res://main.tscn") as PackedScene
	var world: Node = packed_scene.instantiate()
	add_child(world)
	for _index: int in range(6):
		await get_tree().process_frame
	var lab: Node = world.get_node("MovementLab")
	var controls: Control = lab.get_node("MovementHUD/Root/MobileControls") as Control
	controls.call("set_force_visible_for_testing", true)
	lab.call("_apply_generation_settings")
	for _index: int in range(4):
		await get_tree().process_frame
	var player: CharacterBody3D = lab.get_node("Player") as CharacterBody3D
	var car: RigidBody3D = lab.get_node("ArcadeCar") as RigidBody3D
	player.global_position = car.global_position + car.global_transform.basis.x * 2.0
	lab.call("_toggle_vehicle")
