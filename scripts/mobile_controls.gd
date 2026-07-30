class_name MobileTouchControls
extends Control

signal look_dragged(relative: Vector2)
signal menu_requested

const JOYSTICK_RADIUS: float = 82.0
const MOVE_ACTIONS: Array[StringName] = [
	&"move_left",
	&"move_right",
	&"move_forward",
	&"move_back",
]
const BUTTON_ACTIONS: Array[StringName] = [
	&"jump",
	&"sprint",
	&"drift",
	&"interact",
	&"camera_toggle",
	&"reset_actor",
	&"weather_cycle",
]

var _available: bool = false
var _gameplay_active: bool = false
var _driving: bool = false
var _joystick_touch: int = -1
var _look_touch: int = -1
var _button_touches: Dictionary = {}
var _joystick_origin: Vector2 = Vector2.ZERO
var _joystick_value: Vector2 = Vector2.ZERO
var _action_buttons: Array[Button] = []
var _primary_button: Button
var _sprint_button: Button
var _interact_button: Button
var _camera_button: Button
var _reset_button: Button
var _gas_button: Button
var _brake_button: Button
var _steer_left_button: Button
var _steer_right_button: Button
var _vehicle_buttons: Array[Button] = []


func _ready() -> void:
	name = "MobileControls"
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_available = OS.has_feature("mobile") or bool(ProjectSettings.get_setting("debug/mobile/force_touch_controls", false))
	_build_buttons()
	_reset_joystick_origin()
	set_gameplay_active(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _joystick_touch < 0:
		_reset_joystick_origin()


func _draw() -> void:
	if not _available or not _gameplay_active or _driving:
		return
	var outer_color: Color = Color(0.08, 0.14, 0.17, 0.54)
	var edge_color: Color = Color(0.62, 0.95, 0.87, 0.62)
	var thumb_color: Color = Color(0.38, 0.88, 0.78, 0.78)
	draw_circle(_joystick_origin, JOYSTICK_RADIUS, outer_color)
	draw_arc(_joystick_origin, JOYSTICK_RADIUS, 0.0, TAU, 48, edge_color, 3.0, true)
	draw_circle(_joystick_origin + _joystick_value * JOYSTICK_RADIUS, 32.0, thumb_color)
	draw_arc(_joystick_origin + _joystick_value * JOYSTICK_RADIUS, 32.0, 0.0, TAU, 32, Color.WHITE, 2.0, true)


func _input(event: InputEvent) -> void:
	if not _available or not _gameplay_active or not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		if _handle_touch(event):
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		if _handle_drag(event):
			get_viewport().set_input_as_handled()


func set_gameplay_active(value: bool) -> void:
	var was_active: bool = _gameplay_active
	_gameplay_active = value
	visible = _available and value
	set_process_input(visible)
	if was_active and not value:
		release_all_actions()
	queue_redraw()


func set_driving(value: bool) -> void:
	if _driving == value:
		return
	release_all_actions()
	_driving = value
	_primary_button.text = "DRIFT" if value else "JUMP"
	_interact_button.text = "EXIT" if value else "ENTER"
	_sprint_button.visible = not value
	for button: Button in _vehicle_buttons:
		button.visible = value
	if value:
		_set_button_offsets(_primary_button, Vector4(-142.0, -266.0, -30.0, -166.0))
		_set_button_offsets(_interact_button, Vector4(-266.0, -266.0, -154.0, -166.0))
		_set_button_offsets(_camera_button, Vector4(-142.0, -360.0, -30.0, -282.0))
		_set_button_offsets(_reset_button, Vector4(-266.0, -360.0, -154.0, -282.0))
	else:
		_set_button_offsets(_primary_button, Vector4(-134.0, -162.0, -30.0, -58.0))
		_set_button_offsets(_interact_button, Vector4(-238.0, -250.0, -134.0, -180.0))
		_set_button_offsets(_camera_button, Vector4(-126.0, -258.0, -30.0, -188.0))
		_set_button_offsets(_reset_button, Vector4(-126.0, -338.0, -30.0, -276.0))
	queue_redraw()


func is_available() -> bool:
	return _available


func set_force_visible_for_testing(value: bool) -> void:
	_available = value
	set_gameplay_active(_gameplay_active)


func get_joystick_center() -> Vector2:
	return _joystick_origin


func get_action_button(node_name: StringName) -> Button:
	return get_node(String(node_name)) as Button


func release_all_actions() -> void:
	_joystick_touch = -1
	_look_touch = -1
	_joystick_value = Vector2.ZERO
	for touch_state: Dictionary in _button_touches.values():
		var button: Button = touch_state["button"] as Button
		button.set_pressed_no_signal(false)
	_button_touches.clear()
	for action: StringName in MOVE_ACTIONS:
		Input.action_release(action)
	for action: StringName in BUTTON_ACTIONS:
		Input.action_release(action)
	_reset_joystick_origin()
	queue_redraw()


func _handle_touch(event: InputEventScreenTouch) -> bool:
	if event.pressed:
		var button: Button = _action_button_at(event.position)
		if button != null:
			_press_touch_button(event.index, button)
			return true
		if not _driving and _joystick_touch < 0 and event.position.x < size.x * 0.46 and event.position.y > size.y * 0.28:
			_joystick_touch = event.index
			_joystick_origin = Vector2(
				clamp(event.position.x, JOYSTICK_RADIUS + 24.0, size.x * 0.42),
				clamp(event.position.y, size.y * 0.48, size.y - JOYSTICK_RADIUS - 24.0)
			)
			_update_joystick(event.position)
			return true
		elif not _driving and _look_touch < 0 and event.position.x >= size.x * 0.38:
			_look_touch = event.index
			return true
	else:
		if _button_touches.has(event.index):
			_release_touch_button(event.index, event.position)
			return true
		if event.index == _joystick_touch:
			_joystick_touch = -1
			_joystick_value = Vector2.ZERO
			_apply_joystick_actions()
			_reset_joystick_origin()
			queue_redraw()
			return true
		if event.index == _look_touch:
			_look_touch = -1
			return true
	return false


func _handle_drag(event: InputEventScreenDrag) -> bool:
	if event.index == _joystick_touch:
		_update_joystick(event.position)
		return true
	elif event.index == _look_touch:
		look_dragged.emit(event.relative)
		return true
	return _button_touches.has(event.index)


func _press_touch_button(touch_index: int, button: Button) -> void:
	var action: StringName = _action_for_button(button)
	_button_touches[touch_index] = {
		"button": button,
		"action": action,
	}
	button.set_pressed_no_signal(true)
	if not action.is_empty():
		Input.action_press(action)


func _release_touch_button(touch_index: int, touch_position: Vector2) -> void:
	var touch_state: Dictionary = _button_touches[touch_index] as Dictionary
	var button: Button = touch_state["button"] as Button
	var action: StringName = touch_state["action"] as StringName
	_button_touches.erase(touch_index)
	button.set_pressed_no_signal(false)
	if not action.is_empty():
		Input.action_release(action)
	elif button.name == &"Menu" and button.get_global_rect().has_point(touch_position):
		menu_requested.emit()


func _action_for_button(button: Button) -> StringName:
	match button.name:
		&"Primary":
			return &"drift" if _driving else &"jump"
		&"Sprint":
			return &"sprint"
		&"Interact":
			return &"interact"
		&"Camera":
			return &"camera_toggle"
		&"Reset":
			return &"reset_actor"
		&"Weather":
			return &"weather_cycle"
		&"Gas":
			return &"move_forward"
		&"Brake":
			return &"move_back"
		&"SteerLeft":
			return &"move_left"
		&"SteerRight":
			return &"move_right"
	return &""


func _update_joystick(touch_position: Vector2) -> void:
	var offset: Vector2 = touch_position - _joystick_origin
	_joystick_value = offset.limit_length(JOYSTICK_RADIUS) / JOYSTICK_RADIUS
	if _joystick_value.length() < 0.12:
		_joystick_value = Vector2.ZERO
	_apply_joystick_actions()
	queue_redraw()


func _apply_joystick_actions() -> void:
	for action: StringName in MOVE_ACTIONS:
		Input.action_release(action)
	if _driving:
		return
	_press_with_strength(&"move_left", max(-_joystick_value.x, 0.0))
	_press_with_strength(&"move_right", max(_joystick_value.x, 0.0))
	_press_with_strength(&"move_forward", max(-_joystick_value.y, 0.0))
	_press_with_strength(&"move_back", max(_joystick_value.y, 0.0))


func _press_with_strength(action: StringName, strength: float) -> void:
	if strength > 0.01:
		Input.action_press(action, strength)


func _build_buttons() -> void:
	_primary_button = _add_action_button("Primary", "JUMP", Vector4(-134.0, -162.0, -30.0, -58.0))
	_primary_button.button_down.connect(_on_primary_down)
	_primary_button.button_up.connect(_on_primary_up)

	_sprint_button = _add_action_button("Sprint", "SPRINT", Vector4(-250.0, -145.0, -150.0, -69.0))
	_connect_hold_action(_sprint_button, &"sprint")

	_interact_button = _add_action_button("Interact", "ENTER", Vector4(-238.0, -250.0, -134.0, -180.0))
	_connect_hold_action(_interact_button, &"interact")

	_camera_button = _add_action_button("Camera", "CAM", Vector4(-126.0, -258.0, -30.0, -188.0))
	_connect_hold_action(_camera_button, &"camera_toggle")

	_reset_button = _add_action_button("Reset", "RESET", Vector4(-126.0, -338.0, -30.0, -276.0))
	_connect_hold_action(_reset_button, &"reset_actor")

	_brake_button = _add_left_action_button("Brake", "BRAKE", Vector4(30.0, -150.0, 142.0, -48.0))
	_connect_hold_action(_brake_button, &"move_back")
	_gas_button = _add_left_action_button("Gas", "GAS", Vector4(154.0, -150.0, 266.0, -48.0))
	_connect_hold_action(_gas_button, &"move_forward")
	_steer_left_button = _add_action_button("SteerLeft", "LEFT", Vector4(-266.0, -150.0, -154.0, -48.0))
	_connect_hold_action(_steer_left_button, &"move_left")
	_steer_right_button = _add_action_button("SteerRight", "RIGHT", Vector4(-142.0, -150.0, -30.0, -48.0))
	_connect_hold_action(_steer_right_button, &"move_right")
	_vehicle_buttons.assign([_brake_button, _gas_button, _steer_left_button, _steer_right_button])
	for button: Button in _vehicle_buttons:
		button.visible = false

	var menu_button: Button = Button.new()
	menu_button.name = "Menu"
	menu_button.text = "MENU"
	menu_button.anchor_left = 1.0
	menu_button.anchor_right = 1.0
	menu_button.offset_left = -116.0
	menu_button.offset_top = 70.0
	menu_button.offset_right = -30.0
	menu_button.offset_bottom = 128.0
	_style_button(menu_button)
	menu_button.pressed.connect(func() -> void: menu_requested.emit())
	add_child(menu_button)
	_action_buttons.append(menu_button)

	var weather_button: Button = Button.new()
	weather_button.name = "Weather"
	weather_button.text = "WEATHER"
	weather_button.anchor_left = 1.0
	weather_button.anchor_right = 1.0
	weather_button.offset_left = -134.0
	weather_button.offset_top = 142.0
	weather_button.offset_right = -30.0
	weather_button.offset_bottom = 200.0
	weather_button.focus_mode = Control.FOCUS_NONE
	_style_button(weather_button)
	add_child(weather_button)
	_action_buttons.append(weather_button)


func _add_action_button(node_name: String, label: String, offsets: Vector4) -> Button:
	var button: Button = Button.new()
	button.name = node_name
	button.text = label
	button.anchor_left = 1.0
	button.anchor_top = 1.0
	button.anchor_right = 1.0
	button.anchor_bottom = 1.0
	button.offset_left = offsets.x
	button.offset_top = offsets.y
	button.offset_right = offsets.z
	button.offset_bottom = offsets.w
	button.focus_mode = Control.FOCUS_NONE
	_style_button(button)
	add_child(button)
	_action_buttons.append(button)
	return button


func _add_left_action_button(node_name: String, label: String, offsets: Vector4) -> Button:
	var button: Button = _add_action_button(node_name, label, offsets)
	button.anchor_left = 0.0
	button.anchor_right = 0.0
	return button


func _set_button_offsets(button: Button, offsets: Vector4) -> void:
	button.offset_left = offsets.x
	button.offset_top = offsets.y
	button.offset_right = offsets.z
	button.offset_bottom = offsets.w


func _style_button(button: Button) -> void:
	button.add_theme_font_size_override("font_size", 17)
	button.add_theme_color_override("font_color", Color("effffb"))
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", _button_style(Color(0.04, 0.09, 0.11, 0.72), Color(0.48, 0.9, 0.8, 0.78), 2))
	button.add_theme_stylebox_override("hover", _button_style(Color(0.08, 0.18, 0.19, 0.84), Color(0.65, 1.0, 0.9, 0.95), 2))
	button.add_theme_stylebox_override("pressed", _button_style(Color(0.18, 0.58, 0.5, 0.9), Color.WHITE, 3))


func _button_style(background: Color, border: Color, width: int) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(18)
	return style


func _connect_hold_action(button: Button, action: StringName) -> void:
	button.button_down.connect(func() -> void: Input.action_press(action))
	button.button_up.connect(func() -> void: Input.action_release(action))
	button.mouse_exited.connect(func() -> void:
		if not button.button_pressed:
			Input.action_release(action)
	)


func _on_primary_down() -> void:
	Input.action_press(&"drift" if _driving else &"jump")


func _on_primary_up() -> void:
	Input.action_release(&"drift" if _driving else &"jump")


func _action_button_at(point: Vector2) -> Button:
	for button: Button in _action_buttons:
		if button.visible and button.get_global_rect().has_point(point):
			return button
	return null


func _reset_joystick_origin() -> void:
	if size.x <= 1.0 or size.y <= 1.0:
		return
	_joystick_origin = Vector2(
		clamp(size.x * 0.13, 112.0, 168.0),
		size.y - clamp(size.y * 0.20, 112.0, 152.0)
	)
