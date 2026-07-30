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
	var controls: Control = lab.get_node("MovementHUD/Root/MobileControls") as Control
	controls.call("set_force_visible_for_testing", true)
	lab.call("_apply_generation_settings")
	await _wait_process_frames(5)
	_check(controls.visible and bool(lab.call("is_mobile_controls_active")), "touch HUD becomes active during gameplay")
	_check(
		controls.has_node("Primary") and controls.has_node("Menu") and controls.has_node("Weather"),
		"touch HUD exposes primary, weather, and pause buttons"
	)
	var weather_button: Button = controls.get_node_or_null("Weather") as Button
	var weather_system: Node = world.get_node("WeatherSystem")
	var weather_before: int = int(weather_system.get("_weather_index"))
	if weather_button != null:
		var weather_center: Vector2 = weather_button.get_global_rect().get_center()
		_send_touch(controls, 3, weather_center, true)
		await process_frame
		_send_touch(controls, 3, weather_center, false)
		await _wait_process_frames(2)
		_check(
			int(weather_system.get("_weather_index")) != weather_before,
			"touch weather button cycles the active weather"
		)

	var player: CharacterBody3D = lab.get_node("Player") as CharacterBody3D
	var car: RigidBody3D = lab.get_node("ArcadeCar") as RigidBody3D
	var player_start: Vector3 = player.global_position
	var joystick_center: Vector2 = controls.call("get_joystick_center") as Vector2
	var primary_button: Button = controls.call("get_action_button", &"Primary") as Button
	_send_touch(controls, 0, joystick_center, true)
	_send_drag(controls, 0, joystick_center + Vector2(0.0, -78.0), Vector2(0.0, -78.0))
	var primary_center: Vector2 = primary_button.get_global_rect().get_center()
	_send_touch(controls, 1, primary_center, true)
	await process_frame
	_check(
		Input.is_action_pressed(&"move_forward") and Input.is_action_pressed(&"jump"),
		"second touch can hold the primary action while the joystick remains active"
	)
	var sprint_button: Button = controls.call("get_action_button", &"Sprint") as Button
	var sprint_center: Vector2 = sprint_button.get_global_rect().get_center()
	_send_touch(controls, 2, sprint_center, true)
	await process_frame
	_check(
		Input.is_action_pressed(&"move_forward")
		and Input.is_action_pressed(&"jump")
		and Input.is_action_pressed(&"sprint"),
		"three touches can hold the joystick and two independent actions"
	)
	_send_touch(controls, 1, primary_center, false)
	_check(
		not Input.is_action_pressed(&"jump")
		and Input.is_action_pressed(&"move_forward")
		and Input.is_action_pressed(&"sprint"),
		"releasing one touch preserves the other held controls"
	)
	_send_touch(controls, 2, sprint_center, false)
	await _wait_physics_frames(30)
	_send_touch(controls, 0, joystick_center + Vector2(0.0, -78.0), false)
	_check(player.global_position.distance_to(player_start) > 2.0, "virtual joystick moves the on-foot player")

	await _wait_physics_frames(8)
	var jump_start_y: float = player.global_position.y
	primary_button.button_down.emit()
	await _wait_physics_frames(2)
	primary_button.button_up.emit()
	await _wait_physics_frames(6)
	_check(player.global_position.y > jump_start_y + 0.2, "touch primary button jumps on foot")

	var rotation_before_look: float = player.rotation.y
	var look_start: Vector2 = Vector2(controls.size.x * 0.56, controls.size.y * 0.32)
	_send_touch(controls, 1, look_start, true)
	_send_drag(controls, 1, look_start + Vector2(110.0, -35.0), Vector2(110.0, -35.0))
	_send_touch(controls, 1, look_start + Vector2(110.0, -35.0), false)
	_check(abs(angle_difference(rotation_before_look, player.rotation.y)) > 0.1, "right-side drag rotates the on-foot camera")

	player.global_position = car.global_position + car.global_transform.basis.x * 2.0
	player.velocity = Vector3.ZERO
	var interact_button: Button = controls.call("get_action_button", &"Interact") as Button
	interact_button.button_down.emit()
	await _wait_process_frames(2)
	interact_button.button_up.emit()
	await _wait_process_frames(2)
	_check(not bool(player.get("active")) and bool(car.get("driver_active")), "touch interact button enters the car")
	_check(primary_button.text == "DRIFT" and interact_button.text == "EXIT", "touch labels adapt to vehicle mode")

	var gas_button: Button = controls.get_node_or_null("Gas") as Button
	var brake_button: Button = controls.get_node_or_null("Brake") as Button
	var left_button: Button = controls.get_node_or_null("SteerLeft") as Button
	var right_button: Button = controls.get_node_or_null("SteerRight") as Button
	_check(
		gas_button != null and brake_button != null and left_button != null and right_button != null,
		"driving HUD exposes separate GAS, BRAKE, LEFT, and RIGHT controls"
	)
	if gas_button != null and brake_button != null and left_button != null and right_button != null:
		_check(
			gas_button.visible and brake_button.visible and left_button.visible and right_button.visible,
			"vehicle controls become visible after entering the car"
		)
		_check(
			gas_button.get_global_rect().get_center().x < controls.size.x * 0.5
			and brake_button.get_global_rect().get_center().x < controls.size.x * 0.5,
			"GAS and BRAKE stay on the left half of the touch HUD"
		)
		_check(
			left_button.get_global_rect().get_center().x > controls.size.x * 0.5
			and right_button.get_global_rect().get_center().x > controls.size.x * 0.5,
			"LEFT and RIGHT stay on the right half of the touch HUD"
		)
		_check_buttons_do_not_overlap([
			gas_button,
			brake_button,
			left_button,
			right_button,
			primary_button,
			interact_button,
			controls.call("get_action_button", &"Camera") as Button,
			controls.call("get_action_button", &"Reset") as Button,
		])
		var gas_center: Vector2 = gas_button.get_global_rect().get_center()
		var left_center: Vector2 = left_button.get_global_rect().get_center()
		var right_center: Vector2 = right_button.get_global_rect().get_center()
		_send_touch(controls, 2, gas_center, true)
		_send_touch(controls, 3, left_center, true)
		await process_frame
		_check(
			Input.is_action_pressed(&"move_forward") and Input.is_action_pressed(&"move_left"),
			"GAS and LEFT can be held by separate fingers"
		)
		var heading_before_drive: float = car.rotation.y
		await _wait_physics_frames(120)
		_check(float(car.call("speed_kph")) > 20.0, "GAS accelerates the car")
		_check(
			absf(angle_difference(heading_before_drive, car.rotation.y)) > 0.12,
			"LEFT turns the car while GAS remains held"
		)
		_send_touch(controls, 3, left_center, false)
		_check(
			Input.is_action_pressed(&"move_forward") and not Input.is_action_pressed(&"move_left"),
			"releasing LEFT preserves GAS"
		)
		_send_touch(controls, 4, right_center, true)
		await process_frame
		_check(Input.is_action_pressed(&"move_right"), "RIGHT produces an independent steering action")
		_send_touch(controls, 4, right_center, false)
		_send_touch(controls, 2, gas_center, false)
	primary_button.button_down.emit()
	await _wait_physics_frames(4)
	_check(bool(car.get("drifting")), "touch primary button activates drift while driving")
	primary_button.button_up.emit()
	var speed_before_brake: float = float(car.call("speed_kph"))
	if brake_button != null:
		var brake_center: Vector2 = brake_button.get_global_rect().get_center()
		_send_touch(controls, 5, brake_center, true)
		await process_frame
		_check(Input.is_action_pressed(&"move_back"), "BRAKE produces the braking action")
		await _wait_physics_frames(20)
		_send_touch(controls, 5, brake_center, false)
		_check(float(car.call("speed_kph")) < speed_before_brake, "BRAKE reduces forward speed")

	var camera_button: Button = controls.call("get_action_button", &"Camera") as Button
	camera_button.button_down.emit()
	await _wait_process_frames(2)
	camera_button.button_up.emit()
	_check(bool(car.get("cockpit_camera")), "touch camera button changes vehicle camera")

	var reset_button: Button = controls.call("get_action_button", &"Reset") as Button
	reset_button.button_down.emit()
	await _wait_process_frames(2)
	reset_button.button_up.emit()
	await _wait_physics_frames(2)
	_check(car.linear_velocity.length() < 5.0, "touch reset button stops and resets the controlled car")

	interact_button.button_down.emit()
	await _wait_process_frames(2)
	interact_button.button_up.emit()
	await _wait_process_frames(2)
	_check(bool(player.get("active")) and not bool(car.get("driver_active")), "touch interact button exits the car")
	if gas_button != null and brake_button != null and left_button != null and right_button != null:
		_check(
			not gas_button.visible and not brake_button.visible and not left_button.visible and not right_button.visible,
			"vehicle controls hide again after exiting the car"
		)

	var menu_button: Button = controls.call("get_action_button", &"Menu") as Button
	menu_button.pressed.emit()
	await _wait_process_frames(2)
	_check(lab.get_node("MovementHUD/Root/PauseMenu").visible and paused, "touch menu button opens the pause menu")

	controls.call("release_all_actions")
	paused = false
	world.queue_free()
	await _wait_process_frames(2)
	if _failures.is_empty():
		print("VERIFY_MOBILE_CONTROLS PASS")
		quit(0)
	else:
		for failure: String in _failures:
			push_error("VERIFY_MOBILE_CONTROLS FAIL: " + failure)
		quit(1)


func _send_touch(_controls: Control, index: int, position: Vector2, pressed: bool) -> void:
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	root.push_input(event, true)


func _send_drag(_controls: Control, index: int, position: Vector2, relative: Vector2) -> void:
	var event: InputEventScreenDrag = InputEventScreenDrag.new()
	event.index = index
	event.position = position
	event.relative = relative
	root.push_input(event, true)


func _wait_physics_frames(count: int) -> void:
	for _index: int in range(count):
		await physics_frame


func _wait_process_frames(count: int) -> void:
	for _index: int in range(count):
		await process_frame


func _check(condition: bool, message: String) -> void:
	if not condition and not _failures.has(message):
		_failures.append(message)


func _check_buttons_do_not_overlap(buttons: Array[Button]) -> void:
	for first_index: int in range(buttons.size()):
		for second_index: int in range(first_index + 1, buttons.size()):
			_check(
				not buttons[first_index].get_global_rect().intersects(buttons[second_index].get_global_rect()),
				"driving touch buttons do not overlap"
			)
