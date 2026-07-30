class_name ProceduralWorldGenerator
extends Node3D

signal world_regenerated(stats: Dictionary)
signal generation_progress(status: String, percent: float)

@export_group("World")
@export var generate_on_ready: bool = true
@export var world_seed: int = 1847
@export_range(2, 10, 1) var chunk_count: int = 6
@export_range(64.0, 256.0, 16.0) var chunk_size: float = 192.0
@export_range(16, 64, 1) var chunk_resolution: int = 32
@export_range(0.5, 2.0, 0.05) var feature_scale: float = 1.0

@export_group("Terrain")
@export_range(0.0, 60.0, 1.0) var macro_height: float = 12.0
@export_range(0.0, 80.0, 1.0) var hill_height: float = 16.0
@export_range(20.0, 260.0, 2.0) var mountain_height: float = 96.0
@export_range(0.0, 8.0, 0.1) var detail_height: float = 1.0
@export_range(0.0, 1.0, 0.05) var mountain_coverage: float = 0.4
@export_range(0.6, 2.0, 0.05) var landmark_height_scale: float = 1.28

@export_group("Road")
@export_range(4.0, 24.0, 0.5) var road_width: float = 10.0
@export_range(0.01, 0.5, 0.01) var road_surface_lift: float = 0.01
@export_range(0.03, 0.18, 0.005) var max_road_grade: float = 0.09
@export_range(8.0, 48.0, 1.0) var earthwork_width: float = 24.0
@export_range(0, 4, 1) var branch_count: int = 4
@export_range(64.0, 180.0, 2.0) var buildable_plot_width: float = 112.0
@export_range(64.0, 180.0, 2.0) var buildable_plot_depth: float = 112.0
@export_range(8.0, 32.0, 1.0) var buildable_plot_blend_width: float = 20.0

@export_group("Parkour")
@export_range(20.0, 48.0, 1.0) var parkour_plot_width: float = 28.0
@export_range(18.0, 40.0, 1.0) var parkour_plot_depth: float = 24.0
@export_range(6.0, 20.0, 1.0) var parkour_plot_blend_width: float = 10.0
@export_range(0.08, 0.4, 0.01) var parkour_foundation_lift: float = 0.18

@export_group("Decoration")
@export_range(0, 4000, 1) var decoration_count: int = 1400
@export_range(0.05, 0.35, 0.01) var decoration_ground_embed: float = 0.16

@export_group("Vegetation Config")
@export_range(0, 4000, 1) var tree_count: int = 900
@export_range(0, 2000, 1) var rock_count: int = 400
@export_range(0.2, 2.5, 0.05) var vegetation_density: float = 1.0
@export_range(0.0, 1.0, 0.05) var tree_clump_chance: float = 0.25

@export_group("High Places Config")
@export_range(0.1, 3.0, 0.1) var hill_density: float = 1.0
@export_range(0.1, 3.0, 0.05) var high_place_amount: float = 1.0
@export_range(0, 30, 1) var high_place_count: int = 6

@export_group("Interactive Props")
@export_range(0, 200, 1) var interactive_prop_count: int = 28
@export_range(0.0, 1.0, 0.05) var interactive_variation_bias: float = 0.5
@export_range(1.0, 12.0, 0.5) var interactive_spawn_radius: float = 6.5

const InteractiveObstacleScene: Script = preload("res://scripts/interactive_obstacle.gd")

var _macro_noise: FastNoiseLite = FastNoiseLite.new()
var _mountain_mask_noise: FastNoiseLite = FastNoiseLite.new()
var _mountain_noise: FastNoiseLite = FastNoiseLite.new()
var _hill_noise: FastNoiseLite = FastNoiseLite.new()
var _detail_noise: FastNoiseLite = FastNoiseLite.new()
var _road_points: PackedVector3Array = PackedVector3Array()
var _road_paths: Array[PackedVector3Array] = []
var _buildable_plots: Array[Dictionary] = []
var _parkour_plots: Array[Dictionary] = []
var _landmark_peak: Vector2 = Vector2.ZERO
var _decoration_positions: PackedVector3Array = PackedVector3Array()
var _interactive_positions: PackedVector3Array = PackedVector3Array()
var _terrain_root: Node3D
var _road_root: Node3D
var _decoration_root: Node3D
var _interactive_root: Node3D
var _terrain_material: StandardMaterial3D
var _generation_serial: int = 0
var _extra_peaks: Array[Vector2] = []
var _extra_peak_strengths: Array[float] = []


func _ready() -> void:
	if generate_on_ready:
		await regenerate()


func regenerate() -> void:
	_generation_serial += 1
	generation_progress.emit("Clearing old world...", 0.0)
	await get_tree().process_frame
	_clear_generated_children()

	generation_progress.emit("Initializing...", 5.0)
	await get_tree().process_frame
	_create_containers()
	_configure_noise()

	generation_progress.emit("Planning roads and plots...", 10.0)
	await get_tree().process_frame
	_plan_road()

	generation_progress.emit("Building terrain...", 20.0)
	await get_tree().process_frame
	await _build_terrain_chunks()

	generation_progress.emit("Building roads...", 60.0)
	await get_tree().process_frame
	await _build_road()

	generation_progress.emit("Placing environment decorations...", 85.0)
	await get_tree().process_frame
	_build_decorations()

	generation_progress.emit("Placing interactive props...", 92.0)
	await get_tree().process_frame
	_build_interactive_props()

	generation_progress.emit("World generation complete!", 100.0)
	await get_tree().process_frame

	var stats: Dictionary = {
		"generation": _generation_serial,
		"seed": world_seed,
		"chunks": chunk_count * chunk_count,
		"road_points": _count_road_points(),
		"roads": _road_paths.size(),
		"buildable_plots": _buildable_plots.size(),
		"parkour_plots": _parkour_plots.size(),
		"houses": _count_houses(),
		"decorations": _count_decoration_instances(),
		"trees": tree_count,
		"rocks": rock_count,
		"high_places": high_place_count,
		"interactive_props": _count_interactive_props(),
		"world_size": get_world_size(),
	}
	world_regenerated.emit(stats)
	print("WORLD_GENERATED ", stats)


func get_world_size() -> float:
	return chunk_count * chunk_size


func get_road_points() -> PackedVector3Array:
	return _road_points.duplicate()


func get_road_paths() -> Array[PackedVector3Array]:
	var result: Array[PackedVector3Array] = []
	for path: PackedVector3Array in _road_paths:
		result.append(path.duplicate())
	return result


func get_buildable_plots() -> Array[Dictionary]:
	return _buildable_plots.duplicate(true)


func get_parkour_plots() -> Array[Dictionary]:
	return _parkour_plots.duplicate(true)


func get_decoration_positions() -> PackedVector3Array:
	return _decoration_positions.duplicate()


func get_mountain_landmark_position() -> Vector2:
	return _landmark_peak


func get_road_flattened_half_width() -> float:
	var vertex_step: float = chunk_size / float(max(chunk_resolution, 1))
	var mesh_clearance: float = vertex_step * sqrt(2.0) + 0.5
	return road_width * 0.5 + max(2.0, mesh_clearance)


func get_road_decoration_clearance() -> float:
	return get_road_flattened_half_width() + max(earthwork_width, 3.0) + 3.0


func get_max_actual_road_grade() -> float:
	var result: float = 0.0
	for path: PackedVector3Array in _road_paths:
		for index: int in range(1, path.size()):
			var previous: Vector3 = path[index - 1]
			var current: Vector3 = path[index]
			var horizontal_distance: float = Vector2(current.x - previous.x, current.z - previous.z).length()
			if horizontal_distance > 0.001:
				result = max(result, abs(current.y - previous.y) / horizontal_distance)
	return result


func get_height_at(world_x: float, world_z: float, include_road: bool = true) -> float:
	var base_height: float = _get_base_height(world_x, world_z)
	if not include_road:
		return base_height
	var shaped_height: float = base_height
	if not _road_paths.is_empty():
		var road_sample: Vector2 = _nearest_road_sample(world_x, world_z)
		var distance_to_center: float = road_sample.x
		var road_height: float = road_sample.y
		var shoulder_edge: float = get_road_flattened_half_width()
		var outer_edge: float = shoulder_edge + max(earthwork_width, 3.0)
		if distance_to_center <= shoulder_edge:
			shaped_height = road_height
		elif distance_to_center < outer_edge:
			var blend: float = smoothstep(shoulder_edge, outer_edge, distance_to_center)
			shaped_height = lerp(road_height, base_height, blend)
	return _apply_flattening_plots(world_x, world_z, shaped_height)


func get_terrain_normal(world_x: float, world_z: float) -> Vector3:
	var sample_step: float = max(1.0, chunk_size / float(chunk_resolution))
	var left_height: float = get_height_at(world_x - sample_step, world_z)
	var right_height: float = get_height_at(world_x + sample_step, world_z)
	var back_height: float = get_height_at(world_x, world_z - sample_step)
	var front_height: float = get_height_at(world_x, world_z + sample_step)
	return Vector3(left_height - right_height, sample_step * 2.0, back_height - front_height).normalized()


func get_rendered_terrain_height(world_x: float, world_z: float) -> float:
	var world_min: float = -get_world_size() * 0.5
	var vertex_step: float = chunk_size / float(max(chunk_resolution, 1))
	var grid_side: int = chunk_count * chunk_resolution
	var local_x: float = clamp((world_x - world_min) / vertex_step, 0.0, float(grid_side))
	var local_z: float = clamp((world_z - world_min) / vertex_step, 0.0, float(grid_side))
	var cell_x: int = clampi(int(floor(local_x)), 0, grid_side - 1)
	var cell_z: int = clampi(int(floor(local_z)), 0, grid_side - 1)
	var fraction_x: float = local_x - float(cell_x)
	var fraction_z: float = local_z - float(cell_z)
	var x0: float = world_min + float(cell_x) * vertex_step
	var z0: float = world_min + float(cell_z) * vertex_step
	var top_left: float = get_height_at(x0, z0)
	var top_right: float = get_height_at(x0 + vertex_step, z0)
	var bottom_left: float = get_height_at(x0, z0 + vertex_step)
	var bottom_right: float = get_height_at(x0 + vertex_step, z0 + vertex_step)
	if fraction_x + fraction_z <= 1.0:
		return top_left + fraction_x * (top_right - top_left) + fraction_z * (bottom_left - top_left)
	return top_right * (1.0 - fraction_z) + bottom_left * (1.0 - fraction_x) + bottom_right * (fraction_x + fraction_z - 1.0)


func distance_to_road(world_x: float, world_z: float) -> float:
	if _road_paths.is_empty():
		return INF
	return _nearest_road_sample(world_x, world_z).x


func distance_to_buildable_plot(world_x: float, world_z: float) -> float:
	return _distance_to_plots(world_x, world_z, _buildable_plots)


func distance_to_parkour_plot(world_x: float, world_z: float) -> float:
	return _distance_to_plots(world_x, world_z, _parkour_plots)


func _distance_to_plots(world_x: float, world_z: float, plots: Array[Dictionary]) -> float:
	var query: Vector2 = Vector2(world_x, world_z)
	var best_distance: float = INF
	for plot: Dictionary in plots:
		var center: Vector2 = plot["center"] as Vector2
		var forward: Vector2 = plot["forward"] as Vector2
		var right: Vector2 = plot["right"] as Vector2
		var half_extents: Vector2 = plot["half_extents"] as Vector2
		var delta: Vector2 = query - center
		var local_position: Vector2 = Vector2(delta.dot(right), delta.dot(forward))
		var edge_delta: Vector2 = Vector2(abs(local_position.x), abs(local_position.y)) - half_extents
		var outside_distance: float = Vector2(max(edge_delta.x, 0.0), max(edge_delta.y, 0.0)).length()
		var signed_distance: float = outside_distance + min(max(edge_delta.x, edge_delta.y), 0.0)
		best_distance = min(best_distance, signed_distance)
	return best_distance


func _clear_generated_children() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()


func _create_containers() -> void:
	_terrain_root = Node3D.new()
	_terrain_root.name = "TerrainChunks"
	add_child(_terrain_root)

	_road_root = Node3D.new()
	_road_root.name = "Road"
	add_child(_road_root)

	_decoration_root = Node3D.new()
	_decoration_root.name = "Decorations"
	add_child(_decoration_root)

	_interactive_root = Node3D.new()
	_interactive_root.name = "InteractiveProps"
	add_child(_interactive_root)

	_interactive_positions.clear()
	_extra_peaks.clear()
	_extra_peak_strengths.clear()


func _configure_noise() -> void:
	_configure_fbm(_macro_noise, world_seed + 11, 0.0018 / feature_scale, 4, 0.52)
	_configure_fbm(_mountain_mask_noise, world_seed + 29, 0.0022 / feature_scale, 3, 0.55)
	_configure_fbm(_hill_noise, world_seed + 47, 0.0075 / feature_scale, 4, 0.52)
	_configure_fbm(_detail_noise, world_seed + 71, 0.035 / feature_scale, 3, 0.48)
	_landmark_peak = Vector2(get_world_size() * 0.38, get_world_size() * 0.24)

	_mountain_noise.seed = world_seed + 97
	_mountain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_mountain_noise.frequency = 0.0028 / feature_scale
	_mountain_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_mountain_noise.fractal_octaves = 4
	_mountain_noise.fractal_gain = 0.48
	_mountain_noise.fractal_lacunarity = 2.0

	# Extra high places / hills configurable peaks
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed * 1337 + 19
	var world_half: float = get_world_size() * 0.5 - 30.0
	_extra_peaks.clear()
	_extra_peak_strengths.clear()
	var count: int = clampi(high_place_count, 0, 30)
	for i in range(count):
		var px: float = rng.randf_range(-world_half, world_half)
		var pz: float = rng.randf_range(-world_half, world_half)
		_extra_peaks.append(Vector2(px, pz))
		_extra_peak_strengths.append(rng.randf_range(0.8, 1.6))


func _configure_fbm(noise: FastNoiseLite, seed_value: int, frequency_value: float, octaves: int, gain: float) -> void:
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency_value
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves
	noise.fractal_gain = gain
	noise.fractal_lacunarity = 2.0


func _get_base_height(world_x: float, world_z: float) -> float:
	var macro: float = _macro_noise.get_noise_2d(world_x, world_z) * macro_height
	var raw_mask: float = (_mountain_mask_noise.get_noise_2d(world_x, world_z) + 1.0) * 0.5
	var belt: float = 0.5 + 0.5 * sin((world_x + world_seed * 0.73) * 0.006 / feature_scale + _macro_noise.get_noise_2d(world_x, world_z) * 2.2)
	var mountain_threshold: float = lerp(0.78, 0.46, mountain_coverage)
	var mountain_mask: float = smoothstep(mountain_threshold, mountain_threshold + 0.22, raw_mask * 0.72 + belt * 0.28)
	var hills: float = _hill_noise.get_noise_2d(world_x, world_z) * hill_height * hill_density * lerp(0.72, 0.28, mountain_mask)
	var ridge: float = clamp((_mountain_noise.get_noise_2d(world_x, world_z) + 1.0) * 0.5, 0.0, 1.0)
	var mountains: float = pow(ridge, 1.55) * mountain_height * mountain_mask * 0.52 * high_place_amount
	var detail: float = _detail_noise.get_noise_2d(world_x, world_z) * detail_height * lerp(0.35, 1.0, mountain_mask)
	var landmark_radius: float = get_world_size() * 0.19
	var landmark_distance: float = Vector2(world_x, world_z).distance_to(_landmark_peak)
	var landmark_mask: float = pow(max(0.0, 1.0 - landmark_distance / max(landmark_radius, 1.0)), 2.25)
	var landmark_ridges: float = lerp(0.82, 1.08, ridge)
	var landmark: float = mountain_height * landmark_height_scale * landmark_mask * landmark_ridges * high_place_amount

	# Configurable extra peaks (high places / hills)
	var extra_height: float = 0.0
	for i in range(_extra_peaks.size()):
		var peak: Vector2 = _extra_peaks[i]
		var dist: float = Vector2(world_x, world_z).distance_to(peak)
		var radius: float = get_world_size() * 0.08 + 24.0
		if dist < radius:
			var falloff: float = pow(max(0.0, 1.0 - dist / radius), 2.2)
			var strength: float = _extra_peak_strengths[i] if i < _extra_peak_strengths.size() else 1.0
			extra_height += mountain_height * 0.35 * falloff * strength * high_place_amount
			# secondary hill lump around it
			extra_height += hill_height * 0.45 * falloff * hill_density

	return macro + hills + mountains + landmark + detail + extra_height


func _plan_road() -> void:
	_road_points.clear()
	_road_paths.clear()
	_buildable_plots.clear()
	_parkour_plots.clear()
	var world_size: float = get_world_size()
	var margin: float = max(28.0, chunk_size * 0.18)
	var z_start: float = -world_size * 0.5 + margin
	var z_end: float = world_size * 0.5 - margin
	var row_spacing: float = 12.0
	var row_count: int = int(floor((z_end - z_start) / row_spacing)) + 1
	var lane_spacing: float = 12.0
	var road_half_range: float = world_size * 0.5 - margin - earthwork_width
	var lane_count: int = max(9, int(floor((road_half_range * 2.0) / lane_spacing)) + 1)
	var lane_start: float = -lane_spacing * float(lane_count - 1) * 0.5
	var infinity: float = 1.0e30
	var previous_costs: PackedFloat64Array = PackedFloat64Array()
	previous_costs.resize(lane_count)
	var parents: Array[PackedInt32Array] = []

	for lane: int in range(lane_count):
		var x: float = lane_start + lane * lane_spacing
		var height: float = _get_base_height(x, z_start)
		previous_costs[lane] = abs(x) * 0.08 + max(height - 55.0, 0.0) * 0.3

	for row: int in range(1, row_count):
		var z: float = z_start + row * row_spacing
		var previous_z: float = z - row_spacing
		var current_costs: PackedFloat64Array = PackedFloat64Array()
		current_costs.resize(lane_count)
		var parent_row: PackedInt32Array = PackedInt32Array()
		parent_row.resize(lane_count)

		for lane: int in range(lane_count):
			var x: float = lane_start + lane * lane_spacing
			var height: float = _get_base_height(x, z)
			var best_cost: float = infinity
			var best_parent: int = lane

			for previous_lane: int in range(max(0, lane - 2), min(lane_count, lane + 3)):
				var previous_x: float = lane_start + previous_lane * lane_spacing
				var previous_height: float = _get_base_height(previous_x, previous_z)
				var segment_length: float = Vector2(x - previous_x, row_spacing).length()
				var terrain_grade: float = abs(height - previous_height) / max(segment_length, 0.001)
				var lateral_change: float = abs(x - previous_x)
				var grade_cost: float = terrain_grade * terrain_grade * 220.0
				if terrain_grade > max_road_grade * 1.6:
					grade_cost += pow((terrain_grade - max_road_grade * 1.6) * 80.0, 2.0)
				var elevation_cost: float = max(height - 48.0, 0.0) * 0.22
				var direction_cost: float = lateral_change * 0.32
				var center_cost: float = abs(x) * 0.012
				var candidate_cost: float = previous_costs[previous_lane] + segment_length + grade_cost + elevation_cost + direction_cost + center_cost
				if candidate_cost < best_cost:
					best_cost = candidate_cost
					best_parent = previous_lane

			current_costs[lane] = best_cost
			parent_row[lane] = best_parent

		parents.append(parent_row)
		previous_costs = current_costs

	var best_last_lane: int = 0
	var best_last_cost: float = infinity
	for lane: int in range(lane_count):
		if previous_costs[lane] < best_last_cost:
			best_last_cost = previous_costs[lane]
			best_last_lane = lane

	var lane_path: PackedInt32Array = PackedInt32Array()
	lane_path.resize(row_count)
	lane_path[row_count - 1] = best_last_lane
	for row: int in range(row_count - 2, -1, -1):
		lane_path[row] = parents[row][lane_path[row + 1]]

	var x_values: PackedFloat64Array = PackedFloat64Array()
	x_values.resize(row_count)
	for row: int in range(row_count):
		x_values[row] = lane_start + lane_path[row] * lane_spacing

	for pass_index: int in range(12):
		var smoothed: PackedFloat64Array = x_values.duplicate()
		for row: int in range(1, row_count - 1):
			smoothed[row] = lerp(x_values[row], (x_values[row - 1] + x_values[row + 1]) * 0.5, 0.58)
		x_values = smoothed

	var profile: PackedFloat64Array = PackedFloat64Array()
	profile.resize(row_count)
	for row: int in range(row_count):
		var weighted_height: float = 0.0
		var weight_total: float = 0.0
		for offset: int in range(-3, 4):
			var sample_row: int = clampi(row + offset, 0, row_count - 1)
			var sample_z: float = z_start + sample_row * row_spacing
			var weight: float = 4.0 - abs(offset)
			weighted_height += _get_base_height(x_values[sample_row], sample_z) * weight
			weight_total += weight
		profile[row] = weighted_height / weight_total

	for pass_index: int in range(28):
		var smoothed_profile: PackedFloat64Array = profile.duplicate()
		for row: int in range(1, row_count - 1):
			smoothed_profile[row] = lerp(profile[row], (profile[row - 1] + profile[row + 1]) * 0.5, 0.62)
		profile = smoothed_profile
		_limit_profile_grade(profile, x_values, row_spacing)

	for row: int in range(row_count):
		_road_points.append(Vector3(x_values[row], profile[row], z_start + row * row_spacing))
	_road_paths.append(_road_points)
	_plan_branches()
	_plan_parkour_plots()


func _plan_parkour_plots() -> void:
	if _road_points.size() < 8:
		return
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = world_seed * 104729 + 313
	var fractions: Array[float] = [0.12, 0.34, 0.60, 0.82]
	for plot_index: int in range(fractions.size()):
		var target_index: int = int(round(fractions[plot_index] * float(_road_points.size() - 1)))
		target_index = clampi(target_index + rng.randi_range(-2, 2), 3, _road_points.size() - 4)
		var previous: Vector3 = _road_points[target_index - 1]
		var current: Vector3 = _road_points[target_index]
		var next: Vector3 = _road_points[target_index + 1]
		var forward: Vector2 = Vector2(next.x - previous.x, next.z - previous.z).normalized()
		var right: Vector2 = Vector2(forward.y, -forward.x)
		var half_extents: Vector2 = Vector2(parkour_plot_width, parkour_plot_depth) * 0.5
		var mesh_margin: float = chunk_size / float(max(chunk_resolution, 1)) * sqrt(2.0) + 0.5
		var earthwork_outer_edge: float = get_road_flattened_half_width() + max(earthwork_width, 3.0)
		var roadside_offset: float = earthwork_outer_edge + half_extents.length() + mesh_margin + parkour_plot_blend_width + 3.0
		var preferred_side: float = -1.0 if rng.randi_range(0, 1) == 0 else 1.0
		var center: Vector2 = Vector2(current.x, current.z) + right * preferred_side * roadside_offset
		var best_clearance: float = distance_to_road(center.x, center.y)
		var alternate_center: Vector2 = Vector2(current.x, current.z) - right * preferred_side * roadside_offset
		var alternate_clearance: float = distance_to_road(alternate_center.x, alternate_center.y)
		if alternate_clearance > best_clearance:
			center = alternate_center
		_parkour_plots.append({
			"name": "ParkourPlot_%d" % plot_index,
			"center": center,
			"height": current.y,
			"forward": forward,
			"right": right,
			"half_extents": half_extents,
			"terrain_half_extents": half_extents + Vector2.ONE * mesh_margin,
			"blend_width": parkour_plot_blend_width,
			"variant": (plot_index + rng.randi_range(0, 2)) % 3,
		})


func _plan_branches() -> void:
	if branch_count <= 0 or _road_points.size() < 12:
		return
	var road_fractions: Array[float] = [0.24, 0.61, 0.48, 0.86]
	var world_half: float = get_world_size() * 0.5
	var boundary_margin: float = max(32.0, chunk_size * 0.2)
	var branch_length: float = min(get_world_size() * 0.27, world_half - boundary_margin)
	var point_spacing: float = 10.0
	var point_count: int = max(8, int(floor(branch_length / point_spacing)) + 1)

	for branch_index: int in range(min(branch_count, road_fractions.size())):
		var target_index: int = int(round(road_fractions[branch_index] * float(_road_points.size() - 1)))
		var junction_index: int = _find_flattest_main_road_index(target_index, 5)
		var junction: Vector3 = _road_points[junction_index]
		var previous: Vector3 = _road_points[max(0, junction_index - 1)]
		var next: Vector3 = _road_points[min(_road_points.size() - 1, junction_index + 1)]
		var main_forward: Vector2 = Vector2(next.x - previous.x, next.z - previous.z).normalized()
		var main_right: Vector2 = Vector2(main_forward.y, -main_forward.x)
		var direction_sign: float = -1.0 if branch_index % 2 == 0 else 1.0
		var branch_forward: Vector2 = main_right * direction_sign
		var positions: PackedVector2Array = PackedVector2Array()
		var height_profile: PackedFloat64Array = PackedFloat64Array()
		height_profile.resize(point_count)

		for point_index: int in range(point_count):
			var progress: float = float(point_index) / float(point_count - 1)
			var distance: float = progress * branch_length
			var curve_weight: float = pow(sin(progress * PI), 2.0)
			var curve_offset: float = curve_weight * get_world_size() * 0.035 * (1.0 if branch_index % 2 == 0 else -1.0)
			var position_2d: Vector2 = Vector2(junction.x, junction.z) + branch_forward * distance + main_forward * curve_offset
			position_2d.x = clamp(position_2d.x, -world_half + boundary_margin, world_half - boundary_margin)
			position_2d.y = clamp(position_2d.y, -world_half + boundary_margin, world_half - boundary_margin)
			positions.append(position_2d)
			height_profile[point_index] = _get_base_height(position_2d.x, position_2d.y)

		height_profile[0] = junction.y
		for pass_index: int in range(18):
			var smoothed_profile: PackedFloat64Array = height_profile.duplicate()
			for point_index: int in range(1, point_count - 1):
				smoothed_profile[point_index] = lerp(height_profile[point_index], (height_profile[point_index - 1] + height_profile[point_index + 1]) * 0.5, 0.58)
			height_profile = smoothed_profile
			height_profile[0] = junction.y
			_limit_branch_grade(height_profile, positions)
		var mesh_margin: float = chunk_size / float(max(chunk_resolution, 1)) * sqrt(2.0) + 0.5
		var flat_distance: float = buildable_plot_depth * 0.5 + mesh_margin + buildable_plot_blend_width + max(earthwork_width, 3.0)
		var flat_point_count: int = int(ceil(flat_distance / point_spacing)) + 1
		var flat_entry_start: int = max(1, point_count - flat_point_count)
		var plot_height: float = height_profile[flat_entry_start]
		for point_index: int in range(flat_entry_start, point_count):
			height_profile[point_index] = plot_height

		var branch_path: PackedVector3Array = PackedVector3Array()
		for point_index: int in range(point_count):
			var position_2d: Vector2 = positions[point_index]
			branch_path.append(Vector3(position_2d.x, height_profile[point_index], position_2d.y))
		_road_paths.append(branch_path)
		_add_buildable_plot(branch_path, branch_index)


func _find_flattest_main_road_index(target_index: int, search_radius: int) -> int:
	var best_index: int = clampi(target_index, 2, _road_points.size() - 3)
	var best_grade: float = INF
	for index: int in range(max(2, best_index - search_radius), min(_road_points.size() - 2, best_index + search_radius + 1)):
		var first: Vector3 = _road_points[index - 1]
		var last: Vector3 = _road_points[index + 1]
		var distance: float = Vector2(last.x - first.x, last.z - first.z).length()
		var grade: float = abs(last.y - first.y) / max(distance, 0.001)
		if grade < best_grade:
			best_grade = grade
			best_index = index
	return best_index


func _limit_branch_grade(profile: PackedFloat64Array, positions: PackedVector2Array) -> void:
	for index: int in range(1, profile.size()):
		var distance: float = positions[index].distance_to(positions[index - 1])
		var maximum_change: float = max_road_grade * distance
		profile[index] = clamp(profile[index], profile[index - 1] - maximum_change, profile[index - 1] + maximum_change)


func _add_buildable_plot(path: PackedVector3Array, branch_index: int) -> void:
	var end: Vector3 = path[path.size() - 1]
	var previous: Vector3 = path[path.size() - 2]
	var forward: Vector2 = Vector2(end.x - previous.x, end.z - previous.z).normalized()
	var right: Vector2 = Vector2(forward.y, -forward.x)
	_buildable_plots.append({
		"name": "Plot_%d" % branch_index,
		"center": Vector2(end.x, end.z),
		"height": end.y,
		"forward": forward,
		"right": right,
		"half_extents": Vector2(buildable_plot_width * 0.5, buildable_plot_depth * 0.5),
		"terrain_half_extents": Vector2(buildable_plot_width * 0.5, buildable_plot_depth * 0.5) + Vector2.ONE * (chunk_size / float(max(chunk_resolution, 1)) * sqrt(2.0) + 0.5),
		"blend_width": buildable_plot_blend_width,
	})


func _limit_profile_grade(profile: PackedFloat64Array, x_values: PackedFloat64Array, row_spacing: float) -> void:
	for row: int in range(1, profile.size()):
		var horizontal_distance: float = Vector2(x_values[row] - x_values[row - 1], row_spacing).length()
		var maximum_change: float = max_road_grade * horizontal_distance
		profile[row] = clamp(profile[row], profile[row - 1] - maximum_change, profile[row - 1] + maximum_change)
	for row: int in range(profile.size() - 2, -1, -1):
		var horizontal_distance: float = Vector2(x_values[row + 1] - x_values[row], row_spacing).length()
		var maximum_change: float = max_road_grade * horizontal_distance
		profile[row] = clamp(profile[row], profile[row + 1] - maximum_change, profile[row + 1] + maximum_change)


func _apply_flattening_plots(world_x: float, world_z: float, source_height: float) -> float:
	var result: float = source_height
	var query: Vector2 = Vector2(world_x, world_z)
	var plots: Array[Dictionary] = []
	plots.append_array(_buildable_plots)
	plots.append_array(_parkour_plots)
	for plot: Dictionary in plots:
		var center: Vector2 = plot["center"] as Vector2
		var forward: Vector2 = plot["forward"] as Vector2
		var right: Vector2 = plot["right"] as Vector2
		var half_extents: Vector2 = plot.get("terrain_half_extents", plot["half_extents"]) as Vector2
		var delta: Vector2 = query - center
		var local_position: Vector2 = Vector2(delta.dot(right), delta.dot(forward))
		if abs(local_position.x) <= half_extents.x and abs(local_position.y) <= half_extents.y:
			return float(plot["height"])
	for plot: Dictionary in plots:
		var center: Vector2 = plot["center"] as Vector2
		var forward: Vector2 = plot["forward"] as Vector2
		var right: Vector2 = plot["right"] as Vector2
		var half_extents: Vector2 = plot.get("terrain_half_extents", plot["half_extents"]) as Vector2
		var delta: Vector2 = query - center
		var local_position: Vector2 = Vector2(delta.dot(right), delta.dot(forward))
		var edge_delta: Vector2 = Vector2(abs(local_position.x), abs(local_position.y)) - half_extents
		var outside_distance: float = Vector2(max(edge_delta.x, 0.0), max(edge_delta.y, 0.0)).length()
		var signed_distance: float = outside_distance + min(max(edge_delta.x, edge_delta.y), 0.0)
		var target_height: float = float(plot["height"])
		if signed_distance <= 0.0:
			result = target_height
		else:
			var blend_width: float = float(plot["blend_width"])
			if signed_distance < blend_width:
				var blend: float = smoothstep(0.0, blend_width, signed_distance)
				result = lerp(target_height, result, blend)
	return result


func _nearest_road_sample(world_x: float, world_z: float) -> Vector2:
	var query: Vector2 = Vector2(world_x, world_z)
	var best_distance_squared: float = INF
	var best_height: float = 0.0

	for path: PackedVector3Array in _road_paths:
		for index: int in range(path.size() - 1):
			var first: Vector3 = path[index]
			var second: Vector3 = path[index + 1]
			var first_2d: Vector2 = Vector2(first.x, first.z)
			var second_2d: Vector2 = Vector2(second.x, second.z)
			var segment: Vector2 = second_2d - first_2d
			var segment_length_squared: float = segment.length_squared()
			var t: float = 0.0
			if segment_length_squared > 0.0001:
				t = clamp((query - first_2d).dot(segment) / segment_length_squared, 0.0, 1.0)
			var closest: Vector2 = first_2d + segment * t
			var distance_squared: float = query.distance_squared_to(closest)
			if distance_squared < best_distance_squared:
				best_distance_squared = distance_squared
				best_height = lerp(first.y, second.y, t)

	return Vector2(sqrt(best_distance_squared), best_height)


func _build_terrain_chunks() -> void:
	_terrain_material = StandardMaterial3D.new()
	_terrain_material.vertex_color_use_as_albedo = true
	_terrain_material.roughness = 0.92
	_terrain_material.metallic = 0.0

	var world_min: float = -get_world_size() * 0.5
	var vertex_step: float = chunk_size / float(chunk_resolution)
	var total_chunks: int = chunk_count * chunk_count
	var current_chunk: int = 0
	for chunk_z: int in range(chunk_count):
		for chunk_x: int in range(chunk_count):
			var origin_x: float = world_min + chunk_x * chunk_size
			var origin_z: float = world_min + chunk_z * chunk_size
			var mesh: ArrayMesh = _create_chunk_mesh(origin_x, origin_z, vertex_step)
			var mesh_instance: MeshInstance3D = MeshInstance3D.new()
			mesh_instance.name = "Chunk_%d_%d" % [chunk_x, chunk_z]
			mesh_instance.mesh = mesh
			mesh_instance.material_override = _terrain_material
			_terrain_root.add_child(mesh_instance)

			var static_body: StaticBody3D = StaticBody3D.new()
			static_body.name = "Collision"
			var collision_shape: CollisionShape3D = CollisionShape3D.new()
			collision_shape.shape = mesh.create_trimesh_shape()
			static_body.add_child(collision_shape)
			mesh_instance.add_child(static_body)

			current_chunk += 1
			var percent: float = 20.0 + (float(current_chunk) / float(total_chunks)) * 40.0
			generation_progress.emit("Generating terrain chunk %d/%d..." % [current_chunk, total_chunks], percent)
			await get_tree().process_frame


func _create_chunk_mesh(origin_x: float, origin_z: float, vertex_step: float) -> ArrayMesh:
	var side: int = chunk_resolution + 1
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	var uvs: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()
	vertices.resize(side * side)
	normals.resize(side * side)
	colors.resize(side * side)
	uvs.resize(side * side)

	for local_z: int in range(side):
		for local_x: int in range(side):
			var vertex_index: int = local_z * side + local_x
			var world_x: float = origin_x + local_x * vertex_step
			var world_z: float = origin_z + local_z * vertex_step
			var height: float = get_height_at(world_x, world_z)
			var normal: Vector3 = get_terrain_normal(world_x, world_z)
			vertices[vertex_index] = Vector3(world_x, height, world_z)
			normals[vertex_index] = normal
			colors[vertex_index] = _terrain_color(height, normal)
			uvs[vertex_index] = Vector2(world_x, world_z) * 0.025

	for local_z: int in range(chunk_resolution):
		for local_x: int in range(chunk_resolution):
			var top_left: int = local_z * side + local_x
			var top_right: int = top_left + 1
			var bottom_left: int = top_left + side
			var bottom_right: int = bottom_left + 1
			indices.append_array(PackedInt32Array([top_left, top_right, bottom_left, top_right, bottom_right, bottom_left]))

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _terrain_color(height: float, normal: Vector3) -> Color:
	var slope: float = 1.0 - normal.y
	var low: Color = Color("405d3a")
	var grass: Color = Color("6f8849")
	var earth: Color = Color("78644a")
	var rock: Color = Color("777a73")
	var snow: Color = Color("d9e0dc")
	var height_factor: float = clamp((height + 15.0) / max(mountain_height * 0.78, 1.0), 0.0, 1.0)
	var color: Color = low.lerp(grass, smoothstep(0.0, 0.25, height_factor))
	color = color.lerp(earth, smoothstep(0.35, 0.62, height_factor))
	color = color.lerp(rock, smoothstep(0.52, 0.78, height_factor))
	color = color.lerp(snow, smoothstep(0.78, 1.0, height_factor))
	if slope > 0.28:
		color = color.lerp(rock.darkened(0.12), smoothstep(0.28, 0.62, slope))
	return color


func _build_road() -> void:
	var road_material: StandardMaterial3D = StandardMaterial3D.new()
	road_material.albedo_color = Color("34383a")
	road_material.roughness = 0.88

	var line_material: StandardMaterial3D = StandardMaterial3D.new()
	line_material.albedo_color = Color("e7c85a")
	line_material.roughness = 0.8

	var shoulder_material: StandardMaterial3D = StandardMaterial3D.new()
	shoulder_material.albedo_color = Color("8a806c")
	shoulder_material.roughness = 1.0

	var total_roads: int = _road_paths.size()
	for path_index: int in range(total_roads):
		var path: PackedVector3Array = _road_paths[path_index]
		var suffix: String = "" if path_index == 0 else "_%d" % path_index
		var surface_path: PackedVector3Array = path if path_index == 0 else _trim_path_start(path, road_width * 0.5)
		var line_path: PackedVector3Array = path if path_index == 0 else _trim_path_start(path, road_width * 0.5 + 1.8)
		var shoulder_path: PackedVector3Array = path if path_index == 0 else _trim_path_start(path, road_width * 0.5 + 1.2)
		var road_mesh_instance: MeshInstance3D = MeshInstance3D.new()
		road_mesh_instance.name = "RoadSurface%s" % suffix
		var road_mesh: ArrayMesh = _create_ribbon_mesh(surface_path, road_width, road_surface_lift)
		road_mesh_instance.mesh = road_mesh
		road_mesh_instance.material_override = road_material
		_road_root.add_child(road_mesh_instance)
		var road_collision: StaticBody3D = StaticBody3D.new()
		road_collision.name = "Collision"
		var road_collision_shape: CollisionShape3D = CollisionShape3D.new()
		road_collision_shape.shape = road_mesh.create_trimesh_shape()
		road_collision.add_child(road_collision_shape)
		road_mesh_instance.add_child(road_collision)

		var center_line: MeshInstance3D = MeshInstance3D.new()
		center_line.name = "CenterLine%s" % suffix
		center_line.mesh = _create_ribbon_mesh(line_path, 0.28, road_surface_lift + 0.025)
		center_line.material_override = line_material
		_road_root.add_child(center_line)

		for side: float in [-1.0, 1.0]:
			var shoulder: MeshInstance3D = MeshInstance3D.new()
			var side_name: String = "Left" if side < 0.0 else "Right"
			shoulder.name = "Shoulder_%s%s" % [side_name, suffix]
			shoulder.mesh = _create_offset_ribbon_mesh(shoulder_path, 1.1, side * (road_width * 0.5 + 0.55), road_surface_lift)
			shoulder.material_override = shoulder_material
			_road_root.add_child(shoulder)

		var percent: float = 60.0 + (float(path_index + 1) / float(total_roads)) * 25.0
		generation_progress.emit("Building road segment %d/%d..." % [path_index + 1, total_roads], percent)
		await get_tree().process_frame


func _trim_path_start(path: PackedVector3Array, trim_distance: float) -> PackedVector3Array:
	if path.size() < 2 or trim_distance <= 0.0:
		return path.duplicate()
	var result: PackedVector3Array = PackedVector3Array()
	var remaining: float = trim_distance
	for index: int in range(path.size() - 1):
		var first: Vector3 = path[index]
		var second: Vector3 = path[index + 1]
		var segment_length: float = first.distance_to(second)
		if segment_length <= 0.0001:
			continue
		if remaining <= segment_length:
			result.append(first.lerp(second, remaining / segment_length))
			for tail_index: int in range(index + 1, path.size()):
				result.append(path[tail_index])
			break
		remaining -= segment_length
	if result.size() < 2:
		return path.duplicate()
	return result


func _create_ribbon_mesh(path: PackedVector3Array, width: float, y_offset: float) -> ArrayMesh:
	return _create_offset_ribbon_mesh(path, width, 0.0, y_offset)


func _create_offset_ribbon_mesh(path: PackedVector3Array, width: float, lateral_offset: float, y_offset: float) -> ArrayMesh:
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()
	var distance_along: float = 0.0

	for index: int in range(path.size()):
		var point: Vector3 = path[index]
		var previous: Vector3 = path[max(0, index - 1)]
		var next: Vector3 = path[min(path.size() - 1, index + 1)]
		var tangent_2d: Vector2 = Vector2(next.x - previous.x, next.z - previous.z).normalized()
		var right: Vector3 = Vector3(tangent_2d.y, 0.0, -tangent_2d.x)
		var center: Vector3 = point + right * lateral_offset + Vector3.UP * y_offset
		vertices.append(center - right * width * 0.5)
		vertices.append(center + right * width * 0.5)
		normals.append(Vector3.UP)
		normals.append(Vector3.UP)
		if index > 0:
			distance_along += point.distance_to(path[index - 1])
		uvs.append(Vector2(0.0, distance_along * 0.08))
		uvs.append(Vector2(1.0, distance_along * 0.08))

	for index: int in range(path.size() - 1):
		var first: int = index * 2
		indices.append_array(PackedInt32Array([first, first + 1, first + 2, first + 1, first + 3, first + 2]))

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _build_decorations() -> void:
	_decoration_positions.clear()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = world_seed * 7919 + 17
	var world_half: float = get_world_size() * 0.5 - 10.0
	var rock_transforms: Array[Transform3D] = []
	var tree_transforms: Array[Transform3D] = []

	# Targets from new configurable parameters; vegetation_density scales both
	var desired_trees: int = int(tree_count * vegetation_density)
	var desired_rocks: int = int(rock_count * vegetation_density)

	# Fallback to decoration_count if new counts are zero (preserve old behavior)
	if desired_trees <= 0 and desired_rocks <= 0:
		desired_trees = int(decoration_count * 0.75)
		desired_rocks = int(decoration_count * 0.25)

	var total_desired: int = desired_trees + desired_rocks
	var attempt_limit: int = max(decoration_count * 3, total_desired * 4 + 200)

	# Clumping queue
	var clump_stack: Array[Vector2] = []

	for attempt: int in range(attempt_limit):
		if rock_transforms.size() >= desired_rocks and tree_transforms.size() >= desired_trees:
			break

		var x: float
		var z: float
		if not clump_stack.is_empty() and rng.randf() < tree_clump_chance and tree_transforms.size() < desired_trees:
			var base: Vector2 = clump_stack.pop_back()
			x = base.x + rng.randf_range(-9.0, 9.0)
			z = base.y + rng.randf_range(-9.0, 9.0)
			x = clamp(x, -world_half, world_half)
			z = clamp(z, -world_half, world_half)
		else:
			x = rng.randf_range(-world_half, world_half)
			z = rng.randf_range(-world_half, world_half)

		var clearance: float = get_road_decoration_clearance() + 1.0
		if distance_to_road(x, z) < clearance:
			continue
		if distance_to_buildable_plot(x, z) < 8.0:
			continue
		if distance_to_parkour_plot(x, z) < 6.0:
			continue
		# avoid interactive props
		if not _interactive_positions.is_empty():
			var too_close: bool = false
			for ip in _interactive_positions:
				if Vector2(x, z).distance_to(Vector2(ip.x, ip.z)) < 4.0:
					too_close = true
					break
			if too_close:
				continue
		var normal: Vector3 = get_terrain_normal(x, z)
		if normal.y < 0.82:
			continue
		var height: float = get_rendered_terrain_height(x, z) - decoration_ground_embed
		var scale_value: float = rng.randf_range(0.65, 1.8)
		var instance_basis: Basis = Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * scale_value)
		var instance_transform: Transform3D = Transform3D(instance_basis, Vector3(x, height, z))
		_decoration_positions.append(instance_transform.origin)

		var is_rock_biome: bool = height > mountain_height * 0.46
		# Decide type based on remaining quotas and biome
		var want_rock: bool = false
		if is_rock_biome:
			want_rock = rock_transforms.size() < desired_rocks and (tree_transforms.size() >= desired_trees or rng.randf() < 0.65)
		else:
			want_rock = rock_transforms.size() < desired_rocks and (rng.randf() < 0.22 or tree_transforms.size() >= desired_trees)

		if want_rock:
			rock_transforms.append(instance_transform)
		else:
			if tree_transforms.size() < desired_trees:
				tree_transforms.append(instance_transform)
				# enqueue for clump
				if rng.randf() < tree_clump_chance:
					clump_stack.append(Vector2(x, z))
					if rng.randf() < 0.5:
						clump_stack.append(Vector2(x + rng.randf_range(-2.0, 2.0), z + rng.randf_range(-2.0, 2.0)))
			else:
				# trees full, fill rocks as overflow
				if rock_transforms.size() < desired_rocks:
					rock_transforms.append(instance_transform)

	_create_rock_multimesh(rock_transforms)
	_create_tree_multimesh(tree_transforms)
	_create_tree_colliders(tree_transforms)
	_build_settlements()


func _build_settlements() -> void:
	var pad_material: StandardMaterial3D = StandardMaterial3D.new()
	pad_material.albedo_color = Color("9b9279")
	pad_material.roughness = 1.0
	var wall_materials: Array[StandardMaterial3D] = []
	for color: Color in [Color("c6a777"), Color("a8b4a0"), Color("b98270"), Color("d0bd91")]:
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.88
		wall_materials.append(material)
	var roof_material: StandardMaterial3D = StandardMaterial3D.new()
	roof_material.albedo_color = Color("493e3a")
	roof_material.roughness = 0.95

	for plot_index: int in range(_buildable_plots.size()):
		var plot: Dictionary = _buildable_plots[plot_index]
		var center: Vector2 = plot["center"] as Vector2
		var forward: Vector2 = plot["forward"] as Vector2
		var right: Vector2 = plot["right"] as Vector2
		var half_extents: Vector2 = plot["half_extents"] as Vector2
		var height: float = float(plot["height"])
		var settlement: Node3D = Node3D.new()
		settlement.name = "Settlement_%d" % plot_index
		_decoration_root.add_child(settlement)

		_create_box_body(
			settlement,
			"BuildablePad",
			Vector3(center.x, height + 0.04, center.y),
			Vector3(half_extents.x * 2.0, 0.08, half_extents.y * 2.0),
			pad_material,
			Basis(Vector3.UP, atan2(forward.x, forward.y))
		)

		var house_offsets: Array[Vector2] = []
		var usable_half_width: float = max(half_extents.x - 14.0, 18.0)
		var usable_half_depth: float = max(half_extents.y - 14.0, 18.0)
		for row: int in range(4):
			var local_z: float = lerp(-usable_half_depth, usable_half_depth, float(row) / 3.0)
			for column: int in range(4):
				var local_x: float = lerp(-usable_half_width, usable_half_width, float(column) / 3.0)
				house_offsets.append(Vector2(local_x, local_z))
		for house_index: int in range(house_offsets.size()):
			var local_offset: Vector2 = house_offsets[house_index]
			var house_position_2d: Vector2 = center + right * local_offset.x + forward * local_offset.y
			var house: Node3D = Node3D.new()
			house.name = "House_%d" % house_index
			settlement.add_child(house)
			house.global_position = Vector3(house_position_2d.x, height + 0.08, house_position_2d.y)
			house.look_at(Vector3(center.x, height + 0.08, center.y), Vector3.UP)
			_build_enterable_house(house, wall_materials[(plot_index * 2 + house_index) % wall_materials.size()], roof_material)


func _build_enterable_house(house: Node3D, wall_material: StandardMaterial3D, roof_material: StandardMaterial3D) -> void:
	var width: float = 8.0
	var depth: float = 7.0
	var wall_height: float = 3.2
	var wall_thickness: float = 0.32
	var door_width: float = 2.2
	var door_height: float = 2.5
	var front_segment_width: float = (width - door_width) * 0.5
	var front_segment_offset: float = door_width * 0.5 + front_segment_width * 0.5

	_create_box_body(house, "BackWall", Vector3(0.0, wall_height * 0.5, depth * 0.5), Vector3(width, wall_height, wall_thickness), wall_material)
	_create_box_body(house, "LeftWall", Vector3(-width * 0.5, wall_height * 0.5, 0.0), Vector3(wall_thickness, wall_height, depth), wall_material)
	_create_box_body(house, "RightWall", Vector3(width * 0.5, wall_height * 0.5, 0.0), Vector3(wall_thickness, wall_height, depth), wall_material)
	_create_box_body(house, "FrontLeft", Vector3(-front_segment_offset, wall_height * 0.5, -depth * 0.5), Vector3(front_segment_width, wall_height, wall_thickness), wall_material)
	_create_box_body(house, "FrontRight", Vector3(front_segment_offset, wall_height * 0.5, -depth * 0.5), Vector3(front_segment_width, wall_height, wall_thickness), wall_material)
	var lintel_height: float = wall_height - door_height
	_create_box_body(house, "DoorLintel", Vector3(0.0, door_height + lintel_height * 0.5, -depth * 0.5), Vector3(door_width, lintel_height, wall_thickness), wall_material)
	_create_box_body(house, "Roof", Vector3(0.0, wall_height + 0.18, 0.0), Vector3(width + 0.6, 0.36, depth + 0.6), roof_material)


func _create_box_body(parent: Node3D, node_name: String, local_position: Vector3, size: Vector3, material: StandardMaterial3D, placement_basis: Basis = Basis.IDENTITY) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = node_name
	body.transform = Transform3D(placement_basis, local_position)
	parent.add_child(body)
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	body.add_child(mesh_instance)
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	return body


func _create_rock_multimesh(transforms: Array[Transform3D]) -> void:
	var rock_mesh: SphereMesh = SphereMesh.new()
	rock_mesh.radius = 1.35
	rock_mesh.height = 1.8
	rock_mesh.radial_segments = 8
	rock_mesh.rings = 4
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color("6f726d")
	material.roughness = 1.0
	rock_mesh.material = material
	_create_multimesh_instance("Rocks", rock_mesh, transforms)


func _create_tree_multimesh(transforms: Array[Transform3D]) -> void:
	var trunk_mesh: CylinderMesh = CylinderMesh.new()
	trunk_mesh.top_radius = 0.22
	trunk_mesh.bottom_radius = 0.30
	trunk_mesh.height = 3.2
	trunk_mesh.radial_segments = 7
	trunk_mesh.rings = 1
	var trunk_material: StandardMaterial3D = StandardMaterial3D.new()
	trunk_material.albedo_color = Color("654731")
	trunk_material.roughness = 1.0
	trunk_mesh.material = trunk_material

	var canopy_mesh: CylinderMesh = CylinderMesh.new()
	canopy_mesh.top_radius = 0.18
	canopy_mesh.bottom_radius = 1.45
	canopy_mesh.height = 4.0
	canopy_mesh.radial_segments = 8
	canopy_mesh.rings = 2
	var canopy_material: StandardMaterial3D = StandardMaterial3D.new()
	canopy_material.albedo_color = Color("294c35")
	canopy_material.roughness = 1.0
	canopy_mesh.material = canopy_material

	var trunk_transforms: Array[Transform3D] = []
	var canopy_transforms: Array[Transform3D] = []
	for original: Transform3D in transforms:
		var instance_scale: float = original.basis.get_scale().y
		var trunk: Transform3D = original
		trunk.origin.y += 1.6 * instance_scale
		trunk_transforms.append(trunk)
		var canopy: Transform3D = original
		canopy.origin.y += 4.5 * instance_scale
		canopy_transforms.append(canopy)
	_create_multimesh_instance("TreeTrunks", trunk_mesh, trunk_transforms)
	_create_multimesh_instance("Trees", canopy_mesh, canopy_transforms)


func _create_tree_colliders(transforms: Array[Transform3D]) -> void:
	var collider_root: Node3D = Node3D.new()
	collider_root.name = "TreeColliders"
	_decoration_root.add_child(collider_root)

	for index: int in range(transforms.size()):
		var original: Transform3D = transforms[index]
		var instance_scale: float = original.basis.get_scale().y
		var trunk_origin: Vector3 = original.origin + Vector3.UP * 1.6 * instance_scale

		var body: StaticBody3D = StaticBody3D.new()
		body.name = "TreeCollider_%d" % index
		body.transform = Transform3D(original.basis.orthonormalized(), trunk_origin)
		body.collision_layer = 1
		body.collision_mask = 0
		collider_root.add_child(body)

		var collision_shape: CollisionShape3D = CollisionShape3D.new()
		collision_shape.name = "TrunkShape"
		var cylinder: CylinderShape3D = CylinderShape3D.new()
		cylinder.height = 2.8 * instance_scale
		cylinder.radius = 0.35 * instance_scale
		collision_shape.shape = cylinder
		body.add_child(collision_shape)


func _create_multimesh_instance(node_name: String, mesh: Mesh, transforms: Array[Transform3D]) -> void:
	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	multimesh.visible_instance_count = transforms.size()
	for index: int in range(transforms.size()):
		multimesh.set_instance_transform(index, transforms[index])
	var instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multimesh
	_decoration_root.add_child(instance)


func _build_interactive_props() -> void:
	_interactive_positions.clear()
	if _interactive_root == null:
		return
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = world_seed * 9001 + 73
	var world_half: float = get_world_size() * 0.5 - 18.0
	var desired: int = clampi(interactive_prop_count, 0, 200)
	var attempts: int = desired * 8 + 80
	var placed: int = 0

	for _i in range(attempts):
		if placed >= desired:
			break
		var x: float = rng.randf_range(-world_half, world_half)
		var z: float = rng.randf_range(-world_half, world_half)

		# prefer slightly near roads for gameplay, but avoid blocking them
		if rng.randf() < 0.65 and not _road_paths.is_empty():
			var main_path: PackedVector3Array = _road_paths[0]
			if main_path.size() > 4:
				var idx: int = rng.randi_range(0, main_path.size() - 1)
				var rp: Vector3 = main_path[idx]
				var angle: float = rng.randf_range(0.0, TAU)
				var radius: float = rng.randf_range(get_road_decoration_clearance() + 4.0, get_road_decoration_clearance() + 38.0)
				x = rp.x + cos(angle) * radius
				z = rp.z + sin(angle) * radius

		if distance_to_road(x, z) < get_road_decoration_clearance() + 1.0:
			continue
		if distance_to_buildable_plot(x, z) < 12.0:
			continue
		if distance_to_parkour_plot(x, z) < 9.0:
			continue
		var normal: Vector3 = get_terrain_normal(x, z)
		if normal.y < 0.75:
			continue
		# avoid overlapping existing props
		var too_close: bool = false
		for prev in _interactive_positions:
			if Vector2(x, z).distance_to(Vector2(prev.x, prev.z)) < interactive_spawn_radius * 1.8:
				too_close = true
				break
		if too_close:
			continue
		# avoid trees density
		for dpos in _decoration_positions:
			if Vector2(x, z).distance_to(Vector2(dpos.x, dpos.z)) < 2.0:
				too_close = true
				break
		if too_close:
			continue

		var h: float = get_rendered_terrain_height(x, z)
		var pos := Vector3(x, h, z)

		# pick variant with bias
		var bias: float = clamp(interactive_variation_bias, 0.0, 1.0)
		var variant_choice: int
		var roll: float = rng.randf()
		# distribution: 0.0 bias -> 60% rock, 20% tree, 10% crate, 10% barrel
		# 0.5 bias -> 30% rock, 35% tree, 20% crate, 15% barrel
		# 1.0 bias -> 15% rock, 25% tree, 35% crate, 25% barrel
		var rock_w: float = lerp(0.6, 0.15, bias)
		var tree_w: float = lerp(0.2, 0.25, bias) + (0.15 if bias < 0.7 else 0.0)
		if bias < 0.5:
			tree_w = lerp(0.2, 0.35, bias * 2.0)
		var crate_w: float = lerp(0.1, 0.35, bias)
		if roll < rock_w:
			variant_choice = 0 # PUSHABLE_ROCK
		elif roll < rock_w + tree_w:
			variant_choice = 1 # FALLING_TREE
		elif roll < rock_w + tree_w + crate_w:
			variant_choice = 2 # SUPPLY_CRATE
		else:
			variant_choice = 3 # BOUNCY_BARREL

		var obstacle: Node3D = InteractiveObstacleScene.new() as Node3D
		obstacle.name = "Interactive_%d_%s" % [placed, ["Rock", "FallingTree", "Crate", "Barrel"][variant_choice]]
		obstacle.set("variant", variant_choice)
		obstacle.set("auto_trigger_distance", 8.5 if variant_choice == 1 else 5.5)
		_interactive_root.add_child(obstacle)
		obstacle.global_position = pos + Vector3.UP * 0.15
		# slightly random yaw
		obstacle.rotation.y = rng.randf_range(0.0, TAU)

		_interactive_positions.append(obstacle.global_position)
		placed += 1

	print("INTERACTIVE_PROPS_BUILD ", placed, " / ", desired)


func _count_interactive_props() -> int:
	if _interactive_root == null:
		return 0
	return _interactive_root.get_child_count()


func _count_decoration_instances() -> int:
	var total: int = 0
	for child: Node in _decoration_root.get_children():
		if child is MultiMeshInstance3D:
			var instance: MultiMeshInstance3D = child as MultiMeshInstance3D
			if instance.name == "TreeTrunks":
				continue
			if instance.multimesh != null:
				total += instance.multimesh.instance_count
	return total


func _count_road_points() -> int:
	var total: int = 0
	for path: PackedVector3Array in _road_paths:
		total += path.size()
	return total


func _count_houses() -> int:
	var total: int = 0
	if _decoration_root == null:
		return total
	for settlement: Node in _decoration_root.get_children():
		if not settlement.name.begins_with("Settlement_"):
			continue
		for child: Node in settlement.get_children():
			if child.name.begins_with("House_"):
				total += 1
	return total
