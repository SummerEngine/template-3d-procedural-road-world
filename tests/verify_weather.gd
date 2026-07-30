extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed_scene: PackedScene = load("res://main.tscn") as PackedScene
	var world: Node = packed_scene.instantiate()
	root.add_child(world)
	await process_frame
	await process_frame

	var weather: Node = world.get_node_or_null("WeatherSystem")
	_check(weather != null, "main world contains a weather system")
	if weather != null:
		var rain: GPUParticles3D = weather.get_node_or_null("Rain") as GPUParticles3D
		var environment: Environment = (world.get_node("WorldEnvironment") as WorldEnvironment).environment
		weather.call("set_weather", "RAIN")
		_check(rain != null and rain.emitting and rain.amount >= 1000, "rain mode emits a dense camera-following particle field")
		_check(environment.fog_enabled and environment.fog_density > 0.005, "rain mode adds light atmospheric fog")
		weather.call("set_weather", "FOG")
		_check(rain != null and not rain.emitting, "fog mode disables rain particles")
		_check(environment.fog_density >= 0.025, "fog mode has clearly denser visibility falloff")
		weather.call("set_weather", "CLEAR")
		_check(not environment.fog_enabled and not rain.emitting, "clear mode removes precipitation and fog")
		_check(InputMap.has_action("weather_cycle"), "F2 weather cycling action is registered")

	paused = false
	world.queue_free()
	await process_frame
	if _failures.is_empty():
		print("VERIFY_WEATHER PASS")
		quit(0)
	else:
		for failure: String in _failures:
			push_error("VERIFY_WEATHER FAIL: " + failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition and not _failures.has(message):
		_failures.append(message)
