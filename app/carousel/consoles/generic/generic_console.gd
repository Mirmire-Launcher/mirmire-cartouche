# SPDX-License-Identifier: GPL-3.0-or-later
class_name GenericConsole
extends ConsoleModel
## The console shown for a platform Mirmire plays that has no model of its own ([method Appearance.add_generic]).
## A platform with a [method style_of] gets a console of its own shape and colours with its name printed on the lid; any
## other gets the plain console with the platform's icon, as Mirmire draws it, on its lid (the plugin copies the icons
## to [constant ICONS] when Mirmire opens the app; without one the lid stays plain). [member Node.name] is the
## platform's id, as [method Appearance.console] names the model.

const ICONS := "user://mirmire/icons/%s.png"

## A console's look: its size in millimetres (width, height, depth), the body's and the lid's colours, the name
## printed on the lid, its ink and outline (none when clear), and whether it is a handheld lying on its back.
class Style:
	var size: Vector3
	var body: Color
	var lid: Color
	var logo: String
	var ink: Color
	var outline: Color
	var handheld: bool

	func _init(s: Vector3, b: Color, l: Color, text: String, i: Color, o := Color(0, 0, 0, 0), hand := false) -> void:
		size = s; body = b; lid = l; logo = text; ink = i; outline = o; handheld = hand


## The platforms with a look of their own.
static func style_of(platform: String) -> Style:
	var white := Color(0.86, 0.85, 0.82)
	var white_lid := Color(0.93, 0.92, 0.9)
	var grey_ink := Color(0.3, 0.32, 0.36)
	match platform:
		"segacd":
			return Style.new(Vector3(300, 78, 220), Color(0.09, 0.09, 0.1), Color(0.13, 0.13, 0.14), "SEGA CD",
				Color(0.93, 0.93, 0.95), Color(0.75, 0.08, 0.1))
		"tg16":
			return Style.new(Vector3(140, 38, 140), white, white_lid, "PC Engine", grey_ink)
		"mirmire_pcenginecd":
			return Style.new(Vector3(260, 56, 150), white, white_lid, "CD-ROM²", grey_ink)
		"mirmire_sega32x":
			return Style.new(Vector3(190, 105, 125), Color(0.08, 0.08, 0.09), Color(0.12, 0.12, 0.13), "32X",
				Color(0.95, 0.95, 0.96), Color(0.8, 0.07, 0.09))
		"mirmire_atari7800":
			return Style.new(Vector3(320, 70, 235), Color(0.07, 0.07, 0.07), Color(0.7, 0.71, 0.73), "ATARI 7800",
				Color(0.06, 0.06, 0.07))
		"mirmire_wonderswan":
			return Style.new(Vector3(121, 24, 74), Color(0.74, 0.75, 0.76), Color(0.8, 0.81, 0.82), "WonderSwan",
				Color(0.2, 0.22, 0.28), Color(0, 0, 0, 0), true)
		"mirmire_wonderswancolor":
			return Style.new(Vector3(128, 24, 75), Color(0.55, 0.68, 0.84), Color(0.66, 0.77, 0.9), "WonderSwan Color",
				Color(0.12, 0.16, 0.3), Color(0, 0, 0, 0), true)
	return null

const _LID_MM := 6.0
const _UNIT := 0.01


func _ready() -> void:
	var style := style_of(String(name))
	if style:
		_style(style)
	else:
		_show_icon()
	super()


## Shapes the plain console to [param style]: resized, recoloured, its name on the lid, the seat over its slot.
func _style(style: Style) -> void:
	var size := style.size * _UNIT
	var lid_h := _LID_MM * _UNIT
	var handheld := style.handheld
	var body := get_node("Model/body") as MeshInstance3D
	var lid := get_node("Model/lid") as MeshInstance3D
	var slot := get_node("Model/slot") as MeshInstance3D
	var light := get_node("Model/power_light") as MeshInstance3D
	(get_node("Model/icon") as Node3D).visible = false
	var body_h := size.y - lid_h
	body.mesh = _box(body.mesh, Vector3(size.x, body_h, size.z), style.body)
	body.position = Vector3(0, body_h / 2, 0)
	var inset := minf(0.08, size.x * 0.04)
	lid.mesh = _box(lid.mesh, Vector3(size.x - inset * 2, lid_h, size.z - inset * 2), style.lid)
	lid.position = Vector3(0, body_h + lid_h / 2, 0)
	var top := size.y
	# The slot across the back of the lid, as wide as most media are.
	var slot_z := -size.z * 0.3
	slot.mesh = _box(slot.mesh, Vector3(minf(size.x * 0.6, 1.1), 0.02, minf(size.z * 0.12, 0.14)), null)
	slot.position = Vector3(0, top + 0.005, slot_z)
	light.position = Vector3(size.x * 0.4, body_h * 0.6, size.z / 2 + 0.005)
	var logo_z := size.z * 0.22
	if handheld:
		# Lying on its back: the screen in the middle of the lid, the name in front of it.
		var screen := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(size.x * 0.42, size.z * 0.5)
		var glass := StandardMaterial3D.new()
		glass.albedo_color = Color(0.03, 0.035, 0.04)
		glass.roughness = 0.08
		plane.material = glass
		screen.mesh = plane
		screen.position = Vector3(0, top + 0.002, -size.z * 0.04)
		get_node("Model").add_child(screen)
		slot_z = -size.z * 0.42
		slot.position.z = slot_z
		logo_z = size.z * 0.36
		light.position = Vector3(size.x * 0.36, top + 0.003, size.z * 0.3)
	_print_logo(style, Vector3(0, top + 0.003, logo_z), size.x * (0.55 if handheld else 0.8), size.z * (0.16 if handheld else 0.3))
	var seat_shape := shape.duplicate() as SeatShape
	seat_shape.seat_centre = Vector3(0, size.y / _UNIT + 2, slot_z / _UNIT)
	shape = seat_shape


## The platform's name printed flat on the lid at [param at], fitted in [param width] by [param depth].
func _print_logo(style: Style, at: Vector3, width: float, depth: float) -> void:
	var text := style.logo
	var label := Label3D.new()
	label.text = text
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Roboto", "Helvetica Neue", "Arial", "sans-serif"])
	font.font_weight = 800
	label.font = font
	label.font_size = 96
	label.outline_size = 0
	var outline := style.outline
	if outline.a > 0:
		label.outline_size = 14
		label.outline_modulate = outline
	label.modulate = style.ink
	label.shaded = true
	label.double_sided = false
	# A line of the font is about its size tall; a letter about 0.62 of that wide.
	var height := minf(depth, width / (0.62 * text.length()))
	label.pixel_size = height / label.font_size
	label.rotation_degrees = Vector3(-90, 0, 0)
	label.position = at
	label.name = &"logo"
	get_node("Model").add_child(label)


## A copy of [param mesh] (a box) at [param size], in [param colour] (its own colour kept for null).
static func _box(mesh: Mesh, size: Vector3, colour: Variant) -> BoxMesh:
	var box := mesh.duplicate() as BoxMesh
	box.size = size
	if colour != null:
		var material := (box.material as StandardMaterial3D).duplicate() as StandardMaterial3D
		material.albedo_color = colour
		box.material = material
	return box


func _show_icon() -> void:
	var path := ICONS % name
	if not FileAccess.file_exists(path):
		return
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		return
	var material := StandardMaterial3D.new()
	material.albedo_texture = ImageTexture.create_from_image(image)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.45
	var plate := get_node("Model/icon") as MeshInstance3D
	plate.material_override = material
