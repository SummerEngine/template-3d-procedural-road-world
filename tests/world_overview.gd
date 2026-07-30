extends Node3D

@onready var generator: ProceduralWorldGenerator = $WorldGenerator
@onready var camera: Camera3D = $Camera3D
@onready var movement_lab: MovementLab = $MovementLab
@onready var weather_system: Node = $WeatherSystem

var _view_index: int = 1
var _view_elapsed: float = 0.0
var _overview_ready: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	generator.regenerate()


func _process(delta: float) -> void:
	if not _overview_ready:
		if not movement_lab.has_node("MovementHUD/Root/StartMenu"):
			return
		movement_lab.call("_apply_generation_settings")
		var hud: CanvasLayer = movement_lab.get_node_or_null("MovementHUD") as CanvasLayer
		if hud != null:
			hud.visible = false
		get_tree().paused = false
		_overview_ready = true
		_apply_view()
		return
	_view_elapsed += delta
	if _view_elapsed < 2.5:
		return
	_view_elapsed = 0.0
	_view_index = (_view_index + 1) % 5
	_apply_view()


func _apply_view() -> void:
	var paths: Array[PackedVector3Array] = generator.get_road_paths()
	var plots: Array[Dictionary] = generator.get_buildable_plots()
	match _view_index:
		1:
			weather_system.set_weather("RAIN")
		2:
			weather_system.set_weather("CLEAR")
		3:
			weather_system.set_weather("FOG")
		4:
			weather_system.set_weather("CLEAR")
		_:
			weather_system.set_weather("OVERCAST")
	if _view_index >= 3 and movement_lab.has_node("ParkourLocations/Parkour_0"):
		var location: Node3D = movement_lab.get_node("ParkourLocations/Parkour_0") as Node3D
		var focus: Vector3 = location.global_position
		focus.y = generator.get_rendered_terrain_height(focus.x, focus.z) + 1.8
		camera.global_position = focus + location.global_transform.basis * Vector3(24.0, 17.0, 26.0)
		camera.look_at(focus + Vector3.UP * 1.2, Vector3.UP)
	elif _view_index == 1 and paths.size() > 1:
		var junction: Vector3 = paths[1][0]
		camera.global_position = junction + Vector3(38.0, 42.0, 52.0)
		camera.look_at(junction, Vector3.UP)
	elif _view_index == 2 and not plots.is_empty():
		var center: Vector2 = plots[0]["center"] as Vector2
		var focus: Vector3 = Vector3(center.x, float(plots[0]["height"]) + 1.5, center.y)
		var forward: Vector2 = plots[0]["forward"] as Vector2
		var right: Vector2 = plots[0]["right"] as Vector2
		camera.global_position = focus + Vector3(forward.x * 34.0 + right.x * 24.0, 24.0, forward.y * 34.0 + right.y * 24.0)
		camera.look_at(focus, Vector3.UP)
	else:
		var focus: Vector3 = Vector3.ZERO
		if not plots.is_empty():
			var center: Vector2 = plots[0]["center"] as Vector2
			focus = Vector3(center.x * 0.25, float(plots[0]["height"]), center.y * 0.25)
		camera.global_position = focus + Vector3(300.0, 360.0, 350.0)
		camera.look_at(focus, Vector3.UP)
	camera.current = true
