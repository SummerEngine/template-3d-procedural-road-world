class_name FreeFlyCamera
extends Camera3D

@export_range(5.0, 250.0, 1.0) var move_speed: float = 62.0
@export_range(1.0, 8.0, 0.25) var sprint_multiplier: float = 3.0
@export_range(0.0005, 0.01, 0.0001) var mouse_sensitivity: float = 0.0022

var _pitch: float = -0.32
var _yaw: float = 0.0


func _ready() -> void:
	_ensure_input_actions()
	look_at(Vector3(0.0, 24.0, 0.0), Vector3.UP)
	_pitch = rotation.x
	_yaw = rotation.y


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not _is_panel_open():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not _is_panel_open():
		_yaw -= event.relative.x * mouse_sensitivity
		_pitch = clamp(_pitch - event.relative.y * mouse_sensitivity, -1.52, 1.52)
		rotation = Vector3(_pitch, _yaw, 0.0)


func _process(delta: float) -> void:
	if _is_panel_open():
		return
	var input_2d: Vector2 = Input.get_vector("fly_left", "fly_right", "fly_forward", "fly_back")
	var vertical: float = Input.get_action_strength("fly_up") - Input.get_action_strength("fly_down")
	var direction: Vector3 = transform.basis.x * input_2d.x + transform.basis.z * input_2d.y + Vector3.UP * vertical
	if direction.length_squared() > 0.001:
		var speed: float = move_speed
		if Input.is_action_pressed("fly_sprint"):
			speed *= sprint_multiplier
		global_position += direction.normalized() * speed * delta


func _is_panel_open() -> bool:
	var world_ui: Node = get_node_or_null("../WorldUI")
	return world_ui != null and bool(world_ui.get("panel_open"))


func _ensure_input_actions() -> void:
	_add_key_action("fly_forward", KEY_W)
	_add_key_action("fly_back", KEY_S)
	_add_key_action("fly_left", KEY_A)
	_add_key_action("fly_right", KEY_D)
	_add_key_action("fly_up", KEY_SPACE)
	_add_key_action("fly_down", KEY_C)
	_add_key_action("fly_sprint", KEY_SHIFT)


func _add_key_action(action_name: StringName, physical_keycode: Key) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	if InputMap.action_get_events(action_name).is_empty():
		var event: InputEventKey = InputEventKey.new()
		event.physical_keycode = physical_keycode
		InputMap.action_add_event(action_name, event)
