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
	lab.call("_apply_generation_settings")
	await _wait_process_frames(5)

	var car: RigidBody3D = lab.get_node("ArcadeCar") as RigidBody3D
	car.call("apply_handling_preset", "SPORT")
	car.call("set_driver_active", true)
	Input.action_press(&"move_forward")
	await _wait_physics_frames(180)
	var speed_before_turn: float = float(car.call("speed_kph"))
	_check(speed_before_turn > 80.0, "car reaches the high-speed steering test range")

	var heading_before_turn: float = car.rotation.y
	Input.action_press(&"move_left", 1.0)
	await _wait_physics_frames(90)
	var heading_change: float = absf(angle_difference(heading_before_turn, car.rotation.y))
	var signed_heading_change: float = angle_difference(heading_before_turn, car.rotation.y)
	var rear_grip_during_turn: float = float(car.call("get_rear_grip_average"))
	var slip_during_turn: float = float(car.call("get_max_wheel_slip"))
	var forward_speed: float = absf(car.linear_velocity.dot(-car.global_transform.basis.z.normalized()))
	var lateral_speed: float = absf(car.linear_velocity.dot(car.global_transform.basis.x.normalized()))
	var body_slip_angle: float = rad_to_deg(atan2(lateral_speed, max(forward_speed, 0.01)))
	print(
		"HIGH_SPEED_STEERING speed_kph=%.1f rear_grip=%.3f max_slip=%.3f lateral=%.3f demand=%.3f yaw_rate=%.3f body_slip_deg=%.2f heading_deg=%.2f" % [
			float(car.call("speed_kph")),
			rear_grip_during_turn,
			slip_during_turn,
			float(car.call("get_max_lateral_slip")),
			float(car.call("get_max_demand_slip")),
			absf(car.angular_velocity.y),
			body_slip_angle,
			rad_to_deg(heading_change),
		]
	)
	print("HIGH_SPEED_STEERING_WHEELS lateral=%s demand=%s grip=%s" % [
		str(car.get("_wheel_lateral_slip")),
		str(car.get("_wheel_demand_slip")),
		str(car.get("_wheel_grip")),
	])
	print("HIGH_SPEED_STEERING_DIRECTION heading=%.3f steering=%.4f yaw=%.4f" % [
		signed_heading_change,
		float(car.get("_steering_angle")),
		car.angular_velocity.y,
	])
	_check(not bool(car.get("drifting")), "ordinary steering does not enter the handbrake drift state")
	_check(rear_grip_during_turn > 0.90, "ordinary high-speed steering preserves rear grip")
	_check(body_slip_angle < 10.0, "ordinary high-speed steering keeps the chassis aligned with its travel")
	_check(heading_change > deg_to_rad(28.0), "full steering produces a clearly visible course change within 1.5 seconds")

	Input.action_release(&"move_left")
	Input.action_release(&"move_forward")
	world.queue_free()
	await _wait_process_frames(2)
	if _failures.is_empty():
		print("VERIFY_HIGH_SPEED_STEERING PASS")
		quit(0)
	else:
		for failure: String in _failures:
			push_error("VERIFY_HIGH_SPEED_STEERING FAIL: " + failure)
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
