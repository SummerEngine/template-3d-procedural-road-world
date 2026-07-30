class_name InteractiveObstacle
extends Node3D

enum Variant {
	PUSHABLE_ROCK = 0, # configurable rock count / player & car pushable
	FALLING_TREE = 1,  # collapsible / falling tree triggered by car or E key
	SUPPLY_CRATE = 2,  # extra prop - breakable crate
	BOUNCY_BARREL = 3   # extra prop - bouncy / impulse barrel
}

@export var variant: Variant = Variant.PUSHABLE_ROCK
@export var auto_trigger_distance: float = 7.0
@export var fallen: bool = false
@export var respawnable: bool = false

var _body: Node = null
var _pivot: Node3D = null
var _trigger_area: Area3D = null
var _has_fallen: bool = false
var _initial_transform: Transform3D
var _fall_tween: Tween = null
var _crate_hit_count: int = 0
signal interacted(variant_type: int)

func _ready() -> void:
	_initial_transform = global_transform
	_has_fallen = fallen
	match variant:
		Variant.PUSHABLE_ROCK:
			_build_pushable_rock()
		Variant.FALLING_TREE:
			_build_falling_tree()
		Variant.SUPPLY_CRATE:
			_build_crate()
		Variant.BOUNCY_BARREL:
			_build_barrel()
	add_to_group("interactive_obstacle")
	if _trigger_area == null:
		# fallback trigger for generic interact
		var generic_area := Area3D.new()
		generic_area.name = "GenericTrigger"
		var shape_node := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = auto_trigger_distance
		shape_node.shape = sphere
		generic_area.add_child(shape_node)
		add_child(generic_area)
		_trigger_area = generic_area


func _physics_process(_delta: float) -> void:
	if variant == Variant.PUSHABLE_ROCK:
		_process_pushable_logic()


func _process(_delta: float) -> void:
	if variant == Variant.FALLING_TREE and not _has_fallen:
		_check_auto_fall()
	# interact key when player nearby
	if _trigger_area != null and Input.is_action_just_pressed("interact"):
		var bodies := _trigger_area.get_overlapping_bodies()
		for b in bodies:
			if b is CharacterBody3D or b.name.contains("Player"):
				if global_position.distance_to(b.global_position) < 4.5:
					interact(b.global_position)
					break


func interact(from_position: Vector3 = Vector3.ZERO) -> void:
	match variant:
		Variant.PUSHABLE_ROCK:
			if _body is RigidBody3D:
				var dir: Vector3 = global_position - from_position
				dir.y = 0.25
				if dir.length_squared() < 0.01:
					dir = -global_transform.basis.z
				dir = dir.normalized()
				(_body as RigidBody3D).apply_central_impulse(dir * 18.0 + Vector3.UP * 3.0)
		Variant.FALLING_TREE:
			trigger_fall(from_position)
		Variant.SUPPLY_CRATE:
			if _body is RigidBody3D:
				(_body as RigidBody3D).apply_central_impulse(Vector3.UP * 6.0 + Vector3(randf()-0.5, 0.2, randf()-0.5).normalized() * 4.0)
				_crate_hit_count += 1
				if _crate_hit_count > 3:
					_play_crate_break()
		Variant.BOUNCY_BARREL:
			if _body is RigidBody3D:
				(_body as RigidBody3D).apply_central_impulse(Vector3.UP * 12.0)
	interacted.emit(variant)


func trigger_fall(from_position: Vector3 = Vector3.ZERO) -> void:
	if _has_fallen:
		return
	if _pivot == null:
		return
	_has_fallen = true
	fallen = true
	if _trigger_area:
		_trigger_area.monitoring = false
		_trigger_area.monitorable = false
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var fall_angle_y: float = rng.randf_range(0.0, TAU)
	if from_position != Vector3.ZERO:
		var to_self: Vector3 = global_position - from_position
		to_self.y = 0.0
		if to_self.length_squared() > 0.2:
			fall_angle_y = atan2(to_self.x, to_self.z) + rng.randf_range(-0.6, 0.6)
	_pivot.rotation.y = fall_angle_y
	# random tilt direction
	_pivot.rotation.z = 0.0
	_pivot.rotation.x = 0.0
	if _fall_tween != null and _fall_tween.is_valid():
		_fall_tween.kill()
	_fall_tween = get_tree().create_tween()
	_fall_tween.tween_property(_pivot, "rotation:x", PI * 0.5, 0.85).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_fall_tween.tween_callback(_on_fall_finished)


func _on_fall_finished() -> void:
	# add ground blocking collision after fall - makes world more interactive after collapse
	var ground_block := StaticBody3D.new()
	ground_block.name = "FallenBlock"
	ground_block.collision_layer = 1
	ground_block.collision_mask = 1
	add_child(ground_block)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.2, 1.0, 5.5)
	shape.shape = box
	shape.position = Vector3(0.0, 0.5, 2.2)
	shape.rotation.x = 0.0
	ground_block.add_child(shape)
	# visual dust placeholder via darkening - simple robust feedback
	if _pivot != null:
		for child in _pivot.get_children():
			if child is MeshInstance3D:
				var mat := child.get_active_material(0) as StandardMaterial3D
				if mat != null:
					mat.albedo_color = mat.albedo_color.darkened(0.15)
	# also darken trunk mesh if present
	for trunk_child in get_children():
		if trunk_child.name == "Pivot":
			for sub in trunk_child.get_children():
				if sub is StaticBody3D:
					for mesh_child in sub.get_children():
						if mesh_child is MeshInstance3D:
							var m := mesh_child.get_active_material(0) as StandardMaterial3D
							if m != null:
								m.albedo_color = m.albedo_color.darkened(0.08)


func _build_pushable_rock() -> void:
	var body := RigidBody3D.new()
	body.name = "RockBody"
	body.mass = 135.0
	body.linear_damp = 0.55
	body.angular_damp = 0.68
	body.collision_layer = 1
	body.collision_mask = 1
	body.continuous_cd = true
	body.contact_monitor = true
	body.max_contacts_reported = 4
	add_child(body)
	_body = body

	var col := CollisionShape3D.new()
	col.name = "RockShape"
	var sphere_shape := SphereShape3D.new()
	sphere_shape.radius = 1.0
	col.shape = sphere_shape
	body.add_child(col)

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "Mesh"
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = 1.0
	sphere_mesh.height = 2.0
	sphere_mesh.radial_segments = 12
	sphere_mesh.rings = 7
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("7a7d81")
	mat.roughness = 0.96
	mat.metallic = 0.05
	sphere_mesh.material = mat
	mesh_inst.mesh = sphere_mesh
	body.add_child(mesh_inst)

	# random deform scale for visual variety
	mesh_inst.scale = Vector3(randf_range(0.85, 1.25), randf_range(0.75, 1.15), randf_range(0.85, 1.25))

	var area := Area3D.new()
	area.name = "PushArea"
	area.collision_layer = 0
	area.collision_mask = 1
	area.monitoring = true
	var area_shape_node := CollisionShape3D.new()
	var area_sphere := SphereShape3D.new()
	area_sphere.radius = 2.8
	area_shape_node.shape = area_sphere
	area.add_child(area_shape_node)
	body.add_child(area)
	_trigger_area = area
	area.body_entered.connect(_on_rock_body_entered)


func _on_rock_body_entered(b: Node) -> void:
	if not _body is RigidBody3D:
		return
	var rb := _body as RigidBody3D
	if b is CharacterBody3D:
		var dir: Vector3 = rb.global_position - b.global_position
		dir.y = 0.15
		if dir.length_squared() < 0.01:
			return
		dir = dir.normalized()
		var speed: float = 1.0
		if b is CharacterBody3D:
			speed = (b as CharacterBody3D).velocity.length()
		var push_strength: float = 7.0 + speed * 0.6
		rb.apply_central_impulse(dir * push_strength + Vector3.UP * 1.2)
	elif b is RigidBody3D:
		# car will push automatically, add small extra for feedback
		if b.name.contains("ArcadeCar") or b.name.contains("Car"):
			var dir2: Vector3 = rb.global_position - b.global_position
			dir2.y = 0.1
			dir2 = dir2.normalized()
			rb.apply_central_impulse(dir2 * 4.0)


func _process_pushable_logic() -> void:
	if _trigger_area == null:
		return
	if not _body is RigidBody3D:
		return
	var bodies := _trigger_area.get_overlapping_bodies()
	var rb := _body as RigidBody3D
	for b in bodies:
		if b == rb:
			continue
		if b is CharacterBody3D:
			var char_body := b as CharacterBody3D
			if char_body.velocity.length() < 0.5:
				continue
			var dir: Vector3 = rb.global_position - char_body.global_position
			dir.y = 0.1
			if dir.length_squared() < 0.01:
				continue
			dir = dir.normalized()
			# only push if character moving toward rock
			var toward: float = char_body.velocity.normalized().dot(dir * -1.0)
			if toward < -0.15:
				rb.apply_central_force(dir * 45.0)


func _build_falling_tree() -> void:
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)

	var trunk_body := StaticBody3D.new()
	trunk_body.name = "TrunkBody"
	trunk_body.collision_layer = 1
	trunk_body.collision_mask = 1
	_pivot.add_child(trunk_body)

	var trunk_col := CollisionShape3D.new()
	trunk_col.name = "TrunkShape"
	var cyl_shape := CylinderShape3D.new()
	cyl_shape.height = 4.2
	cyl_shape.radius = 0.34
	trunk_col.shape = cyl_shape
	trunk_col.position.y = 2.1
	trunk_body.add_child(trunk_col)

	var trunk_mesh := MeshInstance3D.new()
	trunk_mesh.name = "TrunkMesh"
	var cyl_mesh := CylinderMesh.new()
	cyl_mesh.top_radius = 0.26
	cyl_mesh.bottom_radius = 0.38
	cyl_mesh.height = 4.2
	cyl_mesh.radial_segments = 8
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color("6b4a2e")
	trunk_mat.roughness = 0.98
	cyl_mesh.material = trunk_mat
	trunk_mesh.mesh = cyl_mesh
	trunk_mesh.position.y = 2.1
	trunk_body.add_child(trunk_mesh)

	var canopy_body := MeshInstance3D.new()
	canopy_body.name = "Canopy"
	var cone_mesh := CylinderMesh.new()
	cone_mesh.top_radius = 0.22
	cone_mesh.bottom_radius = 1.55
	cone_mesh.height = 4.0
	cone_mesh.radial_segments = 9
	var canopy_mat := StandardMaterial3D.new()
	canopy_mat.albedo_color = Color("2e5a3a")
	canopy_mat.roughness = 0.92
	cone_mesh.material = canopy_mat
	canopy_body.mesh = cone_mesh
	canopy_body.position.y = 5.2
	_pivot.add_child(canopy_body)

	# trigger area around tree
	var area := Area3D.new()
	area.name = "FallTrigger"
	area.collision_layer = 0
	area.collision_mask = 1
	var area_shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = auto_trigger_distance
	area_shape.shape = sphere
	area_shape.position.y = 2.0
	area.add_child(area_shape)
	add_child(area)
	_trigger_area = area
	area.body_entered.connect(_on_fall_trigger_entered)


func _on_fall_trigger_entered(b: Node) -> void:
	if _has_fallen:
		return
	if b is CharacterBody3D or b is RigidBody3D:
		# check distance and speed for car
		if b is RigidBody3D:
			var rb := b as RigidBody3D
			if rb.linear_velocity.length() < 2.0 and not rb.name.contains("Car"):
				return
		trigger_fall(b.global_position)


func _check_auto_fall() -> void:
	if _trigger_area == null or _has_fallen:
		return
	var bodies := _trigger_area.get_overlapping_bodies()
	for b in bodies:
		if b is RigidBody3D:
			var rb := b as RigidBody3D
			if rb.linear_velocity.length() > 3.5:
				trigger_fall(rb.global_position)
				break


func _build_crate() -> void:
	var body := RigidBody3D.new()
	body.name = "CrateBody"
	body.mass = 32.0
	body.linear_damp = 0.38
	body.angular_damp = 0.55
	body.collision_layer = 1
	body.collision_mask = 1
	body.contact_monitor = true
	body.max_contacts_reported = 4
	add_child(body)
	_body = body

	var col := CollisionShape3D.new()
	col.name = "CrateShape"
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(1.2, 1.2, 1.2)
	col.shape = box_shape
	body.add_child(col)

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "Mesh"
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(1.2, 1.2, 1.2)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("c8a06a")
	mat.roughness = 0.82
	mat.metallic = 0.05
	box_mesh.material = mat
	mesh_inst.mesh = box_mesh
	body.add_child(mesh_inst)

	var area := Area3D.new()
	area.name = "CrateTrigger"
	area.collision_layer = 0
	area.collision_mask = 1
	var area_shape_node := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 2.5
	area_shape_node.shape = sphere
	area.add_child(area_shape_node)
	body.add_child(area)
	_trigger_area = area

	body.body_entered.connect(_on_crate_body_entered)


func _on_crate_body_entered(_b: Node) -> void:
	_crate_hit_count += 1
	if _crate_hit_count == 2 and _body is MeshInstance3D == false:
		# visual feedback - darken
		if _body is RigidBody3D:
			for child in (_body as RigidBody3D).get_children():
				if child is MeshInstance3D:
					var mi := child as MeshInstance3D
					var mat := mi.get_active_material(0) as StandardMaterial3D
					if mat:
						mat.albedo_color = mat.albedo_color.darkened(0.12)


func _play_crate_break() -> void:
	# simple break effect: scale down and queue free after delay
	var tween := get_tree().create_tween()
	tween.tween_property(self, "scale", Vector3(0.01, 0.01, 0.01), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)


func _build_barrel() -> void:
	var body := RigidBody3D.new()
	body.name = "BarrelBody"
	body.mass = 45.0
	body.linear_damp = 0.45
	body.angular_damp = 0.6
	body.collision_layer = 1
	body.collision_mask = 1
	add_child(body)
	_body = body

	var col := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.height = 1.4
	cyl.radius = 0.6
	col.shape = cyl
	body.add_child(col)

	var mesh_inst := MeshInstance3D.new()
	var cyl_mesh := CylinderMesh.new()
	cyl_mesh.height = 1.4
	cyl_mesh.top_radius = 0.6
	cyl_mesh.bottom_radius = 0.6
	cyl_mesh.radial_segments = 12
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("8a5a3a")
	mat.roughness = 0.75
	mat.metallic = 0.2
	cyl_mesh.material = mat
	mesh_inst.mesh = cyl_mesh
	body.add_child(mesh_inst)

	var area := Area3D.new()
	area.name = "BarrelTrigger"
	var shape_node := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 3.0
	shape_node.shape = sphere
	area.add_child(shape_node)
	body.add_child(area)
	_trigger_area = area
