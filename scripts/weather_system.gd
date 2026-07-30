class_name WorldWeatherSystem
extends Node3D

const WEATHER_MODES: Array[String] = ["CLEAR", "OVERCAST", "RAIN", "FOG"]

@export_enum("CLEAR", "OVERCAST", "RAIN", "FOG") var default_weather: String = "RAIN"
@export_range(1000, 4000, 100) var rain_amount: int = 1800
@export_range(16.0, 60.0, 1.0) var rain_radius: float = 34.0

var _weather_index: int = 0
var _environment: Environment
var _sky_material: ProceduralSkyMaterial
var _sun: DirectionalLight3D
var _sky_fill: DirectionalLight3D
var _rain: GPUParticles3D
var _weather_label: Label


func _ready() -> void:
	_ensure_input_action()
	_environment = (get_node_or_null("../WorldEnvironment") as WorldEnvironment).environment
	_sun = get_node_or_null("../Sun") as DirectionalLight3D
	_sky_fill = get_node_or_null("../SkyFill") as DirectionalLight3D
	if _environment != null and _environment.sky != null:
		_sky_material = _environment.sky.sky_material as ProceduralSkyMaterial
	_build_rain()
	_build_weather_hud()
	set_weather(default_weather)


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("weather_cycle"):
		_weather_index = (_weather_index + 1) % WEATHER_MODES.size()
		set_weather(WEATHER_MODES[_weather_index])
	if _rain == null or not _rain.emitting:
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera != null:
		_rain.global_position = camera.global_position + Vector3.UP * 18.0


func set_weather(mode: String) -> void:
	var normalized_mode: String = mode.to_upper()
	if not WEATHER_MODES.has(normalized_mode):
		normalized_mode = "CLEAR"
	_weather_index = WEATHER_MODES.find(normalized_mode)
	if _rain != null:
		_rain.emitting = normalized_mode == "RAIN"
	match normalized_mode:
		"OVERCAST":
			_apply_atmosphere(true, 0.004, Color("87959a"), Color("899ba6"), Color("c4c9c7"), 0.72, 0.28)
		"RAIN":
			_apply_atmosphere(true, 0.009, Color("66787f"), Color("657985"), Color("a5afb0"), 0.54, 0.22)
		"FOG":
			_apply_atmosphere(true, 0.035, Color("b9c3c1"), Color("8f9da1"), Color("c9cfcc"), 0.48, 0.18)
		_:
			_apply_atmosphere(false, 0.0009, Color("9eb3b5"), Color("1f405e"), Color("a1bab8"), 1.25, 0.52)
	if _weather_label != null:
		_weather_label.text = "F2  WEATHER: %s" % normalized_mode


func _apply_atmosphere(fog_enabled: bool, fog_density: float, fog_color: Color, sky_top: Color, sky_horizon: Color, sun_energy: float, fill_energy: float) -> void:
	if _environment != null:
		_environment.fog_enabled = fog_enabled
		_environment.fog_density = fog_density
		_environment.fog_light_color = fog_color
		_environment.fog_light_energy = 0.82
		_environment.ambient_light_color = fog_color.lightened(0.08)
		_environment.ambient_light_energy = 0.54 if fog_enabled else 0.62
	if _sky_material != null:
		_sky_material.sky_top_color = sky_top
		_sky_material.sky_horizon_color = sky_horizon
		_sky_material.ground_horizon_color = sky_horizon.darkened(0.26)
	if _sun != null:
		_sun.light_energy = sun_energy
	if _sky_fill != null:
		_sky_fill.light_energy = fill_energy


func _build_rain() -> void:
	_rain = GPUParticles3D.new()
	_rain.name = "Rain"
	_rain.amount = rain_amount
	_rain.lifetime = 1.45
	_rain.randomness = 0.38
	_rain.local_coords = false
	_rain.visibility_aabb = AABB(Vector3(-rain_radius, -42.0, -rain_radius), Vector3(rain_radius * 2.0, 58.0, rain_radius * 2.0))
	_rain.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	add_child(_rain)

	var process_material: ParticleProcessMaterial = ParticleProcessMaterial.new()
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process_material.emission_box_extents = Vector3(rain_radius, 2.0, rain_radius)
	process_material.direction = Vector3(0.08, -1.0, 0.02)
	process_material.spread = 3.5
	process_material.initial_velocity_min = 24.0
	process_material.initial_velocity_max = 34.0
	process_material.gravity = Vector3(0.0, -13.0, 0.0)
	_rain.process_material = process_material

	var streak_mesh: QuadMesh = QuadMesh.new()
	streak_mesh.size = Vector2(0.035, 1.35)
	var rain_material: StandardMaterial3D = StandardMaterial3D.new()
	rain_material.albedo_color = Color(0.68, 0.82, 0.95, 0.72)
	rain_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rain_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rain_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	rain_material.no_depth_test = false
	streak_mesh.material = rain_material
	_rain.draw_pass_1 = streak_mesh


func _build_weather_hud() -> void:
	var canvas: CanvasLayer = CanvasLayer.new()
	canvas.name = "WeatherHUD"
	canvas.layer = 18
	add_child(canvas)
	_weather_label = Label.new()
	_weather_label.name = "WeatherLabel"
	_weather_label.anchor_left = 1.0
	_weather_label.anchor_right = 1.0
	_weather_label.offset_left = -310.0
	_weather_label.offset_top = 22.0
	_weather_label.offset_right = -24.0
	_weather_label.offset_bottom = 58.0
	_weather_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_weather_label.add_theme_font_size_override("font_size", 20)
	_weather_label.add_theme_color_override("font_color", Color("e7eef0"))
	_weather_label.add_theme_color_override("font_shadow_color", Color(0.02, 0.04, 0.05, 0.85))
	_weather_label.add_theme_constant_override("shadow_offset_x", 2)
	_weather_label.add_theme_constant_override("shadow_offset_y", 2)
	canvas.add_child(_weather_label)


func _ensure_input_action() -> void:
	if not InputMap.has_action("weather_cycle"):
		InputMap.add_action("weather_cycle")
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = KEY_F2
	if not InputMap.action_has_event("weather_cycle", event):
		InputMap.action_add_event("weather_cycle", event)
