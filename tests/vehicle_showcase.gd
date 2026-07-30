extends Node3D

const CarScript: Script = preload("res://scripts/arcade_car.gd")

var input_blocked: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_actions()
	_build_track()
	var car: RigidBody3D = CarScript.new() as RigidBody3D
	car.name = "ArcadeCar"
	car.set("park_when_unoccupied", false)
	add_child(car)
	car.global_position = Vector3(0.0, 0.95, 55.0)
	car.call("set_spawn_transform", car.global_transform)
	car.call("set_driver_active", true)
	await get_tree().create_timer(0.5).timeout

	Input.action_press("move_forward")
	await get_tree().create_timer(3.2).timeout
	Input.action_release("move_forward")
	Input.action_press("move_back")
	Input.action_press("move_left")
	await get_tree().create_timer(0.55).timeout
	Input.action_release("move_back")
	Input.action_press("move_forward")
	Input.action_press("drift")
	await get_tree().create_timer(1.35).timeout
	Input.action_release("drift")
	Input.action_release("move_left")
	Input.action_release("move_forward")
	await get_tree().create_timer(0.35).timeout
	car.freeze = true
	_show_skid_overview(car)
	print("VEHICLE_SHOWCASE_READY speed=%.1f marks=%d grip=%.2f" % [
		float(car.call("speed_kph")), int(car.call("get_skid_mark_count")),
		float(car.call("get_rear_grip_average")),
	])


func _ensure_actions() -> void:
	for action: StringName in [&"move_forward", &"move_back", &"move_left", &"move_right", &"drift"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)


func _build_track() -> void:
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-58.0, -25.0, 0.0)
	light.light_energy = 1.2
	light.shadow_enabled = true
	add_child(light)

	var ground: StaticBody3D = StaticBody3D.new()
	ground.name = "Track"
	add_child(ground)
	var collision: CollisionShape3D = CollisionShape3D.new()
	var collision_shape: BoxShape3D = BoxShape3D.new()
	collision_shape.size = Vector3(18.0, 0.2, 160.0)
	collision.shape = collision_shape
	collision.position.y = -0.1
	ground.add_child(collision)
	var road: MeshInstance3D = MeshInstance3D.new()
	var road_mesh: BoxMesh = BoxMesh.new()
	road_mesh.size = Vector3(18.0, 0.12, 160.0)
	road.mesh = road_mesh
	road.position.y = 0.06
	var road_material: StandardMaterial3D = StandardMaterial3D.new()
	road_material.albedo_color = Color("4a5053")
	road_material.roughness = 0.95
	road.material_override = road_material
	ground.add_child(road)
	var line: MeshInstance3D = MeshInstance3D.new()
	var line_mesh: BoxMesh = BoxMesh.new()
	line_mesh.size = Vector3(0.22, 0.02, 160.0)
	line.mesh = line_mesh
	line.position.y = 0.13
	var line_material: StandardMaterial3D = StandardMaterial3D.new()
	line_material.albedo_color = Color("e7c85a")
	line.material_override = line_material
	ground.add_child(line)


func _show_skid_overview(car: RigidBody3D) -> void:
	var skid_root: Node3D = car.get_node("SkidMarks") as Node3D
	var bounds: AABB = AABB()
	var has_bounds: bool = false
	var first_index: int = max(0, skid_root.get_child_count() - 120)
	for index: int in range(first_index, skid_root.get_child_count()):
		var segment: MeshInstance3D = skid_root.get_child(index) as MeshInstance3D
		if segment == null:
			continue
		if has_bounds:
			bounds = bounds.merge(segment.get_aabb())
		else:
			bounds = segment.get_aabb()
			has_bounds = true
	if not has_bounds:
		return
	var overview: Camera3D = Camera3D.new()
	overview.name = "SkidOverviewCamera"
	add_child(overview)
	var center: Vector3 = bounds.get_center()
	overview.global_position = center + Vector3(0.0, 25.0, 16.0)
	overview.look_at(center, Vector3.UP)
	overview.current = true
