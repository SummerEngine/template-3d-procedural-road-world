class_name MovementLab
extends Node3D

const MobileControlsScript: Script = preload("res://scripts/mobile_controls.gd")
const MAX_TERRAIN_GRID_CELLS: int = 262144
const CAR_PRESETS: Dictionary = {
	"SPORT": {
		"mass_kg": 1150.0,
		"center_of_mass_drop": 0.28,
		"suspension_stiffness": 36000.0,
		"suspension_damping": 4800.0,
		"top_speed_kph": 270.0,
		"engine_force": 22000.0,
		"brake_force": 26000.0,
		"base_grip": 1.35,
		"sliding_grip": 0.78,
		"drift_grip": 0.58,
		"recovery_seconds": 0.90,
		"front_drive_percent": 38.0,
		"traction_control_percent": 92.0,
	},
	"CHILL": {
		"mass_kg": 1320.0,
		"center_of_mass_drop": 0.32,
		"suspension_stiffness": 41000.0,
		"suspension_damping": 5400.0,
		"top_speed_kph": 155.0,
		"engine_force": 9800.0,
		"brake_force": 15000.0,
		"base_grip": 1.45,
		"sliding_grip": 0.82,
		"drift_grip": 0.72,
		"recovery_seconds": 0.72,
		"front_drive_percent": 0.0,
		"traction_control_percent": 72.0,
	},
}

var _generator: ProceduralWorldGenerator
var _player: MovementPlayerController
var _car: ArcadeCarController
var _parkour_locations: Node3D
var _status_label: Label
var _prompt_label: Label
var _driving: bool = false
var _vehicle_transitioning: bool = false
var input_blocked: bool = true
var _has_started: bool = false
var _hud_root: Control
var _start_menu: Control
var _pause_menu: Control
var _crosshair: Label
var _seed_input: SpinBox
var _chunk_count_input: SpinBox
var _chunk_size_input: SpinBox
var _resolution_input: SpinBox
var _world_size_label: Label
var _mobile_controls: Control
var _handling_preset_input: OptionButton
var _mass_input: SpinBox
var _center_of_mass_input: SpinBox
var _suspension_stiffness_input: SpinBox
var _suspension_damping_input: SpinBox
var _top_speed_input: SpinBox
var _engine_force_input: SpinBox
var _brake_force_input: SpinBox
var _base_grip_input: SpinBox
var _sliding_grip_input: SpinBox
var _drift_grip_input: SpinBox
var _grip_recovery_input: SpinBox
var _front_drive_input: SpinBox
var _traction_control_input: SpinBox
var _park_unoccupied_input: CheckBox
var _skin_input: OptionButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_input_actions()
	call_deferred("_initialize")


func _process(_delta: float) -> void:
	input_blocked = _menu_is_open() or _world_ui_is_open()
	_update_world_size_preview()
	_update_mobile_controls()
	if _player == null or _car == null:
		return
	if not input_blocked and Input.is_action_just_pressed("interact"):
		_toggle_vehicle()
	if not input_blocked and Input.is_action_just_pressed("camera_toggle"):
		if _driving:
			_car.toggle_camera()
		else:
			_player.toggle_camera()
	if not input_blocked and Input.is_action_just_pressed("reset_actor"):
		if _driving:
			_car.reset_to_spawn()
		else:
			_player.reset_to_spawn()
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_ESCAPE or event.keycode == KEY_BACK):
		if _start_menu != null and _start_menu.visible:
			if _has_started:
				_show_pause_menu()
		elif _pause_menu != null and _pause_menu.visible:
			_resume_game()
		else:
			_show_pause_menu()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _has_started and not _menu_is_open() and not _world_ui_is_open():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _initialize() -> void:
	_generator = get_node("../WorldGenerator") as ProceduralWorldGenerator
	_randomize_world_seed()
	if not _generator.world_regenerated.is_connected(_on_world_regenerated):
		_generator.world_regenerated.connect(_on_world_regenerated)
	var free_camera: Camera3D = get_node_or_null("../FreeFlyCamera") as Camera3D
	if free_camera != null:
		free_camera.current = false
		free_camera.set_process(false)
		free_camera.set_process_unhandled_input(false)
	_build_hud()
	_rebuild_lab()
	_show_start_menu()


func _on_world_regenerated(_stats: Dictionary) -> void:
	_rebuild_lab()


func _rebuild_lab() -> void:
	var road_points: PackedVector3Array = _generator.get_road_points()
	if road_points.size() < 8:
		return
	_clear_runtime_nodes()

	var start_index: int = 3
	var start: Vector3 = road_points[start_index]
	var next: Vector3 = road_points[start_index + 1]
	var forward: Vector3 = next - start
	forward.y = 0.0
	forward = forward.normalized()
	var right: Vector3 = forward.cross(Vector3.UP).normalized()

	_player = MovementPlayerController.new()
	_player.name = "Player"
	_player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_player)
	_player.global_position = start + right * 3.2 + Vector3.UP * 0.25
	_player.look_at(_player.global_position + forward, Vector3.UP)
	_player.set_spawn_transform(_player.global_transform)

	_car = ArcadeCarController.new()
	_car.name = "ArcadeCar"
	_car.process_mode = Node.PROCESS_MODE_PAUSABLE
	_apply_vehicle_settings_to(_car)
	add_child(_car)
	_car.global_position = start + forward * 8.0 + Vector3.UP * 0.95
	_car.look_at(_car.global_position + forward, Vector3.UP)
	_car.set_spawn_transform(_car.global_transform)

	_parkour_locations = Node3D.new()
	_parkour_locations.name = "ParkourLocations"
	add_child(_parkour_locations)
	_create_parkour_locations(road_points)
	_driving = false
	_vehicle_transitioning = false
	_player.set_active(true)
	_car.set_driver_active(false)


func _clear_runtime_nodes() -> void:
	for node: Node in [_player, _car, _parkour_locations]:
		if is_instance_valid(node):
			if node.get_parent() == self:
				remove_child(node)
			node.queue_free()
	_player = null
	_car = null
	_parkour_locations = null


func _create_parkour_locations(_road_points: PackedVector3Array) -> void:
	var parkour_plots: Array[Dictionary] = _generator.get_parkour_plots()
	for location_index: int in range(parkour_plots.size()):
		var plot: Dictionary = parkour_plots[location_index]
		var center: Vector2 = plot["center"] as Vector2
		var forward_2d: Vector2 = plot["forward"] as Vector2
		var forward: Vector3 = Vector3(forward_2d.x, 0.0, forward_2d.y)
		var location: Node3D = Node3D.new()
		location.name = "Parkour_%d" % location_index
		_parkour_locations.add_child(location)
		location.global_position = Vector3(center.x, 0.0, center.y)
		location.look_at(location.global_position + forward, Vector3.UP)

		var foundation_material: StandardMaterial3D = _make_parkour_material(Color("4f5757"), 0.04, 0.92)
		var half_extents: Vector2 = plot["half_extents"] as Vector2
		var footprint: Vector2 = half_extents * 2.0 - Vector2(4.0, 4.0)
		var foundation_top: float = _create_terrain_foundation(location, footprint, float(plot["height"]), foundation_material)
		if location_index == 0:
			_build_scaffold_run(location, foundation_top)
		else:
			match int(plot["variant"]):
				0:
					_build_scaffold_run(location, foundation_top)
				1:
					_build_roadside_ruin(location, foundation_top)
				_:
					_build_depot_run(location, foundation_top)


func _create_terrain_foundation(location: Node3D, footprint: Vector2, terrain_height: float, material: StandardMaterial3D) -> float:
	var foundation_top: float = terrain_height + _generator.parkour_foundation_lift
	var foundation_bottom: float = terrain_height - 0.14
	var foundation_height: float = foundation_top - foundation_bottom
	_create_parkour_box(
		location,
		"GroundedFoundation",
		Vector3(0.0, foundation_bottom + foundation_height * 0.5, 0.0),
		Vector3(footprint.x, foundation_height, footprint.y),
		material
	)
	return foundation_top


func _build_scaffold_run(location: Node3D, floor_y: float) -> void:
	var steel: StandardMaterial3D = _make_parkour_material(Color("d68c3f"), 0.34, 0.54)
	var deck: StandardMaterial3D = _make_parkour_material(Color("66777b"), 0.18, 0.70)
	var concrete: StandardMaterial3D = _make_parkour_material(Color("b2aa91"), 0.02, 0.96)
	_create_parkour_box(location, "MantleStep", Vector3(-6.0, floor_y + 0.55, 4.6), Vector3(3.2, 1.10, 2.8), concrete)
	_create_parkour_box(location, "TallWall", Vector3(-6.0, floor_y + 1.40, -3.8), Vector3(4.2, 2.80, 0.55), concrete)
	_create_parkour_box(location, "StepTwo", Vector3(-2.8, floor_y + 0.85, 4.6), Vector3(2.6, 1.70, 2.8), deck)
	_create_supported_platform(location, "MainDeck", Vector2(2.4, 1.1), floor_y + 2.55, Vector3(6.0, 0.34, 5.0), floor_y, deck, steel)
	_create_supported_platform(location, "JumpDeck", Vector2(7.2, -3.4), floor_y + 3.15, Vector3(3.0, 0.30, 3.0), floor_y, deck, steel)
	_create_parkour_box(location, "BalanceBeam", Vector3(4.8, floor_y + 2.88, -1.7), Vector3(0.55, 0.28, 5.2), steel)


func _build_roadside_ruin(location: Node3D, floor_y: float) -> void:
	var stone: StandardMaterial3D = _make_parkour_material(Color("908779"), 0.02, 0.98)
	var cap: StandardMaterial3D = _make_parkour_material(Color("5f6f67"), 0.08, 0.86)
	_create_parkour_box(location, "BrokenWallA", Vector3(-6.5, floor_y + 1.1, -2.0), Vector3(0.65, 2.2, 7.0), stone)
	_create_parkour_box(location, "BrokenWallB", Vector3(1.5, floor_y + 1.7, 5.0), Vector3(7.0, 3.4, 0.65), stone)
	for step_index: int in range(4):
		var height: float = 0.45 + float(step_index) * 0.38
		_create_parkour_box(location, "RuinStep_%d" % step_index, Vector3(-3.0 + step_index * 1.35, floor_y + height * 0.5, 2.0), Vector3(1.5, height, 2.4), stone)
	_create_supported_platform(location, "RuinedBalcony", Vector2(4.8, -2.8), floor_y + 2.75, Vector3(5.0, 0.32, 4.0), floor_y, cap, stone)
	_create_parkour_box(location, "NarrowLintel", Vector3(1.7, floor_y + 3.0, -0.6), Vector3(6.2, 0.34, 0.48), cap)


func _build_depot_run(location: Node3D, floor_y: float) -> void:
	var container_blue: StandardMaterial3D = _make_parkour_material(Color("3f7181"), 0.20, 0.66)
	var container_red: StandardMaterial3D = _make_parkour_material(Color("a8523d"), 0.18, 0.70)
	var frame: StandardMaterial3D = _make_parkour_material(Color("e1b94e"), 0.38, 0.48)
	_create_parkour_box(location, "ContainerLow", Vector3(-4.8, floor_y + 1.15, 2.8), Vector3(6.0, 2.3, 3.0), container_blue)
	_create_parkour_box(location, "ContainerHigh", Vector3(3.0, floor_y + 1.55, -3.0), Vector3(6.5, 3.1, 3.0), container_red)
	for step_index: int in range(3):
		var height: float = 0.55 + step_index * 0.5
		_create_parkour_box(location, "CargoStep_%d" % step_index, Vector3(-8.1 + step_index * 1.25, floor_y + height * 0.5, 3.1), Vector3(1.35, height, 1.8), frame)
	_create_supported_platform(location, "LoadingBridge", Vector2(0.0, 2.8), floor_y + 3.35, Vector3(4.0, 0.28, 1.1), floor_y, frame, frame)
	_create_parkour_box(location, "RailRun", Vector3(7.2, floor_y + 2.65, 1.5), Vector3(0.50, 0.30, 7.0), frame)


func _create_supported_platform(
	parent: Node3D,
	node_name: String,
	center_xz: Vector2,
	center_y: float,
	size: Vector3,
	floor_y: float,
	platform_material: StandardMaterial3D,
	support_material: StandardMaterial3D
) -> void:
	_create_parkour_box(parent, node_name, Vector3(center_xz.x, center_y, center_xz.y), size, platform_material)
	var platform_bottom: float = center_y - size.y * 0.5
	var support_height: float = max(platform_bottom - floor_y + 0.05, 0.2)
	for support_index: int in range(4):
		var x_sign: float = -1.0 if support_index % 2 == 0 else 1.0
		var z_sign: float = -1.0 if support_index < 2 else 1.0
		var support_position: Vector3 = Vector3(
			center_xz.x + x_sign * max(size.x * 0.5 - 0.28, 0.0),
			floor_y + support_height * 0.5,
			center_xz.y + z_sign * max(size.z * 0.5 - 0.28, 0.0)
		)
		_create_parkour_box(parent, "%s_Support_%d" % [node_name, support_index], support_position, Vector3(0.34, support_height, 0.34), support_material)


func _create_parkour_box(parent: Node3D, node_name: String, local_position: Vector3, size: Vector3, material: StandardMaterial3D) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = node_name
	body.position = local_position
	parent.add_child(body)

	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	body.add_child(mesh_instance)

	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	return body


func _make_parkour_material(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	return material


func _toggle_vehicle() -> void:
	if _vehicle_transitioning:
		return
	if _driving:
		_exit_vehicle()
	elif _player.global_position.distance_to(_car.global_position) <= 4.2:
		_enter_vehicle()


func _enter_vehicle() -> void:
	_vehicle_transitioning = true
	_driving = true
	var entering_player: MovementPlayerController = _player
	var entering_car: ArcadeCarController = _car
	entering_player.set_active(false)
	# CharacterBody3D disables its collision shape with set_deferred(). Keep the
	# rigid car parked until the physics server has crossed a frame boundary,
	# otherwise the solver can retain an overlap and eject the car on re-entry.
	await get_tree().physics_frame
	if not is_instance_valid(entering_player) or not is_instance_valid(entering_car):
		_vehicle_transitioning = false
		return
	if entering_player != _player or entering_car != _car:
		_vehicle_transitioning = false
		return
	entering_car.set_driver_active(true)
	_vehicle_transitioning = false


func _exit_vehicle() -> void:
	_driving = false
	_car.set_driver_active(false)
	var exit_position: Vector3 = _car.global_position + _car.global_transform.basis.x * 2.0
	exit_position.y = _generator.get_height_at(exit_position.x, exit_position.z) + 0.12
	_player.global_position = exit_position
	_player.rotation.y = _car.rotation.y
	_player.set_active(true)


func _build_hud() -> void:
	var hud: CanvasLayer = CanvasLayer.new()
	hud.name = "MovementHUD"
	add_child(hud)
	_hud_root = Control.new()
	_hud_root.name = "Root"
	_hud_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.focus_mode = Control.FOCUS_ALL
	_hud_root.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_ENABLED
	hud.add_child(_hud_root)

	_status_label = Label.new()
	_status_label.position = Vector2(18.0, 18.0)
	_status_label.add_theme_font_size_override("font_size", 18)
	_status_label.add_theme_color_override("font_color", Color("dffcf5"))
	_status_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.92))
	_status_label.add_theme_constant_override("shadow_offset_x", 2)
	_status_label.add_theme_constant_override("shadow_offset_y", 2)
	_hud_root.add_child(_status_label)

	_prompt_label = Label.new()
	_prompt_label.set_anchors_preset(Control.PRESET_CENTER)
	_prompt_label.position = Vector2(-190.0, 120.0)
	_prompt_label.custom_minimum_size = Vector2(380.0, 36.0)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.add_theme_font_size_override("font_size", 20)
	_prompt_label.add_theme_color_override("font_color", Color("ffe58a"))
	_prompt_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.95))
	_prompt_label.add_theme_constant_override("shadow_offset_x", 2)
	_prompt_label.add_theme_constant_override("shadow_offset_y", 2)
	_hud_root.add_child(_prompt_label)

	_crosshair = Label.new()
	_crosshair.text = "+"
	_crosshair.set_anchors_preset(Control.PRESET_CENTER)
	_crosshair.position = Vector2(-8.0, -15.0)
	_crosshair.add_theme_font_size_override("font_size", 24)
	_crosshair.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.82))
	_hud_root.add_child(_crosshair)

	_build_start_menu()
	_build_pause_menu()
	_build_mobile_controls()


func _build_mobile_controls() -> void:
	_mobile_controls = MobileControlsScript.new() as Control
	_mobile_controls.connect("look_dragged", _on_touch_look)
	_mobile_controls.connect("menu_requested", _show_pause_menu)
	_hud_root.add_child(_mobile_controls)


func _build_start_menu() -> void:
	var backdrop: ColorRect = ColorRect.new()
	backdrop.name = "StartMenu"
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.015, 0.025, 0.035, 0.94)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.focus_mode = Control.FOCUS_ALL
	backdrop.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_ENABLED
	_hud_root.add_child(backdrop)
	_start_menu = backdrop

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.add_child(center)
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(1120.0, 0.0)
	center.add_child(panel)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color("14242b")
	style.border_color = Color("55c8b3")
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(20.0)
	panel.add_theme_stylebox_override("panel", style)
	var content: VBoxContainer = VBoxContainer.new()
	content.add_theme_constant_override("separation", 9)
	panel.add_child(content)

	var title: Label = Label.new()
	title.text = "PROCEDURAL MOVEMENT LAB"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color("a8f3df"))
	content.add_child(title)
	var subtitle: Label = Label.new()
	subtitle.text = "Generate a finite test world, then explore it on foot or by car."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_color_override("font_color", Color("b6c8c5"))
	content.add_child(subtitle)
	content.add_child(HSeparator.new())

	var settings_columns: HBoxContainer = HBoxContainer.new()
	settings_columns.add_theme_constant_override("separation", 32)
	content.add_child(settings_columns)
	var world_column: VBoxContainer = VBoxContainer.new()
	world_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	world_column.add_theme_constant_override("separation", 6)
	settings_columns.add_child(world_column)
	var world_header: Label = Label.new()
	world_header.text = "WORLD GENERATION"
	world_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	world_header.add_theme_color_override("font_color", Color("a8f3df"))
	world_column.add_child(world_header)

	_seed_input = _add_menu_spin(world_column, "Seed", -999999.0, 999999.0, 1.0, float(_generator.world_seed), true)
	var random_seed_button: Button = Button.new()
	random_seed_button.name = "RandomSeed"
	random_seed_button.text = "RANDOM SEED"
	random_seed_button.pressed.connect(_randomize_world_seed)
	world_column.add_child(random_seed_button)
	_chunk_count_input = _add_menu_spin(world_column, "Chunks per side", 2.0, 10.0, 1.0, float(_generator.chunk_count), true)
	_chunk_size_input = _add_menu_spin(world_column, "Chunk size (m)", 64.0, 256.0, 16.0, _generator.chunk_size)
	_resolution_input = _add_menu_spin(world_column, "Vertices per chunk side", 16.0, 64.0, 4.0, float(_generator.chunk_resolution), true)
	_world_size_label = Label.new()
	_world_size_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_world_size_label.add_theme_font_size_override("font_size", 17)
	_world_size_label.add_theme_color_override("font_color", Color("ffe38a"))
	world_column.add_child(_world_size_label)

	var vehicle_column: VBoxContainer = VBoxContainer.new()
	vehicle_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vehicle_column.add_theme_constant_override("separation", 4)
	settings_columns.add_child(vehicle_column)
	var vehicle_header: Label = Label.new()
	vehicle_header.text = "VEHICLE HANDLING"
	vehicle_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vehicle_header.add_theme_color_override("font_color", Color("a8f3df"))
	vehicle_column.add_child(vehicle_header)
	var vehicle_fields: HBoxContainer = HBoxContainer.new()
	vehicle_fields.add_theme_constant_override("separation", 18)
	vehicle_column.add_child(vehicle_fields)
	var vehicle_left: VBoxContainer = VBoxContainer.new()
	vehicle_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vehicle_left.add_theme_constant_override("separation", 4)
	vehicle_fields.add_child(vehicle_left)
	var vehicle_right: VBoxContainer = VBoxContainer.new()
	vehicle_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vehicle_right.add_theme_constant_override("separation", 4)
	vehicle_fields.add_child(vehicle_right)
	_handling_preset_input = _add_menu_option(vehicle_left, "Preset", ["SPORT", "CHILL", "CUSTOM"])
	_skin_input = _add_menu_option(vehicle_left, "Car Skin", ["RACING RED", "MIDNIGHT BLUE", "EMERALD GREEN", "SUNBURST YELLOW", "MATTE BLACK", "PEARL WHITE"])
	_mass_input = _add_menu_spin(vehicle_left, "Mass (kg)", 450.0, 3500.0, 25.0, 1150.0)
	_center_of_mass_input = _add_menu_spin(vehicle_left, "Center of mass drop (m)", 0.0, 0.8, 0.02, 0.28)
	_suspension_stiffness_input = _add_menu_spin(vehicle_left, "Suspension stiffness", 12000.0, 80000.0, 1000.0, 36000.0)
	_suspension_damping_input = _add_menu_spin(vehicle_left, "Suspension damping", 1200.0, 12000.0, 200.0, 4800.0)
	_top_speed_input = _add_menu_spin(vehicle_left, "Top speed (km/h)", 80.0, 420.0, 5.0, 270.0)
	_engine_force_input = _add_menu_spin(vehicle_left, "Engine force", 4000.0, 42000.0, 500.0, 22000.0)
	_brake_force_input = _add_menu_spin(vehicle_right, "Brake force", 6000.0, 42000.0, 500.0, 26000.0)
	_base_grip_input = _add_menu_spin(vehicle_right, "Base grip μ", 0.45, 2.0, 0.05, 1.55)
	_sliding_grip_input = _add_menu_spin(vehicle_right, "Sliding grip ratio", 0.2, 0.95, 0.05, 0.78)
	_drift_grip_input = _add_menu_spin(vehicle_right, "Drift rear grip μ", 0.2, 1.4, 0.05, 0.58)
	_grip_recovery_input = _add_menu_spin(vehicle_right, "Grip recovery (s)", 0.15, 3.0, 0.05, 0.90)
	_front_drive_input = _add_menu_spin(vehicle_right, "Front drive share (%)", 0.0, 100.0, 1.0, 38.0)
	_traction_control_input = _add_menu_spin(vehicle_right, "Traction control (%)", 0.0, 100.0, 1.0, 92.0)
	_park_unoccupied_input = _add_menu_check(vehicle_right, "Park when unoccupied", true)
	_handling_preset_input.item_selected.connect(_on_handling_preset_selected)
	for field: SpinBox in [
		_mass_input, _center_of_mass_input, _suspension_stiffness_input,
		_suspension_damping_input, _top_speed_input, _engine_force_input,
		_brake_force_input, _base_grip_input,
		_sliding_grip_input, _drift_grip_input, _grip_recovery_input,
		_front_drive_input, _traction_control_input,
	]:
		field.value_changed.connect(_mark_handling_custom)
	_park_unoccupied_input.toggled.connect(_mark_handling_custom)

	var play_button: Button = Button.new()
	play_button.name = "GenerateAndPlay"
	play_button.text = "GENERATE & PLAY"
	play_button.custom_minimum_size.y = 44.0
	play_button.pressed.connect(_apply_generation_settings)
	content.add_child(play_button)
	var quit_button: Button = Button.new()
	quit_button.text = "QUIT TO DESKTOP"
	quit_button.pressed.connect(_quit_game)
	content.add_child(quit_button)


func _build_pause_menu() -> void:
	var backdrop: ColorRect = ColorRect.new()
	backdrop.name = "PauseMenu"
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.01, 0.02, 0.025, 0.82)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.focus_mode = Control.FOCUS_ALL
	backdrop.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_ENABLED
	backdrop.visible = false
	_hud_root.add_child(backdrop)
	_pause_menu = backdrop

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.add_child(center)
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(360.0, 0.0)
	center.add_child(panel)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color("14242b")
	style.border_color = Color("55c8b3")
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(22.0)
	panel.add_theme_stylebox_override("panel", style)
	var content: VBoxContainer = VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	panel.add_child(content)
	var title: Label = Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	content.add_child(title)
	var resume_button: Button = Button.new()
	resume_button.text = "RESUME"
	resume_button.pressed.connect(_resume_game)
	content.add_child(resume_button)
	var settings_button: Button = Button.new()
	settings_button.text = "WORLD & VEHICLE SETTINGS"
	settings_button.pressed.connect(_show_start_menu)
	content.add_child(settings_button)
	var quit_button: Button = Button.new()
	quit_button.text = "QUIT TO DESKTOP"
	quit_button.pressed.connect(_quit_game)
	content.add_child(quit_button)


func _add_menu_spin(parent: VBoxContainer, label_text: String, minimum: float, maximum: float, step: float, value: float, rounded: bool = false) -> SpinBox:
	var row: HBoxContainer = HBoxContainer.new()
	parent.add_child(row)
	var label: Label = Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var spin_box: SpinBox = SpinBox.new()
	spin_box.min_value = minimum
	spin_box.max_value = maximum
	spin_box.step = step
	spin_box.rounded = rounded
	spin_box.custom_minimum_size.x = 118.0
	spin_box.value = value
	row.add_child(spin_box)
	return spin_box


func _add_menu_option(parent: VBoxContainer, label_text: String, choices: Array[String]) -> OptionButton:
	var row: HBoxContainer = HBoxContainer.new()
	parent.add_child(row)
	var label: Label = Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var option: OptionButton = OptionButton.new()
	option.custom_minimum_size.x = 118.0
	for choice: String in choices:
		option.add_item(choice)
	row.add_child(option)
	return option


func _add_menu_check(parent: VBoxContainer, label_text: String, checked: bool) -> CheckBox:
	var check_box: CheckBox = CheckBox.new()
	check_box.text = label_text
	check_box.button_pressed = checked
	parent.add_child(check_box)
	return check_box


func _on_handling_preset_selected(index: int) -> void:
	if index == 0:
		_set_handling_form(CAR_PRESETS["SPORT"] as Dictionary)
	elif index == 1:
		_set_handling_form(CAR_PRESETS["CHILL"] as Dictionary)


func _set_handling_form(values: Dictionary) -> void:
	_mass_input.set_value_no_signal(float(values["mass_kg"]))
	_center_of_mass_input.set_value_no_signal(float(values["center_of_mass_drop"]))
	_suspension_stiffness_input.set_value_no_signal(float(values["suspension_stiffness"]))
	_suspension_damping_input.set_value_no_signal(float(values["suspension_damping"]))
	_top_speed_input.set_value_no_signal(float(values["top_speed_kph"]))
	_engine_force_input.set_value_no_signal(float(values["engine_force"]))
	_brake_force_input.set_value_no_signal(float(values["brake_force"]))
	_base_grip_input.set_value_no_signal(float(values["base_grip"]))
	_sliding_grip_input.set_value_no_signal(float(values["sliding_grip"]))
	_drift_grip_input.set_value_no_signal(float(values["drift_grip"]))
	_grip_recovery_input.set_value_no_signal(float(values["recovery_seconds"]))
	_front_drive_input.set_value_no_signal(float(values["front_drive_percent"]))
	_traction_control_input.set_value_no_signal(float(values["traction_control_percent"]))


func _mark_handling_custom(_value: Variant) -> void:
	if _handling_preset_input != null:
		_handling_preset_input.select(2)


func _randomize_world_seed() -> void:
	var previous_seed: int = int(_seed_input.value) if _seed_input != null else _generator.world_seed
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	var new_seed: int = rng.randi_range(-999999, 999999)
	while new_seed == previous_seed:
		new_seed = rng.randi_range(-999999, 999999)
	_generator.world_seed = new_seed
	if _seed_input != null:
		_seed_input.set_value_no_signal(float(new_seed))


func _apply_vehicle_settings_to(car: ArcadeCarController) -> void:
	if _handling_preset_input == null:
		return
	car.handling_profile = _handling_preset_input.get_item_text(_handling_preset_input.selected)
	car.vehicle_mass = _mass_input.value
	car.center_of_mass_drop = _center_of_mass_input.value
	car.suspension_stiffness = _suspension_stiffness_input.value
	car.suspension_damping = _suspension_damping_input.value
	car.max_forward_speed = _top_speed_input.value / 3.6
	car.engine_force = _engine_force_input.value
	car.brake_force = _brake_force_input.value
	car.tire_friction = _base_grip_input.value
	car.sliding_grip_ratio = _sliding_grip_input.value
	car.drift_rear_friction = _drift_grip_input.value
	car.grip_recovery_seconds = _grip_recovery_input.value
	car.front_drive_share = _front_drive_input.value / 100.0
	car.traction_control_strength = _traction_control_input.value / 100.0
	car.park_when_unoccupied = _park_unoccupied_input.button_pressed
	if _skin_input != null:
		car.apply_skin(_skin_input.get_item_text(_skin_input.selected))


func _show_start_menu() -> void:
	if _start_menu == null:
		return
	_seed_input.set_value_no_signal(float(_generator.world_seed))
	_chunk_count_input.set_value_no_signal(float(_generator.chunk_count))
	_chunk_size_input.set_value_no_signal(_generator.chunk_size)
	_resolution_input.set_value_no_signal(float(_generator.chunk_resolution))
	_start_menu.visible = true
	_pause_menu.visible = false
	input_blocked = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_set_world_ui_visible(false)


func _show_pause_menu() -> void:
	if not _has_started or _pause_menu == null:
		return
	_start_menu.visible = false
	_pause_menu.visible = true
	input_blocked = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_set_world_ui_visible(false)


func _resume_game() -> void:
	if not _has_started:
		return
	_start_menu.visible = false
	_pause_menu.visible = false
	input_blocked = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _mobile_controls != null and bool(_mobile_controls.call("is_available")) else Input.MOUSE_MODE_CAPTURED
	_set_world_ui_visible(true)


func _apply_generation_settings() -> void:
	_generator.world_seed = int(_seed_input.value)
	_generator.chunk_count = int(_chunk_count_input.value)
	_generator.chunk_size = _chunk_size_input.value
	_generator.chunk_resolution = int(_resolution_input.value)
	_generator.regenerate()
	_has_started = true
	_resume_game()


func _update_world_size_preview() -> void:
	if _world_size_label == null or not _start_menu.visible:
		return
	var chunks_per_side: int = maxi(2, int(_chunk_count_input.value))
	var safe_resolution: int = int(floor(sqrt(float(MAX_TERRAIN_GRID_CELLS)) / float(chunks_per_side)))
	safe_resolution = clampi(floori(float(safe_resolution) / 4.0) * 4, 16, 64)
	_resolution_input.max_value = float(safe_resolution)
	if _resolution_input.value > safe_resolution:
		_resolution_input.value = safe_resolution
	var width: float = _chunk_count_input.value * _chunk_size_input.value
	var total_chunks: int = int(_chunk_count_input.value * _chunk_count_input.value)
	_world_size_label.text = "WORLD: %.0f × %.0f m  •  %d CHUNKS  •  MAX RES %d" % [
		width,
		width,
		total_chunks,
		safe_resolution,
	]


func _quit_game() -> void:
	get_tree().quit()


func _menu_is_open() -> bool:
	return (_start_menu != null and _start_menu.visible) or (_pause_menu != null and _pause_menu.visible)


func _set_world_ui_visible(value: bool) -> void:
	var world_ui: CanvasLayer = get_node_or_null("../WorldUI") as CanvasLayer
	if world_ui != null:
		world_ui.visible = value


func _update_hud() -> void:
	if _status_label == null:
		return
	var gameplay_hud_visible: bool = _has_started and not _menu_is_open()
	_status_label.visible = gameplay_hud_visible
	_prompt_label.visible = gameplay_hud_visible and not is_mobile_controls_active()
	_crosshair.visible = gameplay_hud_visible
	if not gameplay_hud_visible:
		return
	if _driving:
		var drift_text: String = "  •  DRIFT" if _car.drifting else ""
		_status_label.text = "CAR %s  •  %s  •  %03d km/h  •  %d/4 WHEELS  •  SLIP %02d%%%s" % [
			_car.handling_profile, _car.camera_mode_name(), roundi(_car.speed_kph()),
			_car.get_wheel_contact_count(), roundi(_car.get_max_wheel_slip() * 100.0), drift_text,
		]
		_prompt_label.text = "E  exit   •   V  camera   •   Space  handbrake drift   •   R  reset"
	else:
		_status_label.text = "ON FOOT  •  %s%s" % [_player.camera_mode_name(), "  •  MANTLE" if _player.is_mantling else ""]
		if _player.global_position.distance_to(_car.global_position) <= 4.2:
			_prompt_label.text = "E  enter car   •   V  camera   •   Space  jump   •   Shift  sprint"
		else:
			_prompt_label.text = "V  camera   •   Space  jump   •   Shift  sprint   •   R  reset"


func _world_ui_is_open() -> bool:
	var world_ui: Node = get_node_or_null("../WorldUI")
	return world_ui != null and bool(world_ui.get("panel_open"))


func _update_mobile_controls() -> void:
	if _mobile_controls == null:
		return
	_mobile_controls.call("set_driving", _driving)
	_mobile_controls.call("set_gameplay_active", _has_started and not input_blocked)


func _on_touch_look(relative: Vector2) -> void:
	if not input_blocked and not _driving and _player != null:
		_player.apply_touch_look(relative)


func is_mobile_controls_active() -> bool:
	return _mobile_controls != null and bool(_mobile_controls.call("is_available")) and _mobile_controls.visible


func _ensure_input_actions() -> void:
	_add_key_action("move_forward", KEY_W)
	_add_key_action("move_back", KEY_S)
	_add_key_action("move_left", KEY_A)
	_add_key_action("move_right", KEY_D)
	_add_key_action("jump", KEY_SPACE)
	_add_key_action("sprint", KEY_SHIFT)
	_add_key_action("drift", KEY_SPACE)
	_add_key_action("interact", KEY_E)
	_add_key_action("camera_toggle", KEY_V)
	_add_key_action("reset_actor", KEY_R)


func _add_key_action(action_name: StringName, physical_keycode: Key) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	if InputMap.action_get_events(action_name).is_empty():
		var event: InputEventKey = InputEventKey.new()
		event.physical_keycode = physical_keycode
		InputMap.action_add_event(action_name, event)
