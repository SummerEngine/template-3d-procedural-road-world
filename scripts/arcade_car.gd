class_name ArcadeCarController
extends RigidBody3D

@export_group("Handling profile")
@export_enum("SPORT", "CHILL", "CUSTOM") var handling_profile: String = "SPORT"
@export var park_when_unoccupied: bool = true

@export_group("Chassis")
@export var vehicle_mass: float = 1150.0
@export var center_of_mass_drop: float = 0.28
@export var aerodynamic_drag: float = 0.24

@export_group("Suspension")
@export var suspension_rest_length: float = 0.42
@export var suspension_travel: float = 0.2
@export var suspension_stiffness: float = 36000.0
@export var suspension_damping: float = 4800.0
@export var wheel_radius: float = 0.36
@export_range(1.0, 5.0, 0.1) var maximum_suspension_load: float = 3.0

@export_group("Powertrain")
@export var engine_force: float = 22000.0
@export var reverse_force: float = 8500.0
@export var brake_force: float = 26000.0
@export var max_forward_speed: float = 75.0
@export var max_reverse_speed: float = 16.0
@export_range(0.0, 1.0, 0.01) var front_drive_share: float = 0.38
@export_range(0.0, 1.0, 0.01) var traction_control_strength: float = 0.92

@export_group("Tires")
@export var max_steering_angle: float = 0.52
@export var steering_response: float = 5.5
@export var steering_wheelbase: float = 2.76
@export var target_lateral_acceleration: float = 10.5
@export_range(0.1, 1.0, 0.05) var high_speed_steering_response_scale: float = 0.4
@export var yaw_rate_assist: float = 24.0
@export var front_lateral_stiffness: float = 1750.0
@export var rear_lateral_stiffness: float = 1900.0
@export var tire_friction: float = 1.55
@export var sliding_grip_ratio: float = 0.78
@export var drift_rear_stiffness: float = 560.0
@export var drift_rear_friction: float = 0.58
@export var grip_loss_rate: float = 2.2
@export var grip_recovery_seconds: float = 0.90

@export_group("Skid marks")
@export var skid_slip_threshold: float = 0.34
@export var skid_mark_width: float = 0.32
@export var skid_surface_lift: float = 0.205
@export var max_skid_segments: int = 420

const CAR_SKINS: Dictionary = {
	"RACING RED": {
		"albedo": Color("e95f3d"),
		"metallic": 0.68,
		"roughness": 0.22,
	},
	"MIDNIGHT BLUE": {
		"albedo": Color("1a2b4c"),
		"metallic": 0.72,
		"roughness": 0.18,
	},
	"EMERALD GREEN": {
		"albedo": Color("1e6b4c"),
		"metallic": 0.60,
		"roughness": 0.25,
	},
	"SUNBURST YELLOW": {
		"albedo": Color("f0c040"),
		"metallic": 0.55,
		"roughness": 0.28,
	},
	"MATTE BLACK": {
		"albedo": Color("1a1a1a"),
		"metallic": 0.10,
		"roughness": 0.85,
	},
	"PEARL WHITE": {
		"albedo": Color("e8e4dd"),
		"metallic": 0.45,
		"roughness": 0.12,
	},
}

var driver_active: bool = false
var cockpit_camera: bool = false
var drifting: bool = false
var _body_paint: StandardMaterial3D

var _spawn_transform: Transform3D
var _steering_input: float = 0.0
var _throttle_input: float = 0.0
var _brake_input: float = 0.0
var _steering_angle: float = 0.0
var _wheel_contact_count: int = 0
var _wheel_anchors: Array[Vector3] = [
	Vector3(-0.86, -0.08, -1.38),
	Vector3(0.86, -0.08, -1.38),
	Vector3(-0.86, -0.08, 1.38),
	Vector3(0.86, -0.08, 1.38),
]
var _wheel_steer_pivots: Array[Node3D] = []
var _wheel_roll_pivots: Array[Node3D] = []
var _wheel_lengths: Array[float] = [0.42, 0.42, 0.42, 0.42]
var _wheel_roll_angles: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _wheel_grip: Array[float] = [1.0, 1.0, 1.0, 1.0]
var _wheel_slip: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _wheel_lateral_slip: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _wheel_demand_slip: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _last_skid_positions: Array = [null, null, null, null]
var _skid_root: Node3D
var _skid_material: StandardMaterial3D
var _skid_segments: Array[MeshInstance3D] = []
var _chase_camera: Camera3D
var _cockpit_camera: Camera3D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	mass = vehicle_mass
	gravity_scale = 1.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, -center_of_mass_drop, 0.0)
	continuous_cd = true
	can_sleep = true
	linear_damp = 0.04
	angular_damp = 0.32
	max_contacts_reported = 12
	contact_monitor = true
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	var physics_material: PhysicsMaterial = PhysicsMaterial.new()
	physics_material.friction = 0.24
	physics_material.bounce = 0.02
	physics_material_override = physics_material
	_build_car()
	_build_cameras()
	_build_skid_marks()
	_spawn_transform = global_transform
	_apply_camera_mode()
	if park_when_unoccupied:
		freeze = true


func _physics_process(delta: float) -> void:
	_read_input()
	_update_steering(delta)
	if freeze:
		_wheel_contact_count = 0
		_update_wheel_visuals(delta)
		return
	_apply_wheel_forces(delta)
	_apply_air_drag()
	_update_wheel_visuals(delta)


func apply_handling_preset(preset_name: String) -> void:
	handling_profile = preset_name.to_upper()
	match handling_profile:
		"SPORT":
			vehicle_mass = 1150.0
			center_of_mass_drop = 0.28
			suspension_stiffness = 36000.0
			suspension_damping = 4800.0
			engine_force = 22000.0
			reverse_force = 8500.0
			brake_force = 26000.0
			max_forward_speed = 75.0
			max_reverse_speed = 16.0
			front_drive_share = 0.38
			traction_control_strength = 0.92
			aerodynamic_drag = 0.24
			tire_friction = 1.55
			sliding_grip_ratio = 0.78
			drift_rear_friction = 0.58
			grip_recovery_seconds = 0.90
		"CHILL":
			vehicle_mass = 1320.0
			center_of_mass_drop = 0.32
			suspension_stiffness = 41000.0
			suspension_damping = 5400.0
			engine_force = 9800.0
			reverse_force = 6200.0
			brake_force = 15000.0
			max_forward_speed = 43.0
			max_reverse_speed = 13.0
			front_drive_share = 0.0
			traction_control_strength = 0.72
			aerodynamic_drag = 0.42
			tire_friction = 1.45
			sliding_grip_ratio = 0.82
			drift_rear_friction = 0.72
			grip_recovery_seconds = 0.72
		_:
			handling_profile = "CUSTOM"
	if is_inside_tree():
		mass = vehicle_mass
		center_of_mass = Vector3(0.0, -center_of_mass_drop, 0.0)


func set_driver_active(value: bool) -> void:
	driver_active = value
	_reset_skid_sampling()
	if value:
		if freeze:
			# A parked rigid body must not carry a stale solver impulse into the
			# first active frame after the player enters it again.
			linear_velocity = Vector3.ZERO
			angular_velocity = Vector3.ZERO
			constant_force = Vector3.ZERO
			constant_torque = Vector3.ZERO
		freeze = false
		sleeping = false
	elif park_when_unoccupied:
		freeze = true
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		constant_force = Vector3.ZERO
		constant_torque = Vector3.ZERO
	_apply_camera_mode()


func toggle_camera() -> void:
	cockpit_camera = not cockpit_camera
	_apply_camera_mode()


func camera_mode_name() -> String:
	return "COCKPIT" if cockpit_camera else "CHASE"


func speed_kph() -> float:
	var forward: Vector3 = -global_transform.basis.z.normalized()
	return abs(linear_velocity.dot(forward)) * 3.6


func get_wheel_contact_count() -> int:
	return _wheel_contact_count


func get_skid_mark_count() -> int:
	return _skid_segments.size()


func get_rear_grip_average() -> float:
	return (_wheel_grip[2] + _wheel_grip[3]) * 0.5


func get_max_wheel_slip() -> float:
	var result: float = 0.0
	for slip: float in _wheel_slip:
		result = max(result, slip)
	return result


func get_max_lateral_slip() -> float:
	return _wheel_lateral_slip.max()


func get_max_demand_slip() -> float:
	return _wheel_demand_slip.max()


func get_suspension_travel_spread() -> float:
	if _wheel_lengths.is_empty():
		return 0.0
	var shortest: float = _wheel_lengths[0]
	var longest: float = _wheel_lengths[0]
	for length: float in _wheel_lengths:
		shortest = min(shortest, length)
		longest = max(longest, length)
	return longest - shortest


func chassis_tilt_degrees() -> float:
	var up_alignment: float = clamp(global_transform.basis.y.normalized().dot(Vector3.UP), -1.0, 1.0)
	return rad_to_deg(acos(up_alignment))


func reset_to_spawn() -> void:
	freeze = true
	global_transform = _spawn_transform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	drifting = false
	_steering_angle = 0.0
	_reset_tire_state()
	freeze = park_when_unoccupied and not driver_active
	if driver_active:
		sleeping = false


func set_spawn_transform(value: Transform3D) -> void:
	_spawn_transform = value


func _read_input() -> void:
	_throttle_input = 0.0
	_brake_input = 0.0
	_steering_input = 0.0
	if not driver_active or _input_is_blocked():
		drifting = false
		return
	var forward_amount: float = Input.get_action_strength("move_forward")
	var backward_amount: float = Input.get_action_strength("move_back")
	_steering_input = Input.get_action_strength("move_left") - Input.get_action_strength("move_right")
	var forward_speed: float = linear_velocity.dot(-global_transform.basis.z.normalized())
	if backward_amount > 0.01 and forward_speed > 1.2:
		_brake_input = backward_amount
	else:
		_throttle_input = forward_amount - backward_amount
	drifting = Input.is_action_pressed("drift") and abs(forward_speed) > 5.0
	if drifting:
		_brake_input = max(_brake_input, 0.35)


func _update_steering(delta: float) -> void:
	var planar_speed: float = linear_velocity.slide(Vector3.UP).length()
	var steering_speed: float = max(planar_speed, 5.0)
	var acceleration_limited_angle: float = atan(
		max(steering_wheelbase, 0.1)
		* max(target_lateral_acceleration, 0.1)
		/ (steering_speed * steering_speed)
	)
	var available_angle: float = min(max_steering_angle, acceleration_limited_angle)
	var target_angle: float = _steering_input * available_angle
	var high_speed_ratio: float = clamp(planar_speed / 27.78, 0.0, 1.0)
	var response: float = lerp(
		steering_response,
		steering_response * high_speed_steering_response_scale,
		high_speed_ratio
	)
	_steering_angle = move_toward(_steering_angle, target_angle, response * delta)


func _apply_wheel_forces(delta: float) -> void:
	_wheel_contact_count = 0
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var body_up: Vector3 = global_transform.basis.y.normalized()
	var body_forward: Vector3 = -global_transform.basis.z.normalized()
	var ray_direction: Vector3 = -body_up
	var ray_length: float = suspension_rest_length + suspension_travel + wheel_radius
	var body_speed: float = linear_velocity.dot(body_forward)

	for index: int in range(_wheel_anchors.size()):
		var anchor_world: Vector3 = global_transform * _wheel_anchors[index]
		var hit: Dictionary = _find_wheel_contact(space, anchor_world, body_up, ray_direction, ray_length)
		if hit.is_empty():
			_wheel_lengths[index] = suspension_rest_length + suspension_travel
			_wheel_slip[index] = 0.0
			_wheel_lateral_slip[index] = 0.0
			_wheel_demand_slip[index] = 0.0
			_last_skid_positions[index] = null
			continue

		_wheel_contact_count += 1
		var contact_position: Vector3 = hit["position"] as Vector3
		var contact_normal: Vector3 = (hit["normal"] as Vector3).normalized()
		var distance: float = max((anchor_world - contact_position).dot(body_up), 0.0)
		var spring_length: float = clamp(distance - wheel_radius, suspension_rest_length - suspension_travel, suspension_rest_length + suspension_travel)
		_wheel_lengths[index] = spring_length
		var compression: float = suspension_rest_length - spring_length
		var offset: Vector3 = contact_position - global_position
		var point_velocity: Vector3 = linear_velocity + angular_velocity.cross(offset)
		var suspension_velocity: float = point_velocity.dot(body_up)
		var spring_force_magnitude: float = max(compression * suspension_stiffness - suspension_velocity * suspension_damping, 0.0)
		var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
		var maximum_force: float = mass * gravity * maximum_suspension_load / float(_wheel_anchors.size())
		spring_force_magnitude = min(spring_force_magnitude, maximum_force)
		if spring_force_magnitude <= 0.0:
			continue
		apply_force(body_up * spring_force_magnitude, offset)

		var is_front: bool = index < 2
		var is_rear: bool = not is_front
		var wheel_forward: Vector3 = body_forward
		if is_front:
			wheel_forward = Basis(body_up, _steering_angle) * wheel_forward
		wheel_forward = wheel_forward.slide(contact_normal).normalized()
		var wheel_right: Vector3 = wheel_forward.cross(contact_normal).normalized()
		var lateral_speed: float = point_velocity.dot(wheel_right)
		var longitudinal_speed: float = point_velocity.dot(wheel_forward)

		var base_stiffness: float = front_lateral_stiffness if is_front else rear_lateral_stiffness
		var lost_grip: float = 1.0 - _wheel_grip[index]
		var lateral_stiffness: float = lerp(base_stiffness, drift_rear_stiffness, lost_grip if is_rear else lost_grip * 0.45)
		var desired_lateral_force: float = -lateral_speed * lateral_stiffness
		var desired_longitudinal_force: float = 0.0

		var static_limit: float = max(spring_force_magnitude * tire_friction, 1.0)
		if abs(_throttle_input) > 0.01:
			var force_limit: float = engine_force if _throttle_input > 0.0 else reverse_force
			var speed_limit: float = max_forward_speed if _throttle_input > 0.0 else max_reverse_speed
			var speed_fade: float = clamp(1.0 - abs(body_speed) / speed_limit, 0.0, 1.0)
			var axle_share: float = front_drive_share if is_front else 1.0 - front_drive_share
			var raw_drive_force: float = _throttle_input * force_limit * speed_fade * axle_share * 0.5
			var managed_drive_force: float = clamp(raw_drive_force, -static_limit * 0.96, static_limit * 0.96)
			desired_longitudinal_force += lerp(raw_drive_force, managed_drive_force, traction_control_strength)

		if _brake_input > 0.01 and abs(longitudinal_speed) > 0.05:
			desired_longitudinal_force += -sign(longitudinal_speed) * brake_force * _brake_input * 0.25
		elif abs(_throttle_input) < 0.01:
			desired_longitudinal_force += clamp(-longitudinal_speed * 95.0, -500.0, 500.0)

		var combined_demand: float = Vector2(desired_lateral_force, desired_longitudinal_force).length()
		var normalized_lateral_slip: float = abs(lateral_speed) / (abs(longitudinal_speed) + 2.0)
		var brake_lock_slip: float = _brake_input * clamp(abs(longitudinal_speed) / 8.0, 0.0, 1.0)
		var demand_slip: float = clamp((combined_demand / static_limit - 1.0) / 0.65, 0.0, 1.0)
		_wheel_lateral_slip[index] = normalized_lateral_slip
		_wheel_demand_slip[index] = demand_slip
		var slip_intensity: float = clamp(max(normalized_lateral_slip / 0.34, brake_lock_slip * 0.88, demand_slip), 0.0, 1.0)
		if is_rear and drifting:
			slip_intensity = max(slip_intensity, 0.96)
		_wheel_slip[index] = slip_intensity

		var minimum_grip: float = sliding_grip_ratio
		if is_rear and drifting:
			minimum_grip = clamp(drift_rear_friction / max(tire_friction, 0.01), 0.2, 0.95)
		var grip_loss_intensity: float = slip_intensity if _brake_input > 0.01 or (is_rear and drifting) else 0.0
		var target_grip: float = lerp(1.0, minimum_grip, grip_loss_intensity)
		if target_grip < _wheel_grip[index]:
			_wheel_grip[index] = move_toward(_wheel_grip[index], target_grip, grip_loss_rate * delta)
		else:
			_wheel_grip[index] = move_toward(_wheel_grip[index], 1.0, delta / max(grip_recovery_seconds, 0.05))

		var dynamic_limit: float = static_limit * _wheel_grip[index]
		var force_scale: float = min(1.0, dynamic_limit / max(combined_demand, 1.0))
		var tire_force: Vector3 = (
			wheel_right * desired_lateral_force + wheel_forward * desired_longitudinal_force
		) * force_scale
		apply_force(tire_force, offset)

		if slip_intensity >= skid_slip_threshold and point_velocity.length() > 3.5:
			_add_skid_sample(index, contact_position, contact_normal, slip_intensity)
		else:
			_last_skid_positions[index] = null

	_apply_yaw_rate_assist(body_up, body_speed)


func _apply_yaw_rate_assist(body_up: Vector3, forward_speed: float) -> void:
	if _wheel_contact_count < 2 or absf(forward_speed) < 3.0:
		return
	var desired_yaw_rate: float = forward_speed * tan(_steering_angle) / max(steering_wheelbase, 0.1)
	desired_yaw_rate = clamp(desired_yaw_rate, -0.9, 0.9)
	var current_yaw_rate: float = angular_velocity.dot(body_up)
	var assist_torque: float = (desired_yaw_rate - current_yaw_rate) * mass * yaw_rate_assist
	apply_torque(body_up * clamp(assist_torque, -mass * 3.0, mass * 3.0))


func _find_wheel_contact(
	space: PhysicsDirectSpaceState3D,
	anchor_world: Vector3,
	body_up: Vector3,
	ray_direction: Vector3,
	ray_length: float
) -> Dictionary:
	var primary_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		anchor_world + body_up * 0.08,
		anchor_world + ray_direction * ray_length,
		collision_mask,
		[get_rid()]
	)
	var hit: Dictionary = space.intersect_ray(primary_query)
	if not hit.is_empty() or body_up.dot(Vector3.UP) < 0.35:
		return hit
	var vertical_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		anchor_world + Vector3.UP * 0.35,
		anchor_world + Vector3.DOWN * (ray_length + 0.65),
		collision_mask,
		[get_rid()]
	)
	return space.intersect_ray(vertical_query)


func _apply_air_drag() -> void:
	var speed_squared: float = linear_velocity.length_squared()
	if speed_squared < 0.01:
		return
	apply_central_force(-linear_velocity.normalized() * speed_squared * aerodynamic_drag)


func _build_car() -> void:
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.name = "Collision"
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(1.9, 0.82, 4.25)
	collision.shape = shape
	collision.position.y = 0.18
	add_child(collision)

	var visual_root: Node3D = Node3D.new()
	visual_root.name = "VisualRoot"
	add_child(visual_root)
	var body: MeshInstance3D = MeshInstance3D.new()
	body.name = "Body"
	var body_mesh: BoxMesh = BoxMesh.new()
	body_mesh.size = Vector3(1.9, 0.7, 4.2)
	body.mesh = body_mesh
	body.position.y = 0.22
	var paint: StandardMaterial3D = StandardMaterial3D.new()
	paint.albedo_color = Color("e95f3d")
	paint.metallic = 0.68
	paint.roughness = 0.22
	body.material_override = paint
	_body_paint = paint
	visual_root.add_child(body)

	var cabin: MeshInstance3D = MeshInstance3D.new()
	cabin.name = "Cabin"
	var cabin_mesh: BoxMesh = BoxMesh.new()
	cabin_mesh.size = Vector3(1.55, 0.62, 1.82)
	cabin.mesh = cabin_mesh
	cabin.position = Vector3(0.0, 0.85, 0.18)
	var glass: StandardMaterial3D = StandardMaterial3D.new()
	glass.albedo_color = Color("183443")
	glass.metallic = 0.35
	glass.roughness = 0.16
	cabin.material_override = glass
	visual_root.add_child(cabin)

	for index: int in range(_wheel_anchors.size()):
		var steer_pivot: Node3D = Node3D.new()
		steer_pivot.name = "Wheel_%d" % index
		steer_pivot.position = _wheel_anchors[index] + Vector3.DOWN * suspension_rest_length
		visual_root.add_child(steer_pivot)
		var roll_pivot: Node3D = Node3D.new()
		roll_pivot.name = "RollPivot"
		steer_pivot.add_child(roll_pivot)
		var wheel: MeshInstance3D = MeshInstance3D.new()
		wheel.name = "Mesh"
		var wheel_mesh: CylinderMesh = CylinderMesh.new()
		wheel_mesh.top_radius = wheel_radius
		wheel_mesh.bottom_radius = wheel_radius
		wheel_mesh.height = 0.3
		wheel_mesh.radial_segments = 16
		wheel.mesh = wheel_mesh
		wheel.rotation.z = PI * 0.5
		var rubber: StandardMaterial3D = StandardMaterial3D.new()
		rubber.albedo_color = Color("17191b")
		rubber.roughness = 0.96
		wheel.material_override = rubber
		roll_pivot.add_child(wheel)
		_wheel_steer_pivots.append(steer_pivot)
		_wheel_roll_pivots.append(roll_pivot)


func apply_skin(skin_name: String) -> void:
	if _body_paint == null:
		return
	var preset: Dictionary = CAR_SKINS.get(skin_name.to_upper(), CAR_SKINS["RACING RED"])
	_body_paint.albedo_color = preset["albedo"] as Color
	_body_paint.metallic = float(preset["metallic"])
	_body_paint.roughness = float(preset["roughness"])


func _build_cameras() -> void:
	var chase_pivot: Node3D = Node3D.new()
	chase_pivot.name = "ChasePivot"
	chase_pivot.position.y = 1.15
	chase_pivot.rotation.x = -0.16
	add_child(chase_pivot)
	var spring_arm: SpringArm3D = SpringArm3D.new()
	spring_arm.name = "SpringArm"
	spring_arm.spring_length = 7.6
	spring_arm.margin = 0.25
	spring_arm.collision_mask = 1
	chase_pivot.add_child(spring_arm)
	_chase_camera = Camera3D.new()
	_chase_camera.name = "ChaseCamera"
	_chase_camera.fov = 82.0
	_chase_camera.near = 0.08
	spring_arm.add_child(_chase_camera)

	_cockpit_camera = Camera3D.new()
	_cockpit_camera.name = "CockpitCamera"
	_cockpit_camera.position = Vector3(0.0, 0.98, -0.42)
	_cockpit_camera.fov = 86.0
	_cockpit_camera.near = 0.05
	add_child(_cockpit_camera)


func _build_skid_marks() -> void:
	_skid_root = Node3D.new()
	_skid_root.name = "SkidMarks"
	add_child(_skid_root)
	_skid_root.top_level = true
	_skid_root.global_transform = Transform3D.IDENTITY
	_skid_material = StandardMaterial3D.new()
	_skid_material.albedo_color = Color(0.0, 0.0, 0.0, 1.0)
	_skid_material.roughness = 1.0
	_skid_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_skid_material.cull_mode = BaseMaterial3D.CULL_DISABLED


func _add_skid_sample(index: int, contact_position: Vector3, contact_normal: Vector3, intensity: float) -> void:
	var lifted_position: Vector3 = contact_position + contact_normal * skid_surface_lift
	var previous_value: Variant = _last_skid_positions[index]
	_last_skid_positions[index] = lifted_position
	if previous_value == null:
		return
	var previous: Vector3 = previous_value as Vector3
	var travel: Vector3 = lifted_position - previous
	var distance: float = travel.length()
	if distance < 0.08 or distance > 2.5:
		return
	var mark_right: Vector3 = travel.normalized().cross(contact_normal).normalized()
	if mark_right.length_squared() < 0.1:
		return
	var half_width: float = skid_mark_width * lerp(0.72, 1.0, intensity) * 0.5
	var p0: Vector3 = previous - mark_right * half_width
	var p1: Vector3 = previous + mark_right * half_width
	var p2: Vector3 = lifted_position + mark_right * half_width
	var p3: Vector3 = lifted_position - mark_right * half_width
	var mesh: ImmediateMesh = ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _skid_material)
	for vertex: Vector3 in [p0, p1, p2, p0, p2, p3]:
		mesh.surface_set_normal(contact_normal)
		mesh.surface_add_vertex(vertex)
	mesh.surface_end()
	var segment: MeshInstance3D = MeshInstance3D.new()
	segment.mesh = mesh
	segment.material_override = _skid_material
	segment.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_skid_root.add_child(segment)
	_skid_segments.append(segment)
	while _skid_segments.size() > max_skid_segments:
		var oldest: MeshInstance3D = _skid_segments.pop_front()
		oldest.queue_free()


func _apply_camera_mode() -> void:
	if _chase_camera == null:
		return
	_chase_camera.current = driver_active and not cockpit_camera
	_cockpit_camera.current = driver_active and cockpit_camera


func _update_wheel_visuals(delta: float) -> void:
	var forward_speed: float = linear_velocity.dot(-global_transform.basis.z.normalized())
	for index: int in range(_wheel_steer_pivots.size()):
		var steer_pivot: Node3D = _wheel_steer_pivots[index]
		steer_pivot.position = _wheel_anchors[index] + Vector3.DOWN * _wheel_lengths[index]
		steer_pivot.rotation.y = _steering_angle if index < 2 else 0.0
		_wheel_roll_angles[index] = fposmod(
			_wheel_roll_angles[index] - forward_speed * delta / max(wheel_radius, 0.01),
			TAU
		)
		_wheel_roll_pivots[index].rotation.x = _wheel_roll_angles[index]


func _reset_tire_state() -> void:
	for index: int in range(_wheel_grip.size()):
		_wheel_grip[index] = 1.0
		_wheel_slip[index] = 0.0
	_reset_skid_sampling()


func _reset_skid_sampling() -> void:
	for index: int in range(_last_skid_positions.size()):
		_last_skid_positions[index] = null


func _input_is_blocked() -> bool:
	var lab: Node = get_parent()
	if lab != null and bool(lab.get("input_blocked")):
		return true
	var world_ui: Node = get_node_or_null("../../WorldUI")
	return world_ui != null and bool(world_ui.get("panel_open"))
