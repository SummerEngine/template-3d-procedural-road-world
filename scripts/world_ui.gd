class_name ProceduralWorldUI
extends CanvasLayer

var panel_open: bool = false
var _panel: PanelContainer
var _generator: ProceduralWorldGenerator
var _controls: Dictionary = {}
var _status_label: Label
var _generate_button: Button

var _loading_screen: Panel
var _loading_progress_bar: ProgressBar
var _loading_text: Label


func _ready() -> void:
	_generator = get_node("../WorldGenerator") as ProceduralWorldGenerator
	_build_interface()
	_panel.visible = panel_open
	_generator.world_regenerated.connect(_on_world_regenerated)
	_generator.generation_progress.connect(_on_generation_progress)
	if _generator.generate_on_ready:
		_loading_screen.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_update_status({
		"seed": _generator.world_seed,
		"chunks": _generator.chunk_count * _generator.chunk_count,
		"road_points": _generator.get_road_points().size(),
		"roads": _generator.get_road_paths().size(),
		"buildable_plots": _generator.get_buildable_plots().size(),
		"houses": 0,
		"decorations": _generator.decoration_count,
		"world_size": _generator.get_world_size(),
	})


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
		_toggle_panel()
		get_viewport().set_input_as_handled()


func _build_interface() -> void:
	var root: Control = Control.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.focus_mode = Control.FOCUS_ALL
	root.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_ENABLED
	add_child(root)

	_panel = PanelContainer.new()
	_panel.name = "Parameters"
	_panel.position = Vector2(18.0, 18.0)
	_panel.custom_minimum_size = Vector2(360.0, min(680.0, max(320.0, get_viewport().get_visible_rect().size.y - 36.0)))
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(_panel)

	var panel_style: StyleBoxFlat = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.045, 0.065, 0.075, 0.94)
	panel_style.border_color = Color(0.31, 0.55, 0.52, 0.9)
	panel_style.set_border_width_all(1)
	panel_style.corner_radius_top_left = 10
	panel_style.corner_radius_top_right = 10
	panel_style.corner_radius_bottom_left = 10
	panel_style.corner_radius_bottom_right = 10
	panel_style.content_margin_left = 16.0
	panel_style.content_margin_right = 16.0
	panel_style.content_margin_top = 14.0
	panel_style.content_margin_bottom = 14.0
	_panel.add_theme_stylebox_override("panel", panel_style)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel.add_child(scroll)

	var content: VBoxContainer = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	scroll.add_child(content)

	var title: Label = Label.new()
	title.text = "PROCEDURAL ROAD WORLD"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color("9ee8cf"))
	content.add_child(title)

	var subtitle: Label = Label.new()
	subtitle.text = "World generator controls. Movement stays separate."
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_color_override("font_color", Color("aab9b7"))
	content.add_child(subtitle)

	content.add_child(HSeparator.new())
	_add_section_label(content, "SEED / WORLD SIZE")
	_add_spin_control(content, "Seed", "world_seed", _generator.world_seed, -999999.0, 999999.0, 1.0, true)
	_add_spin_control(content, "Chunk count", "chunk_count", _generator.chunk_count, 2.0, 10.0, 1.0, true)
	_add_spin_control(content, "Chunk size", "chunk_size", _generator.chunk_size, 64.0, 256.0, 16.0)
	_add_spin_control(content, "Chunk resolution", "chunk_resolution", _generator.chunk_resolution, 16.0, 64.0, 1.0, true)
	_add_spin_control(content, "Feature scale", "feature_scale", _generator.feature_scale, 0.5, 2.0, 0.05)

	_add_section_label(content, "TERRAIN - HIGH PLACES / HILLS")
	_add_spin_control(content, "Macro height", "macro_height", _generator.macro_height, 0.0, 60.0, 1.0)
	_add_spin_control(content, "Hill height", "hill_height", _generator.hill_height, 0.0, 80.0, 1.0)
	_add_spin_control(content, "Hill density (config)", "hill_density", _generator.hill_density, 0.1, 3.0, 0.1)
	_add_spin_control(content, "Mountain height", "mountain_height", _generator.mountain_height, 20.0, 260.0, 2.0)
	_add_spin_control(content, "Detail height", "detail_height", _generator.detail_height, 0.0, 8.0, 0.1)
	_add_spin_control(content, "Mountain coverage", "mountain_coverage", _generator.mountain_coverage, 0.0, 1.0, 0.05)
	_add_spin_control(content, "Landmark scale", "landmark_height_scale", _generator.landmark_height_scale, 0.6, 2.0, 0.05)
	_add_spin_control(content, "High place amount", "high_place_amount", _generator.high_place_amount, 0.1, 3.0, 0.1)
	_add_spin_control(content, "High place count", "high_place_count", _generator.high_place_count, 0.0, 30.0, 1.0, true)

	_add_section_label(content, "ROADS")
	_add_spin_control(content, "Road width", "road_width", _generator.road_width, 4.0, 24.0, 0.5)
	_add_spin_control(content, "Max road grade", "max_road_grade", _generator.max_road_grade, 0.03, 0.18, 0.005)
	_add_spin_control(content, "Earthwork width", "earthwork_width", _generator.earthwork_width, 8.0, 48.0, 1.0)
	_add_spin_control(content, "Road branches (road count)", "branch_count", _generator.branch_count, 0.0, 4.0, 1.0, true)
	_add_spin_control(content, "Plot width", "buildable_plot_width", _generator.buildable_plot_width, 64.0, 180.0, 2.0)
	_add_spin_control(content, "Plot depth", "buildable_plot_depth", _generator.buildable_plot_depth, 64.0, 180.0, 2.0)
	_add_spin_control(content, "Plot edge blend", "buildable_plot_blend_width", _generator.buildable_plot_blend_width, 8.0, 32.0, 1.0)

	_add_section_label(content, "VEGETATION / TREES")
	_add_spin_control(content, "Tree count", "tree_count", _generator.tree_count, 0.0, 4000.0, 1.0, true)
	_add_spin_control(content, "Rock count", "rock_count", _generator.rock_count, 0.0, 2000.0, 1.0, true)
	_add_spin_control(content, "Vegetation density", "vegetation_density", _generator.vegetation_density, 0.2, 2.5, 0.05)
	_add_spin_control(content, "Tree clump chance", "tree_clump_chance", _generator.tree_clump_chance, 0.0, 1.0, 0.05)
	_add_spin_control(content, "Decorations legacy", "decoration_count", _generator.decoration_count, 0.0, 4000.0, 1.0, true)

	_add_section_label(content, "INTERACTIVE OBJECTS")
	_add_spin_control(content, "Interactive count", "interactive_prop_count", _generator.interactive_prop_count, 0.0, 200.0, 1.0, true)
	_add_spin_control(content, "Variation bias", "interactive_variation_bias", _generator.interactive_variation_bias, 0.0, 1.0, 0.05)
	_add_spin_control(content, "Spawn radius", "interactive_spawn_radius", _generator.interactive_spawn_radius, 1.0, 12.0, 0.5)

	var button_row: HBoxContainer = HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 8)
	content.add_child(button_row)

	_generate_button = Button.new()
	_generate_button.text = "REGENERATE"
	_generate_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_generate_button.pressed.connect(_on_regenerate_pressed)
	button_row.add_child(_generate_button)

	var randomize_button: Button = Button.new()
	randomize_button.text = "RANDOM SEED"
	randomize_button.pressed.connect(_on_random_seed_pressed)
	button_row.add_child(randomize_button)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_color_override("font_color", Color("a9c5bd"))
	content.add_child(_status_label)

	var help: Label = Label.new()
	help.text = "F1  world panel   •   Esc  pause / quit   •   click  capture\nWASD  move/drive   •   V  camera   •   E  enter/exit   •   R  reset"
	help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	help.offset_left = 18.0
	help.offset_top = -62.0
	help.offset_right = 620.0
	help.offset_bottom = -16.0
	help.add_theme_font_size_override("font_size", 15)
	help.add_theme_color_override("font_color", Color(0.92, 0.96, 0.95, 0.95))
	help.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	help.add_theme_constant_override("shadow_offset_x", 2)
	help.add_theme_constant_override("shadow_offset_y", 2)
	help.visible = not OS.has_feature("mobile") and not bool(ProjectSettings.get_setting("debug/mobile/force_touch_controls", false))
	root.add_child(help)

	_loading_screen = Panel.new()
	_loading_screen.name = "LoadingScreen"
	_loading_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loading_screen.visible = false

	var loading_style: StyleBoxFlat = StyleBoxFlat.new()
	loading_style.bg_color = Color(0.04, 0.05, 0.06, 0.95)
	_loading_screen.add_theme_stylebox_override("panel", loading_style)
	root.add_child(_loading_screen)

	var center_container: CenterContainer = CenterContainer.new()
	center_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loading_screen.add_child(center_container)

	var loading_vbox: VBoxContainer = VBoxContainer.new()
	loading_vbox.custom_minimum_size = Vector2(400.0, 0.0)
	loading_vbox.add_theme_constant_override("separation", 20)
	center_container.add_child(loading_vbox)

	var loading_title: Label = Label.new()
	loading_title.text = "GENERATING PROCEDURAL WORLD"
	loading_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading_title.add_theme_font_size_override("font_size", 22)
	loading_title.add_theme_color_override("font_color", Color("9ee8cf"))
	loading_vbox.add_child(loading_title)

	_loading_text = Label.new()
	_loading_text.text = "Initializing world generator..."
	_loading_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_loading_text.add_theme_font_size_override("font_size", 15)
	_loading_text.add_theme_color_override("font_color", Color("aab9b7"))
	loading_vbox.add_child(_loading_text)

	_loading_progress_bar = ProgressBar.new()
	_loading_progress_bar.custom_minimum_size.y = 20.0
	_loading_progress_bar.min_value = 0.0
	_loading_progress_bar.max_value = 100.0
	_loading_progress_bar.value = 0.0

	var pb_bg: StyleBoxFlat = StyleBoxFlat.new()
	pb_bg.bg_color = Color(0.08, 0.1, 0.12, 1.0)
	pb_bg.corner_radius_top_left = 6
	pb_bg.corner_radius_top_right = 6
	pb_bg.corner_radius_bottom_left = 6
	pb_bg.corner_radius_bottom_right = 6
	_loading_progress_bar.add_theme_stylebox_override("background", pb_bg)

	var pb_fg: StyleBoxFlat = StyleBoxFlat.new()
	pb_fg.bg_color = Color(0.31, 0.55, 0.52, 1.0)
	pb_fg.corner_radius_top_left = 6
	pb_fg.corner_radius_top_right = 6
	pb_fg.corner_radius_bottom_left = 6
	pb_fg.corner_radius_bottom_right = 6
	_loading_progress_bar.add_theme_stylebox_override("fill", pb_fg)

	loading_vbox.add_child(_loading_progress_bar)


func _add_section_label(parent: VBoxContainer, text: String) -> void:
	parent.add_child(HSeparator.new())
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color("9ee8cf"))
	parent.add_child(lbl)


func _add_spin_control(parent: VBoxContainer, label_text: String, property_name: StringName, value: float, minimum: float, maximum: float, step: float, rounded: bool = false) -> void:
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
	spin_box.allow_greater = false
	spin_box.allow_lesser = false
	spin_box.rounded = rounded
	spin_box.custom_minimum_size.x = 112.0
	row.add_child(spin_box)
	spin_box.set_value_no_signal(value)
	_controls[property_name] = spin_box


func _toggle_panel() -> void:
	panel_open = not panel_open
	_panel.visible = panel_open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if panel_open else Input.MOUSE_MODE_CAPTURED


func _on_regenerate_pressed() -> void:
	_generate_button.disabled = true
	_generate_button.text = "GENERATING..."

	if _loading_screen:
		_loading_screen.visible = true
		_loading_text.text = "Starting generation..."
		_loading_progress_bar.value = 0.0

	# Yield a frame to let the loading screen draw
	await get_tree().process_frame

	for property_name: StringName in _controls:
		var spin_box: SpinBox = _controls[property_name] as SpinBox
		_generator.set(property_name, spin_box.value)

	# Explicit int casts for integer properties
	_generator.world_seed = int((_controls["world_seed"] as SpinBox).value)
	_generator.chunk_count = int((_controls["chunk_count"] as SpinBox).value)
	_generator.chunk_size = (_controls["chunk_size"] as SpinBox).value
	_generator.chunk_resolution = int((_controls["chunk_resolution"] as SpinBox).value)
	_generator.branch_count = int((_controls["branch_count"] as SpinBox).value)
	_generator.decoration_count = int((_controls["decoration_count"] as SpinBox).value)
	if _controls.has("tree_count"):
		_generator.tree_count = int((_controls["tree_count"] as SpinBox).value)
	if _controls.has("rock_count"):
		_generator.rock_count = int((_controls["rock_count"] as SpinBox).value)
	if _controls.has("high_place_count"):
		_generator.high_place_count = int((_controls["high_place_count"] as SpinBox).value)
	if _controls.has("interactive_prop_count"):
		_generator.interactive_prop_count = int((_controls["interactive_prop_count"] as SpinBox).value)

	await _generator.regenerate()

	_generate_button.disabled = false
	_generate_button.text = "REGENERATE"


func _on_random_seed_pressed() -> void:
	var seed_control: SpinBox = _controls["world_seed"] as SpinBox
	seed_control.value = randi_range(-999999, 999999)
	await _on_regenerate_pressed()


func _on_world_regenerated(stats: Dictionary) -> void:
	_update_status(stats)
	if _loading_screen:
		_loading_screen.visible = false


func _on_generation_progress(status: String, percent: float) -> void:
	if _loading_screen:
		_loading_screen.visible = true
	if _loading_text:
		_loading_text.text = status
	if _loading_progress_bar:
		_loading_progress_bar.value = percent


func _update_status(stats: Dictionary) -> void:
	if _status_label == null:
		return
	_status_label.text = "Seed %s  •  %.0f m world  •  %s chunks\n%s roads (branches %s)  •  %s plots / %s houses\n%s decor (trees %s / rocks %s)  •  %s interactive props\n%s high places  •  %s road samples  •  max grade %.1f%%" % [
		stats.get("seed", _generator.world_seed),
		float(stats.get("world_size", _generator.get_world_size())),
		stats.get("chunks", 0),
		stats.get("roads", 0),
		_generator.branch_count,
		stats.get("buildable_plots", 0),
		stats.get("houses", 0),
		stats.get("decorations", 0),
		stats.get("trees", _generator.tree_count),
		stats.get("rocks", _generator.rock_count),
		stats.get("interactive_props", 0),
		stats.get("high_places", _generator.high_place_count),
		stats.get("road_points", 0),
		_generator.get_max_actual_road_grade() * 100.0,
	]
