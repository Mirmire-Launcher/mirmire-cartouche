# SPDX-License-Identifier: GPL-3.0-or-later
extends SceneTree
## Closes the parts of a medium cut out of a downloaded model (Mirmire Cartouche: the PSP's UMD, made by
## tools/mirmire_umd.gd), as every shipped medium must be closed round a volume: each part, a sheet with open edges,
## gets a back a hair behind its front and narrow walls along its open edges. The front keeps its normals and UVs, so it
## looks as before. Run once after tools/mirmire_umd.gd, from a copy inside app/:
##   cp tools/mirmire_close_mesh.gd app/close_tmp.gd && Godot --headless --path app --script res://close_tmp.gd; rm app/close_tmp.gd

const PARTS: Array[String] = [
	"res://carousel/media/psp_umd/psp_umd_shell.res",
	"res://carousel/media/psp_umd/psp_umd_clear.res",
	"res://carousel/media/psp_umd/psp_umd_disc.res",
	"res://carousel/media/psp_umd/psp_umd_label.res",
]
## How far the back stands behind the front: 0.2 mm, in this app's units (100 mm a unit).
const THICKNESS := 0.002
## Points nearer than this are one (as the asset checks join them): a micrometre, in units.
const SAME := 0.00001


func _init() -> void:
	for path in PARTS:
		var mesh := load(path) as ArrayMesh
		var closed := ArrayMesh.new()
		for surface in mesh.get_surface_count():
			closed.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _closed(mesh.surface_get_arrays(surface)))
			closed.surface_set_material(surface, mesh.surface_get_material(surface))
			closed.surface_set_name(surface, mesh.surface_get_name(surface))
		closed.resource_name = mesh.resource_name
		print("%s: %s" % [path, ResourceSaver.save(closed, path)])
	quit()


## [param arrays] closed: its faces, the same faces turned and set back along the surface's normal, and a wall along
## each open edge joining the two.
static func _closed(arrays: Array) -> Array:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if indices.is_empty():
		indices.resize(vertices.size())
		for i in vertices.size():
			indices[i] = i
	# Each point once, however many vertices share it, and its normal: the model's own normals there, so the back
	# always stands behind the side that shows.
	var key_of := PackedInt32Array()
	var keys: Dictionary[Vector3i, int] = {}
	for vertex in vertices:
		var key := Vector3i((vertex / SAME).round())
		if key not in keys:
			keys[key] = keys.size()
		key_of.append(keys[key])
	var point_normal: Array[Vector3] = []
	point_normal.resize(keys.size())
	point_normal.fill(Vector3.ZERO)
	for i in vertices.size():
		point_normal[key_of[i]] += normals[i]
	# The open edges: those of one face only, as they run in it.
	var edges: Dictionary[int, int] = {}
	var corner_of: Dictionary[int, PackedInt32Array] = {}
	for t in range(0, indices.size(), 3):
		for k in 3:
			var from := indices[t + k]
			var to := indices[t + (k + 1) % 3]
			var a := key_of[from]
			var b := key_of[to]
			if a == b:
				continue
			edges[(a << 32) | b] = edges.get((a << 32) | b, 0) + 1
			edges[(b << 32) | a] = edges.get((b << 32) | a, 0) - 1
			corner_of[(a << 32) | b] = PackedInt32Array([from, to])
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := vertices.size()
	# The front, as it was; then the back, a hair behind, its faces turned.
	for front: bool in [true, false]:
		for i in count:
			var along := point_normal[key_of[i]].normalized()
			tool.set_normal(normals[i] if front else -normals[i])
			if not uvs.is_empty():
				tool.set_uv(uvs[i])
			tool.add_vertex(vertices[i] if front else vertices[i] - along * THICKNESS)
	for t in range(0, indices.size(), 3):
		tool.add_index(indices[t])
		tool.add_index(indices[t + 1])
		tool.add_index(indices[t + 2])
	for t in range(0, indices.size(), 3):
		tool.add_index(count + indices[t])
		tool.add_index(count + indices[t + 2])
		tool.add_index(count + indices[t + 1])
	# A wall along each open edge a → b of the front: b, a, a' and b, a', b'.
	var next := count * 2
	for edge in edges:
		if edges[edge] <= 0:
			continue
		var ends: PackedInt32Array = corner_of[edge]
		var a := ends[0]
		var b := ends[1]
		var a_back := vertices[a] - point_normal[key_of[a]].normalized() * THICKNESS
		var b_back := vertices[b] - point_normal[key_of[b]].normalized() * THICKNESS
		var wall := (vertices[a] - vertices[b]).cross(a_back - vertices[b]).normalized()
		for spot: Vector3 in [vertices[b], vertices[a], a_back, b_back]:
			tool.set_normal(wall)
			if not uvs.is_empty():
				tool.set_uv(uvs[b] if spot == vertices[b] or spot == b_back else uvs[a])
			tool.add_vertex(spot)
		for corner: int in [0, 1, 2, 0, 2, 3]:
			tool.add_index(next + corner)
		next += 4
	return tool.commit_to_arrays()
