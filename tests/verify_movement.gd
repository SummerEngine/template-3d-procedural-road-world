extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed_scene: PackedScene = load("res://main.tscn") as PackedScene
	var world: Node = packed_scene.instantiate()
	root.add_child(world)
	await _wait_process_frames(5)

	var lab: Node3D = world.get_node("MovementLab") as Node3D
	_check(lab.has_node("MovementHUD/Root/StartMenu"), "startup menu exists before first world generation")
	lab.call("_apply_generation_settings")
	await _wait_process_frames(4)
	var player: CharacterBody3D = lab.get_node("Player") as CharacterBody3D
	var car: RigidBody3D = lab.get_node("ArcadeCar") as RigidBody3D
	var parkour_locations: Node3D = lab.get_node("ParkourLocations") as Node3D
	var generator: ProceduralWorldGenerator = world.get_node("WorldGenerator") as ProceduralWorldGenerator
	_check(player != null and car != null, "player and car are created after generation")
	_check(parkour_locations.get_child_count() >= 3, "at least three procedural parkour locations exist")
	_check(bool(player.get("first_person")), "player starts in first-person")
	_check(player.process_mode == Node.PROCESS_MODE_PAUSABLE and car.process_mode == Node.PROCESS_MODE_PAUSABLE, "runtime actors explicitly stop processing while paused")
	var first_plot: Dictionary = generator.get_parkour_plots()[0] as Dictionary
	var first_foundation: StaticBody3D = parkour_locations.get_node("Parkour_0/GroundedFoundation") as StaticBody3D
	var foundation_shape: BoxShape3D = (first_foundation.get_node("CollisionShape3D") as CollisionShape3D).shape as BoxShape3D
	var foundation_top: float = first_foundation.global_position.y + foundation_shape.size.y * 0.5
	_check(foundation_top - float(first_plot["height"]) >= 0.16, "parkour foundation stays visibly above its level terrain plot")

	var player_start: Vector3 = player.global_position
	Input.action_press("move_forward")
	await _wait_physics_frames(30)
	Input.action_release("move_forward")
	_check(player.global_position.distance_to(player_start) > 2.0, "forward input moves the player")

	var jump_start_y: float = player.global_position.y
	Input.action_press("jump")
	await _wait_physics_frames(2)
	Input.action_release("jump")
	await _wait_physics_frames(6)
	_check(player.global_position.y > jump_start_y + 0.2, "jump input lifts the player")

	var low_block: StaticBody3D = lab.get_node("ParkourLocations/Parkour_0/MantleStep") as StaticBody3D
	var low_ground_y: float = low_block.global_position.y - 0.55
	player.global_position = low_block.global_position + low_block.global_transform.basis.z * 2.1
	player.global_position.y = low_ground_y + 0.15
	player.look_at(Vector3(low_block.global_position.x, player.global_position.y, low_block.global_position.z), Vector3.UP)
	player.velocity = Vector3(0.0, -1.0, 0.0)
	var low_mantle_started: bool = bool(player.call("_try_begin_mantle"))
	_check(low_mantle_started and bool(player.get("is_mantling")), "low ledge starts an automatic mantle")
	await _wait_physics_frames(40)
	_check(not bool(player.get("is_mantling")) and player.global_position.y > low_ground_y + 0.9, "low ledge mantle reaches the top")

	var high_block: StaticBody3D = lab.get_node("ParkourLocations/Parkour_0/TallWall") as StaticBody3D
	var high_ground_y: float = high_block.global_position.y - 1.4
	player.global_position = high_block.global_position + high_block.global_transform.basis.z * 2.1
	player.global_position.y = high_ground_y + 0.15
	player.look_at(Vector3(high_block.global_position.x, player.global_position.y, high_block.global_position.z), Vector3.UP)
	player.velocity = Vector3(0.0, -1.0, 0.0)
	_check(not bool(player.call("_try_begin_mantle")), "tall obstacle is rejected by mantle clearance")

	Input.action_press("camera_toggle")
	await _wait_process_frames(2)
	Input.action_release("camera_toggle")
	_check(not bool(player.get("first_person")), "on-foot camera toggles to third-person")

	player.global_position = car.global_position + car.global_transform.basis.x * 2.0
	player.velocity = Vector3.ZERO
	Input.action_press("interact")
	await _wait_process_frames(2)
	Input.action_release("interact")
	_check(not bool(player.get("active")) and bool(car.get("driver_active")), "interact enters the nearby car")

	var car_start: Vector3 = car.global_position
	Input.action_press("move_forward")
	await _wait_physics_frames(120)
	_check(car.global_position.distance_to(car_start) > 4.0, "throttle accelerates and moves the car")
	_check(float(car.call("speed_kph")) > 20.0, "car reaches a useful driving speed")
	_check(int(car.call("get_wheel_contact_count")) >= 2, "raycast suspension maintains wheel contact")

	var rotation_before_drift: float = car.rotation.y
	Input.action_press("move_left")
	Input.action_press("drift")
	await _wait_physics_frames(20)
	_check(bool(car.get("drifting")), "handbrake enables drift state at speed")
	_check(abs(angle_difference(rotation_before_drift, car.rotation.y)) > 0.05, "steering rotates the moving car")
	var suspension_spread: float = float(car.call("get_suspension_travel_spread"))
	var chassis_tilt: float = float(car.call("chassis_tilt_degrees"))
	print("CAR_TELEMETRY wheels=%d suspension_spread=%.3f tilt_degrees=%.2f" % [
		int(car.call("get_wheel_contact_count")), suspension_spread, chassis_tilt
	])
	_check(suspension_spread > 0.01, "independent wheel suspension responds unevenly under load")
	_check(chassis_tilt > 0.1, "rigid chassis is free to pitch or roll with terrain and tire forces")
	Input.action_release("drift")
	Input.action_release("move_left")
	Input.action_release("move_forward")

	Input.action_press("camera_toggle")
	await _wait_process_frames(2)
	Input.action_release("camera_toggle")
	_check(bool(car.get("cockpit_camera")), "car camera toggles from chase to cockpit")

	var pause_transform: Transform3D = car.global_transform
	var pause_velocity: Vector3 = car.linear_velocity
	lab.call("_show_pause_menu")
	await _wait_process_frames(20)
	_check(car.global_transform.is_equal_approx(pause_transform), "active car transform stays fixed for the whole pause")
	_check(car.linear_velocity.is_equal_approx(pause_velocity), "active car velocity does not accumulate or change during pause")
	lab.call("_resume_game")
	await _wait_physics_frames(2)

	Input.action_press("interact")
	await _wait_process_frames(2)
	Input.action_release("interact")
	_check(bool(player.get("active")) and not bool(car.get("driver_active")), "interact exits the car and restores the player")
	lab.call("_show_pause_menu")
	await _wait_process_frames(3)
	_check(paused and car.freeze, "parked car stays frozen while the game is paused")
	lab.call("_resume_game")
	await _wait_physics_frames(2)

	var reentry_height: float = car.global_position.y
	player.global_position = car.global_position + car.global_transform.basis.x * 0.5
	player.velocity = Vector3.ZERO
	lab.call("_enter_vehicle")
	_check(not bool(car.get("driver_active")), "re-entry waits for the player collider to disengage before unfreezing the car")
	await _wait_process_frames(2)
	await _wait_physics_frames(30)
	_check(bool(car.get("driver_active")), "delayed re-entry activates the parked car")
	_check(car.global_position.y - reentry_height < 1.0, "parked car does not launch upward on re-entry")
	_check(abs(car.linear_velocity.y) < 4.0, "parked car keeps bounded vertical velocity on re-entry")
	Input.action_press("interact")
	await _wait_process_frames(2)
	Input.action_release("interact")

	generator.regenerate()
	await _wait_process_frames(5)
	_check(lab.has_node("Player") and lab.has_node("ArcadeCar"), "world regeneration rebuilds the movement layer")
	_check((lab.get_node("ParkourLocations") as Node3D).get_child_count() >= 3, "world regeneration rebuilds procedural parkour locations")

	world.queue_free()
	await _wait_process_frames(2)
	if _failures.is_empty():
		print("VERIFY_MOVEMENT PASS")
		quit(0)
	else:
		for failure: String in _failures:
			push_error("VERIFY_MOVEMENT FAIL: " + failure)
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
