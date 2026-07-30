extends SceneTree

const GENERATOR_SCRIPT: Script = preload("res://scripts/world_generator.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var generator: ProceduralWorldGenerator = GENERATOR_SCRIPT.new() as ProceduralWorldGenerator
	root.add_child(generator)
	await process_frame

	_check(generator.get_world_size() >= 1100.0, "default world is larger than one square kilometre")
	_check(_exported_range_max(generator, &"chunk_count") >= 10.0, "generator exposes at least ten chunks per side")
	_check(generator.get_road_paths().size() >= 5, "default world contains a main road and four branches")
	_check(generator.get_decoration_positions().size() >= 1200, "default world contains dense procedural vegetation and rocks")
	_check(generator.has_node("Decorations/TreeTrunks") and generator.has_node("Decorations/Trees"), "procedural trees include separate trunks and canopies")
	_check(generator.get_child_count() == 3, "generator owns exactly three generated containers")
	_check(generator.get_node("TerrainChunks").get_child_count() == generator.chunk_count * generator.chunk_count, "expected chunk count exists")
	_check(generator.get_road_points().size() > 20, "road contains enough samples")
	_check(generator.get_max_actual_road_grade() <= generator.max_road_grade + 0.0001, "road grade respects configured maximum")
	_check_road_network(generator)
	_check_road_junctions(generator)
	_check_chunk_seam(generator)
	_check_road_surface(generator)
	_check_rendered_road_clearance(generator)
	_check_buildable_plots(generator)
	_check_parkour_plots(generator)
	_check_landmark_mountain(generator)
	_check_decoration_clearance(generator)
	_check_decoration_grounding(generator)

	var first_road: PackedVector3Array = generator.get_road_points()
	var first_height: float = generator.get_height_at(37.0, -91.0)
	generator.regenerate()
	await process_frame
	_check(generator.get_child_count() == 3, "regeneration replaces rather than accumulates containers")
	_check(_packed_vectors_equal(first_road, generator.get_road_points()), "same seed reproduces identical road")
	_check(is_equal_approx(first_height, generator.get_height_at(37.0, -91.0)), "same seed reproduces identical terrain")

	generator.world_seed += 1
	generator.regenerate()
	await process_frame
	_check(not is_equal_approx(first_height, generator.get_height_at(37.0, -91.0)), "different seed changes terrain")
	_check_rendered_road_clearance(generator)

	generator.chunk_count = 10
	generator.chunk_size = 256.0
	generator.chunk_resolution = 16
	generator.regenerate()
	await process_frame
	_check(is_equal_approx(generator.get_world_size(), 2560.0), "expanded settings generate a 2.56 km square world")
	_check(generator.get_node("TerrainChunks").get_child_count() == 100, "expanded world generates all one hundred terrain chunks")
	generator.queue_free()
	await process_frame
	await process_frame

	if _failures.is_empty():
		print("VERIFY_WORLD PASS")
		quit(0)
	else:
		for failure: String in _failures:
			push_error("VERIFY_WORLD FAIL: " + failure)
		quit(1)


func _check_chunk_seam(generator: ProceduralWorldGenerator) -> void:
	var left_chunk: MeshInstance3D = generator.get_node("TerrainChunks/Chunk_0_0") as MeshInstance3D
	var right_chunk: MeshInstance3D = generator.get_node("TerrainChunks/Chunk_1_0") as MeshInstance3D
	var left_arrays: Array = left_chunk.mesh.surface_get_arrays(0)
	var right_arrays: Array = right_chunk.mesh.surface_get_arrays(0)
	var left_vertices: PackedVector3Array = left_arrays[Mesh.ARRAY_VERTEX]
	var right_vertices: PackedVector3Array = right_arrays[Mesh.ARRAY_VERTEX]
	var left_normals: PackedVector3Array = left_arrays[Mesh.ARRAY_NORMAL]
	var right_normals: PackedVector3Array = right_arrays[Mesh.ARRAY_NORMAL]
	var side: int = generator.chunk_resolution + 1
	for row: int in range(side):
		var left_index: int = row * side + generator.chunk_resolution
		var right_index: int = row * side
		_check(left_vertices[left_index].is_equal_approx(right_vertices[right_index]), "shared chunk-edge vertices match")
		_check(left_normals[left_index].is_equal_approx(right_normals[right_index]), "shared chunk-edge normals match")


func _check_road_surface(generator: ProceduralWorldGenerator) -> void:
	var points: PackedVector3Array = generator.get_road_points()
	for index: int in range(2, points.size() - 2, 5):
		var point: Vector3 = points[index]
		_check(abs(generator.get_height_at(point.x, point.z) - point.y) < 0.001, "terrain centerline matches road profile")


func _check_road_network(generator: ProceduralWorldGenerator) -> void:
	var paths: Array[PackedVector3Array] = generator.get_road_paths()
	_check(paths.size() == generator.branch_count + 1, "road network contains the main road and requested branches")
	if paths.is_empty():
		return
	var main_path: PackedVector3Array = paths[0]
	for path_index: int in range(1, paths.size()):
		var branch: PackedVector3Array = paths[path_index]
		_check(branch.size() >= 8, "branch road contains enough samples")
		var starts_on_main: bool = false
		var junction_index: int = -1
		for main_index: int in range(main_path.size()):
			var main_point: Vector3 = main_path[main_index]
			if branch[0].distance_to(main_point) < 0.001:
				starts_on_main = true
				junction_index = main_index
				break
		_check(starts_on_main, "branch begins at a main-road junction")
		if junction_index >= 1 and junction_index < main_path.size() - 1:
			var main_direction: Vector2 = Vector2(
				main_path[junction_index + 1].x - main_path[junction_index - 1].x,
				main_path[junction_index + 1].z - main_path[junction_index - 1].z
			).normalized()
			var branch_direction: Vector2 = Vector2(branch[1].x - branch[0].x, branch[1].z - branch[0].z).normalized()
			_check(abs(main_direction.dot(branch_direction)) < 0.16, "branch leaves the junction close to perpendicular before it starts curving")
		_check(Vector2(branch[-1].x, branch[-1].z).distance_to(Vector2(branch[0].x, branch[0].z)) > 90.0, "branch creates a meaningful route choice")


func _check_road_junctions(generator: ProceduralWorldGenerator) -> void:
	var paths: Array[PackedVector3Array] = generator.get_road_paths()
	for path_index: int in range(paths.size()):
		var suffix: String = "" if path_index == 0 else "_%d" % path_index
		var surface: MeshInstance3D = generator.get_node_or_null("Road/RoadSurface%s" % suffix) as MeshInstance3D
		_check(surface != null, "every road path has a rendered surface")
		if surface == null:
			continue
		_check(surface.has_node("Collision"), "every road surface has matching collision")
		if path_index == 0:
			continue
		var arrays: Array = surface.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var first_center: Vector3 = (vertices[0] + vertices[1]) * 0.5
		var junction: Vector3 = paths[path_index][0]
		var entry_distance: float = Vector2(first_center.x - junction.x, first_center.z - junction.z).length()
		_check(entry_distance >= generator.road_width * 0.48, "branch asphalt begins at the main-road edge instead of overlapping its center")
		var center_line: MeshInstance3D = generator.get_node_or_null("Road/CenterLine%s" % suffix) as MeshInstance3D
		if center_line != null:
			var line_arrays: Array = center_line.mesh.surface_get_arrays(0)
			var line_vertices: PackedVector3Array = line_arrays[Mesh.ARRAY_VERTEX]
			var line_center: Vector3 = (line_vertices[0] + line_vertices[1]) * 0.5
			var line_distance: float = Vector2(line_center.x - junction.x, line_center.z - junction.z).length()
			_check(line_distance > generator.road_width * 0.5 + 1.0, "branch center line stops before the junction conflict area")


func _check_rendered_road_clearance(generator: ProceduralWorldGenerator) -> void:
	var paths: Array[PackedVector3Array] = generator.get_road_paths()
	for path: PackedVector3Array in paths:
		for index: int in range(1, path.size() - 1, 2):
			var previous: Vector3 = path[index - 1]
			var next: Vector3 = path[index + 1]
			var tangent: Vector2 = Vector2(next.x - previous.x, next.z - previous.z).normalized()
			var right: Vector2 = Vector2(tangent.y, -tangent.x)
			for lateral: float in [-generator.road_width * 0.48, 0.0, generator.road_width * 0.48]:
				var sample_2d: Vector2 = Vector2(path[index].x, path[index].z) + right * lateral
				var mesh_height: float = _sample_terrain_mesh_height(generator, sample_2d.x, sample_2d.y)
				var road_profile_height: float = generator.get_height_at(sample_2d.x, sample_2d.y)
				var maximum_terrain_height: float = road_profile_height + generator.road_surface_lift - 0.02
				if mesh_height > maximum_terrain_height:
					_check(false, "rendered terrain stays below the road surface across its full width (%.2f > %.2f at %.1f, %.1f; lateral %.1f)" % [mesh_height, maximum_terrain_height, sample_2d.x, sample_2d.y, lateral])
					return


func _sample_terrain_mesh_height(generator: ProceduralWorldGenerator, world_x: float, world_z: float) -> float:
	var world_min: float = -generator.get_world_size() * 0.5
	var chunk_x: int = clampi(int(floor((world_x - world_min) / generator.chunk_size)), 0, generator.chunk_count - 1)
	var chunk_z: int = clampi(int(floor((world_z - world_min) / generator.chunk_size)), 0, generator.chunk_count - 1)
	var origin_x: float = world_min + chunk_x * generator.chunk_size
	var origin_z: float = world_min + chunk_z * generator.chunk_size
	var vertex_step: float = generator.chunk_size / float(generator.chunk_resolution)
	var local_x: float = clamp((world_x - origin_x) / vertex_step, 0.0, float(generator.chunk_resolution))
	var local_z: float = clamp((world_z - origin_z) / vertex_step, 0.0, float(generator.chunk_resolution))
	var cell_x: int = clampi(int(floor(local_x)), 0, generator.chunk_resolution - 1)
	var cell_z: int = clampi(int(floor(local_z)), 0, generator.chunk_resolution - 1)
	var fraction_x: float = local_x - float(cell_x)
	var fraction_z: float = local_z - float(cell_z)
	var chunk: MeshInstance3D = generator.get_node("TerrainChunks/Chunk_%d_%d" % [chunk_x, chunk_z]) as MeshInstance3D
	var arrays: Array = chunk.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var side: int = generator.chunk_resolution + 1
	var top_left: Vector3 = vertices[cell_z * side + cell_x]
	var top_right: Vector3 = vertices[cell_z * side + cell_x + 1]
	var bottom_left: Vector3 = vertices[(cell_z + 1) * side + cell_x]
	var bottom_right: Vector3 = vertices[(cell_z + 1) * side + cell_x + 1]
	if fraction_x + fraction_z <= 1.0:
		return top_left.y + fraction_x * (top_right.y - top_left.y) + fraction_z * (bottom_left.y - top_left.y)
	return top_right.y * (1.0 - fraction_z) + bottom_left.y * (1.0 - fraction_x) + bottom_right.y * (fraction_x + fraction_z - 1.0)


func _check_buildable_plots(generator: ProceduralWorldGenerator) -> void:
	var plots: Array[Dictionary] = generator.get_buildable_plots()
	_check(plots.size() == generator.branch_count, "each branch terminates at a buildable plot")
	for plot_index: int in range(plots.size()):
		var plot: Dictionary = plots[plot_index]
		var center: Vector2 = plot["center"] as Vector2
		var forward: Vector2 = plot["forward"] as Vector2
		var right: Vector2 = plot["right"] as Vector2
		var half_extents: Vector2 = plot["half_extents"] as Vector2
		_check(half_extents.x * 2.0 >= 100.0 and half_extents.y * 2.0 >= 100.0, "settlement terrain provides at least a 100 by 100 metre level district")
		var target_height: float = float(plot["height"])
		for offset: Vector2 in [Vector2.ZERO, right * half_extents.x * 0.7, -right * half_extents.x * 0.7, forward * half_extents.y * 0.7, -forward * half_extents.y * 0.7]:
			var sample: Vector2 = center + offset
			var sample_height: float = generator.get_height_at(sample.x, sample.y)
			_check(abs(sample_height - target_height) < 0.001, "buildable plot interior is level (plot %d: %.3f != %.3f at %.1f, %.1f)" % [plot_index, sample_height, target_height, sample.x, sample.y])
		var settlement: Node = generator.get_node_or_null("Decorations/Settlement_%d" % plot_index)
		_check(settlement != null, "buildable plot has a settlement marker")
		if settlement != null:
				_check(settlement.has_node("House_0") and settlement.has_node("House_15"), "large settlement contains sixteen enterable house shells")


func _check_parkour_plots(generator: ProceduralWorldGenerator) -> void:
	var plots: Array[Dictionary] = generator.get_parkour_plots()
	_check(plots.size() == 4, "world planner reserves four terrain-level parkour plots")
	for plot: Dictionary in plots:
		var center: Vector2 = plot["center"] as Vector2
		var forward: Vector2 = plot["forward"] as Vector2
		var right: Vector2 = plot["right"] as Vector2
		var half_extents: Vector2 = plot["half_extents"] as Vector2
		var target_height: float = float(plot["height"])
		_check(half_extents.x * 2.0 >= 24.0 and half_extents.y * 2.0 >= 20.0, "parkour plot is large enough for a composed location")
		for x_fraction: float in [-0.8, 0.0, 0.8]:
			for z_fraction: float in [-0.8, 0.0, 0.8]:
				var sample: Vector2 = center + right * half_extents.x * x_fraction + forward * half_extents.y * z_fraction
				var rendered_height: float = generator.get_rendered_terrain_height(sample.x, sample.y)
				_check(abs(rendered_height - target_height) < 0.001, "parkour terrain mesh is level across the reserved footprint (%.3f != %.3f at %.1f, %.1f)" % [rendered_height, target_height, sample.x, sample.y])


func _check_landmark_mountain(generator: ProceduralWorldGenerator) -> void:
	var peak: Vector2 = generator.get_mountain_landmark_position()
	var peak_height: float = generator.get_height_at(peak.x, peak.y, false)
	var ring_radius: float = generator.get_world_size() * 0.15
	var ring_height: float = 0.0
	for direction: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		var sample: Vector2 = peak + direction * ring_radius
		ring_height += generator.get_height_at(sample.x, sample.y, false)
	ring_height *= 0.25
	_check(peak_height > ring_height + generator.mountain_height * 0.42, "one large mountain remains a readable landmark")


func _check_decoration_clearance(generator: ProceduralWorldGenerator) -> void:
	var clearance: float = generator.get_road_decoration_clearance()
	var minimum_distance: float = INF
	var closest_position: Vector3 = Vector3.ZERO
	for position: Vector3 in generator.get_decoration_positions():
		var distance: float = generator.distance_to_road(position.x, position.z)
		if distance < minimum_distance:
			minimum_distance = distance
			closest_position = position
	_check(minimum_distance >= clearance, "decoration stays outside road earthworks (minimum %.3f m at %.2f, %.2f; required %.3f m)" % [minimum_distance, closest_position.x, closest_position.z, clearance])


func _check_decoration_grounding(generator: ProceduralWorldGenerator) -> void:
	var maximum_gap: float = 0.0
	var maximum_penetration: float = 0.0
	for position: Vector3 in generator.get_decoration_positions():
		var rendered_height: float = generator.get_rendered_terrain_height(position.x, position.z)
		maximum_gap = max(maximum_gap, position.y - rendered_height)
		maximum_penetration = max(maximum_penetration, rendered_height - position.y)
	_check(maximum_gap <= 0.01, "decorations never float above the rendered terrain")
	_check(maximum_penetration <= 0.35, "decorations are grounded with only a shallow terrain embed")


func _packed_vectors_equal(first: PackedVector3Array, second: PackedVector3Array) -> bool:
	if first.size() != second.size():
		return false
	for index: int in range(first.size()):
		if not first[index].is_equal_approx(second[index]):
			return false
	return true


func _check(condition: bool, message: String) -> void:
	if not condition and not _failures.has(message):
		_failures.append(message)


func _exported_range_max(object: Object, property_name: StringName) -> float:
	for property: Dictionary in object.get_property_list():
		if property.get("name", &"") != property_name:
			continue
		var parts: PackedStringArray = String(property.get("hint_string", "")).split(",")
		if parts.size() >= 2:
			return parts[1].to_float()
	return 0.0
