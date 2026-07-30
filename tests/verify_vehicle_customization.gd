extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed_scene: PackedScene = load("res://main.tscn") as PackedScene
	var world: Node = packed_scene.instantiate()
	root.add_child(world)
	await _wait_process_frames(6)

	var lab: Node = world.get_node("MovementLab")
	var seed_input: SpinBox = lab.get("_seed_input") as SpinBox
	seed_input.value = -129935.0
	var mass_input: SpinBox = lab.get("_mass_input") as SpinBox
	if mass_input:
		mass_input.value = 1475.0
	lab.call("_apply_generation_settings")
	await _wait_process_frames(5)
	var car: RigidBody3D = lab.get_node("ArcadeCar") as RigidBody3D

	_check(car.has_node("VisualRoot/Wheel_0/RollPivot"), "wheel steering and rolling use separate transform pivots")
	_check(car.has_method("apply_handling_preset"), "car exposes reusable handling presets")
	_check(car.has_method("get_skid_mark_count"), "car exposes slip-driven skid mark diagnostics")
	_check(car.has_method("get_rear_grip_average"), "car exposes gradual tire-grip state")
	_check(car.has_method("get_max_wheel_slip"), "car exposes measured braking and cornering slip")
	_check(car.get("park_when_unoccupied") == true, "unoccupied parking is configurable and enabled by default")
	_check(is_equal_approx(car.mass, 1475.0), "custom mass setting applies to the real rigid body")

	var parked_start: Vector3 = car.global_position
	await _wait_physics_frames(90)
	_check(car.global_position.distance_to(parked_start) < 0.02, "unoccupied car stays parked on a slope")

	if car.has_method("apply_handling_preset"):
		car.call("apply_handling_preset", "SPORT")
	_check(is_equal_approx(car.mass, 1150.0), "sport profile applies its real rigid-body mass")
	car.call("set_driver_active", true)
	Input.action_press("move_forward")
	await _wait_physics_frames(180)
	var front_steer_pivot: Node3D = car.get_node("VisualRoot/Wheel_0") as Node3D
	var front_roll_pivot: Node3D = car.get_node("VisualRoot/Wheel_0/RollPivot") as Node3D
	_check(absf(front_roll_pivot.rotation.x) > 0.01, "wheel rolling animates around the dedicated local X axis")
	_check(absf(front_roll_pivot.rotation.y) < 0.001 and absf(front_roll_pivot.rotation.z) < 0.001, "wheel rolling does not contaminate steering axes")
	print("SPORT_TELEMETRY speed_kph=%.1f contacts=%d rear_grip=%.2f" % [float(car.call("speed_kph")), int(car.call("get_wheel_contact_count")), float(car.call("get_rear_grip_average"))])
	_check(float(car.call("speed_kph")) > 80.0, "sport preset reaches fast-game speed promptly")
	_check(float(car.call("get_rear_grip_average")) > 0.88, "normal acceleration keeps stable rear grip")

	Input.action_release("move_forward")
	Input.action_press("move_back")
	Input.action_press("move_left")
	await _wait_physics_frames(18)
	_check(absf(front_steer_pivot.rotation.y) > 0.01, "front wheel steering animates around the dedicated local Y axis")
	_check(absf(front_steer_pivot.rotation.x) < 0.001 and absf(front_steer_pivot.rotation.z) < 0.001, "front steering does not contaminate rolling axes")
	if car.has_method("get_max_wheel_slip"):
		_check(float(car.call("get_max_wheel_slip")) > 0.25, "hard braking while turning produces tire slip")
	if car.has_method("get_skid_mark_count"):
		_check(int(car.call("get_skid_mark_count")) > 0, "hard braking can leave skid marks without the drift key")
	Input.action_release("move_back")
	Input.action_release("move_left")
	Input.action_press("move_forward")
	await _wait_physics_frames(35)

	Input.action_press("move_left")
	Input.action_press("drift")
	await _wait_physics_frames(35)
	Input.action_release("drift")
	await _wait_physics_frames(2)
	var grip_after_release: float = 1.0
	if car.has_method("get_rear_grip_average"):
		grip_after_release = float(car.call("get_rear_grip_average"))
	_check(grip_after_release < 0.9, "rear grip does not snap back immediately after a drift")
	if car.has_method("get_skid_mark_count"):
		_check(int(car.call("get_skid_mark_count")) > 0, "actual wheel slip leaves black skid marks")

	Input.action_release("move_left")
	Input.action_release("move_forward")
	await _wait_physics_frames(90)
	if car.has_method("get_rear_grip_average"):
		_check(float(car.call("get_rear_grip_average")) > grip_after_release, "rear grip recovers progressively")

	world.queue_free()
	await _wait_process_frames(2)
	if _failures.is_empty():
		print("VERIFY_VEHICLE_CUSTOMIZATION PASS")
		quit(0)
	else:
		for failure: String in _failures:
			push_error("VERIFY_VEHICLE_CUSTOMIZATION FAIL: " + failure)
		quit(1)


func _wait_physics_frames(count: int) -> void:
	for _index: int in range(count):
		await physics_frame


func _wait_process_frames(count: int) -> void:
	for _index: int in range(count):
		await process_frame


func _check(condition: bool, message: String) -> void:
	if not condition and not _failures.has(message):
		_failures.append(message)
