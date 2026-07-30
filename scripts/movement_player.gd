class_name MovementPlayerController
extends CharacterBody3D

@export_group("Movement")
@export var walk_speed: float = 9.0
@export var sprint_speed: float = 14.0
@export var ground_acceleration: float = 72.0
@export var ground_friction: float = 82.0
@export var air_acceleration: float = 25.0
@export var air_friction: float = 2.5
@export var jump_velocity: float = 9.0
@export var gravity: float = 28.0
@export var fall_gravity_multiplier: float = 1.45
@export var coyote_time: float = 0.11
@export var jump_buffer_time: float = 0.12

@export_group("Camera")
@export_range(0.0005, 0.01, 0.0001) var mouse_sensitivity: float = 0.0022
@export_range(0.0005, 0.02, 0.0001) var touch_sensitivity: float = 0.0034
@export var base_fov: float = 86.0
@export var sprint_fov: float = 94.0

@export_group("Mantle")
@export var mantle_duration: float = 0.52
@export var mantle_min_height: float = 0.55
@export var mantle_max_height: float = 1.65

var active: bool = true
var first_person: bool = true
var is_mantling: bool = false

var _pitch: float = -0.05
var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
var _mantle_elapsed: float = 0.0
var _mantle_start: Vector3 = Vector3.ZERO
var _mantle_target: Vector3 = Vector3.ZERO
var _spawn_transform: Transform3D

var _collision: CollisionShape3D
var _model: Node3D
var _head: Node3D
var _first_person_camera: Camera3D
var _third_person_pivot: Node3D
var _third_person_arm: SpringArm3D
var _third_person_camera: Camera3D


func _ready() -> void:
	floor_snap_length = 0.45
	floor_max_angle = deg_to_rad(48.0)
	floor_stop_on_slope = true
	_build_body()
	_build_cameras()
	_spawn_transform = global_transform
	_apply_camera_mode()


func _unhandled_input(event: InputEvent) -> void:
	if not active or _input_is_blocked():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_apply_look_delta(event.relative, mouse_sensitivity)


func _physics_process(delta: float) -> void:
	if not active:
		return
	if is_mantling:
		_update_mantle(delta)
		return

	var grounded: bool = is_on_floor()
	if grounded:
		_coyote_timer = coyote_time
	else:
		_coyote_timer = max(_coyote_timer - delta, 0.0)

	if not _input_is_blocked() and Input.is_action_just_pressed("jump"):
		_jump_buffer_timer = jump_buffer_time
	else:
		_jump_buffer_timer = max(_jump_buffer_timer - delta, 0.0)

	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
		velocity.y = jump_velocity
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0
		grounded = false
	elif not grounded:
		var gravity_scale: float = fall_gravity_multiplier if velocity.y < 0.0 else 1.0
		velocity.y -= gravity * gravity_scale * delta

	if not _input_is_blocked() and Input.is_action_just_released("jump") and velocity.y > 0.0:
		velocity.y *= 0.55

	var input_vector: Vector2 = Vector2.ZERO
	if not _input_is_blocked():
		input_vector = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish_direction: Vector3 = transform.basis * Vector3(input_vector.x, 0.0, input_vector.y)
	wish_direction.y = 0.0
	if wish_direction.length_squared() > 0.001:
		wish_direction = wish_direction.normalized()

	var sprinting: bool = not _input_is_blocked() and Input.is_action_pressed("sprint") and input_vector.y < -0.2
	var target_speed: float = sprint_speed if sprinting else walk_speed
	var horizontal: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	if wish_direction != Vector3.ZERO:
		var acceleration: float = ground_acceleration if grounded else air_acceleration
		horizontal = horizontal.move_toward(wish_direction * target_speed, acceleration * delta)
	else:
		var friction: float = ground_friction if grounded else air_friction
		horizontal = horizontal.move_toward(Vector3.ZERO, friction * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	var requested_fov: float = sprint_fov if sprinting and grounded else base_fov
	_first_person_camera.fov = lerpf(_first_person_camera.fov, requested_fov, 1.0 - exp(-9.0 * delta))
	_third_person_camera.fov = lerpf(_third_person_camera.fov, requested_fov - 4.0, 1.0 - exp(-9.0 * delta))

	if not grounded and input_vector.y < -0.25 and _try_begin_mantle():
		return

	move_and_slide()


func set_active(value: bool) -> void:
	active = value
	visible = value
	if _collision != null:
		_collision.set_deferred("disabled", not value)
	if value:
		_apply_camera_mode()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		_first_person_camera.current = false
		_third_person_camera.current = false
		velocity = Vector3.ZERO


func toggle_camera() -> void:
	first_person = not first_person
	_apply_camera_mode()


func apply_touch_look(relative: Vector2) -> void:
	if active and not _input_is_blocked():
		_apply_look_delta(relative, touch_sensitivity)


func camera_mode_name() -> String:
	return "FIRST PERSON" if first_person else "THIRD PERSON"


func reset_to_spawn() -> void:
	global_transform = _spawn_transform
	velocity = Vector3.ZERO
	is_mantling = false


func set_spawn_transform(value: Transform3D) -> void:
	_spawn_transform = value


func _build_body() -> void:
	_collision = CollisionShape3D.new()
	_collision.name = "Collision"
	var capsule_shape: CapsuleShape3D = CapsuleShape3D.new()
	capsule_shape.radius = 0.38
	capsule_shape.height = 1.8
	_collision.shape = capsule_shape
	_collision.position.y = 0.9
	add_child(_collision)

	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)
	var body_mesh: MeshInstance3D = MeshInstance3D.new()
	body_mesh.name = "Body"
	var capsule_mesh: CapsuleMesh = CapsuleMesh.new()
	capsule_mesh.radius = 0.38
	capsule_mesh.height = 1.8
	capsule_mesh.radial_segments = 12
	capsule_mesh.rings = 5
	body_mesh.mesh = capsule_mesh
	body_mesh.position.y = 0.9
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color("47d7c8")
	material.metallic = 0.22
	material.roughness = 0.32
	body_mesh.material_override = material
	_model.add_child(body_mesh)


func _build_cameras() -> void:
	_head = Node3D.new()
	_head.name = "Head"
	_head.position.y = 1.58
	add_child(_head)

	_first_person_camera = Camera3D.new()
	_first_person_camera.name = "FirstPersonCamera"
	_first_person_camera.fov = base_fov
	_first_person_camera.near = 0.05
	_head.add_child(_first_person_camera)

	_third_person_pivot = Node3D.new()
	_third_person_pivot.name = "ThirdPersonPivot"
	_third_person_pivot.position.y = 1.35
	_third_person_pivot.rotation.x = -0.18
	add_child(_third_person_pivot)

	_third_person_arm = SpringArm3D.new()
	_third_person_arm.name = "SpringArm"
	_third_person_arm.spring_length = 5.2
	_third_person_arm.margin = 0.18
	_third_person_arm.collision_mask = 1
	_third_person_pivot.add_child(_third_person_arm)

	_third_person_camera = Camera3D.new()
	_third_person_camera.name = "ThirdPersonCamera"
	_third_person_camera.fov = base_fov - 4.0
	_third_person_camera.near = 0.08
	_third_person_camera.position.x = 0.65
	_third_person_arm.add_child(_third_person_camera)


func _apply_camera_mode() -> void:
	if _first_person_camera == null:
		return
	_first_person_camera.current = active and first_person
	_third_person_camera.current = active and not first_person
	_model.visible = not first_person


func _apply_look_delta(relative: Vector2, sensitivity: float) -> void:
	rotate_y(-relative.x * sensitivity)
	_pitch = clamp(_pitch - relative.y * sensitivity, -1.42, 1.28)
	_head.rotation.x = _pitch
	_third_person_pivot.rotation.x = clamp(_pitch, -0.82, 0.34)


func _try_begin_mantle() -> bool:
	var forward: Vector3 = -global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var exclude: Array[RID] = [get_rid()]

	var wall_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 0.65,
		global_position + Vector3.UP * 0.65 + forward * 0.9,
		1,
		exclude
	)
	var wall_hit: Dictionary = space.intersect_ray(wall_query)
	if wall_hit.is_empty():
		return false

	var clearance_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 1.82,
		global_position + Vector3.UP * 1.82 + forward * 0.95,
		1,
		exclude
	)
	if not space.intersect_ray(clearance_query).is_empty():
		return false

	var ledge_probe: Vector3 = global_position + forward * 0.82 + Vector3.UP * (mantle_max_height + 0.4)
	var down_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		ledge_probe,
		ledge_probe - Vector3.UP * (mantle_max_height + 0.7),
		1,
		exclude
	)
	var ledge_hit: Dictionary = space.intersect_ray(down_query)
	if ledge_hit.is_empty():
		return false
	var ledge_position: Vector3 = ledge_hit["position"] as Vector3
	var ledge_height: float = ledge_position.y - global_position.y
	if ledge_height < mantle_min_height or ledge_height > mantle_max_height:
		return false
	if (ledge_hit["normal"] as Vector3).dot(Vector3.UP) < 0.78:
		return false

	is_mantling = true
	_mantle_elapsed = 0.0
	_mantle_start = global_position
	_mantle_target = ledge_position + forward * 0.48 + Vector3.UP * 0.04
	velocity = Vector3.ZERO
	return true


func _update_mantle(delta: float) -> void:
	_mantle_elapsed += delta
	var progress: float = clamp(_mantle_elapsed / mantle_duration, 0.0, 1.0)
	var eased: float = smoothstep(0.0, 1.0, progress)
	global_position = _mantle_start.lerp(_mantle_target, eased) + Vector3.UP * sin(progress * PI) * 0.13
	if progress >= 1.0:
		is_mantling = false
		velocity = Vector3.ZERO


func _input_is_blocked() -> bool:
	var lab: Node = get_parent()
	if lab != null and bool(lab.get("input_blocked")):
		return true
	var world_ui: Node = get_node_or_null("../../WorldUI")
	return world_ui != null and bool(world_ui.get("panel_open"))
