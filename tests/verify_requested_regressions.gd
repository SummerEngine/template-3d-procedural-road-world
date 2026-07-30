extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed_scene: PackedScene = load("res://main.tscn") as PackedScene
	var world: Node = packed_scene.instantiate()
	root.add_child(world)
	for _index: int in range(6):
		await process_frame

	var lab: Node = world.get_node("MovementLab")
	_check(lab.has_node("MovementHUD/Root/StartMenu"), "startup menu exposes world generation settings")
	_check(lab.has_node("MovementHUD/Root/StartMenu/CenterContainer/PanelContainer/VBoxContainer/RandomSeed") or lab.has_method("_randomize_world_seed"), "startup menu exposes random seed generation")
	var seed_input: SpinBox = lab.get("_seed_input") as SpinBox
	seed_input.value = 123.0
	lab.call("_randomize_world_seed")
	_check(int(seed_input.value) != 123, "random seed action replaces the current startup seed")
	var chunk_count_input: SpinBox = lab.get("_chunk_count_input") as SpinBox
	var chunk_size_input: SpinBox = lab.get("_chunk_size_input") as SpinBox
	chunk_count_input.value = 3.0
	chunk_size_input.value = 128.0
	lab.call("_apply_generation_settings")
	for _index: int in range(4):
		await process_frame

	var player: Node = lab.get_node("Player")
	var car: Node = lab.get_node("ArcadeCar")
	var generator: ProceduralWorldGenerator = world.get_node("WorldGenerator") as ProceduralWorldGenerator
	_check(car is RigidBody3D, "car uses force-driven RigidBody3D physics")
	_check(car.has_method("get_wheel_contact_count"), "car exposes four-wheel contact diagnostics")
	_check(car.process_mode == Node.PROCESS_MODE_PAUSABLE, "car physics is explicitly pausable under the always-processing menu owner")
	_check(float(player.get("mantle_duration")) >= 0.45, "ledge mantle is deliberately readable rather than 0.24 seconds")
	_check(lab.has_method("_show_pause_menu"), "movement layer owns an Escape pause/quit flow")
	_check(is_equal_approx(generator.get_world_size(), 384.0), "startup settings control first-generation world size")
	_check(generator.get_node("TerrainChunks").get_child_count() == 9, "startup settings control generated chunk count")
	_check(lab.has_node("ParkourLocations/Parkour_0/MantleStep"), "startup cubes are replaced by generated parkour locations")

	car.call("set_driver_active", true)
	var resting_yaw: float = (car as RigidBody3D).rotation.y
	Input.action_press("move_left")
	for _index: int in range(25):
		await physics_frame
	Input.action_release("move_left")
	_check(abs(angle_difference(resting_yaw, (car as RigidBody3D).rotation.y)) < 0.02, "steering does not rotate a stationary chassis directly")
	car.call("set_driver_active", false)

	var escape_event: InputEventKey = InputEventKey.new()
	escape_event.keycode = KEY_ESCAPE
	escape_event.pressed = true
	lab.call("_unhandled_input", escape_event)
	_check(lab.get_node("MovementHUD/Root/PauseMenu").visible and paused, "Escape releases the mouse into a real pause menu")
	lab.call("_resume_game")
	_check(not paused, "resume exits pause and restores simulation")

	world.queue_free()
	await process_frame
	if _failures.is_empty():
		print("VERIFY_REQUESTED_REGRESSIONS PASS")
		quit(0)
	else:
		for failure: String in _failures:
			push_error("VERIFY_REQUESTED_REGRESSIONS FAIL: " + failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
