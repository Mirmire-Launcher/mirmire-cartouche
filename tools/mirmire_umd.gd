# SPDX-License-Identifier: GPL-3.0-or-later
extends SceneTree
## Makes the PSP's UMD (Mirmire Cartouche) from the UMD of "Psp Handheld Console" by Ryan_Nein (CC-BY-4.0,
## https://sketchfab.com/3d-models/psp-handheld-console-db8c125291314639a32de8dfb66b33fa): its case, the case's clear
## plastic, the disc and the disc's label, stood up facing +Z, centred, 64 mm wide in this app's units (100 mm a unit),
## the label's UVs laid flat across its front (0 to 1 from its top left) so a game's picture covers it.
## Run once, from a copy inside app/, with the download imported at res://tmp_psp/psp.glb:
##   cp tools/mirmire_umd.gd app/umd_tmp.gd && Godot --headless --path app --script res://umd_tmp.gd; rm app/umd_tmp.gd
## It writes res://carousel/media/psp_umd/psp_umd_{shell,clear,disc,label}.res and prints the label's place on the front.
## Then tools/mirmire_close_mesh.gd closes each part, as every shipped medium must be closed.

const SOURCE := "res://tmp_psp/psp.glb"
const OUT := "res://carousel/media/psp_umd/psp_umd_%s.res"
const WIDTH := 0.64
## The parts by their mesh's name in the download, and the part each makes.
const PARTS := {"UmdCase_Umd_0": "shell", "UmdCase_UmdClear_0": "clear", "UmdDisc_Disc_0": "disc", "UmdDisc_DiscLabel_0": "label"}


func _init() -> void:
	var scene := (load(SOURCE) as PackedScene).instantiate() as Node3D
	var group := scene.find_child("Empty", true, false) as Node3D
	# In the group's own space the UMD lies flat, its label towards -Y, its round end towards +Z: stood up, that is
	# -90 degrees about X.
	var stand := Basis(Vector3.RIGHT, deg_to_rad(-90.0))
	var meshes := {}
	var box := AABB()
	var first := true
	for found: Node in group.find_children("*", "MeshInstance3D", true, false):
		var part: MeshInstance3D = found
		if not PARTS.has(String(part.name)):
			continue
		var placed := Transform3D(stand, Vector3.ZERO) * _in_group(group, part)
		meshes[PARTS[String(part.name)]] = [part, placed]
		var bounds := placed * part.get_aabb()
		box = bounds if first else box.merge(bounds)
		first = false
	var fit := WIDTH / box.size.x
	var centre := box.get_center()
	var label_box := AABB()
	for key: String in meshes:
		var part: MeshInstance3D = meshes[key][0]
		var placed: Transform3D = meshes[key][1]
		var whole := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * fit), -centre * fit) * placed
		var mesh := _baked(part.mesh, whole, key == "label")
		if key == "label":
			label_box = mesh.get_aabb()
		else:
			mesh.surface_set_material(0, _material(key))
		var error := ResourceSaver.save(mesh, OUT % key)
		print("%s: %s" % [OUT % key, error_string(error)])
	var front := Vector2(box.size.x, box.size.y) * fit
	var top := front.y / 2.0
	print("front %.4f x %.4f, proportion %.3f; label left %.3f top %.3f width %.3f height %.3f" % [front.x, front.y,
		front.x / front.y, (label_box.position.x + front.x / 2.0) / front.x, (top - label_box.end.y) / front.y,
		label_box.size.x / front.x, label_box.size.y / front.y])
	quit()


## [param node]'s transform in [param group]'s space.
static func _in_group(group: Node3D, node: Node3D) -> Transform3D:
	var placed := Transform3D.IDENTITY
	var at: Node = node
	while at != group:
		placed = (at as Node3D).transform * placed
		at = at.get_parent()
	return placed


## [param source] moved by [param placed], indexed; [param mapped], its UVs laid flat across its front.
static func _baked(source: Mesh, placed: Transform3D, mapped: bool) -> ArrayMesh:
	var arrays := source.surface_get_arrays(0)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var moved := PackedVector3Array()
	var turned := PackedVector3Array()
	for i in points.size():
		moved.append(placed * points[i])
		turned.append((placed.basis * normals[i]).normalized())
	arrays[Mesh.ARRAY_VERTEX] = moved
	arrays[Mesh.ARRAY_NORMAL] = turned
	arrays[Mesh.ARRAY_TANGENT] = null
	if mapped:
		var bounds := AABB(moved[0], Vector3.ZERO)
		for point in moved:
			bounds = bounds.expand(point)
		var uvs := PackedVector2Array()
		for point in moved:
			uvs.append(Vector2((point.x - bounds.position.x) / bounds.size.x, (bounds.end.y - point.y) / bounds.size.y))
		arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if mapped:
		var tool := SurfaceTool.new()
		tool.create_from(mesh, 0)
		tool.generate_tangents()
		return tool.commit()
	return mesh


## The case's grey plastic with its UMD lettering, its clear part, and the disc's silver.
static func _material(key: String) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	match key:
		"shell":
			material.albedo_texture = load("res://carousel/media/psp_umd/umd_case.png")
			material.albedo_color = Color(0.55, 0.56, 0.6)
			material.roughness = 0.35
			material.metallic = 0.1
		"clear":
			material.albedo_texture = load("res://carousel/media/psp_umd/umd_clear.png")
			material.albedo_color = Color(0.9, 0.92, 0.97, 0.08)
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.roughness = 0.08
		"disc":
			material.albedo_texture = load("res://carousel/media/psp_umd/umd_disc.png")
			material.albedo_color = Color(0.9, 0.9, 0.93)
			material.metallic = 0.8
			material.roughness = 0.25
	return material
