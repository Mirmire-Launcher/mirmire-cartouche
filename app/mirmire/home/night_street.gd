# SPDX-License-Identifier: GPL-3.0-or-later
class_name NightStreet
extends SubViewportContainer
## A backdrop of Mirmire Cartouche's: a street at night, "A Mysterious Adventure" by Diosmel
## (CC-BY 4.0, mirmire/home/backdrops), seen as its author shows it, from one annotation's camera to the next. Drawn in
## its own world, with its own camera (the author's field of view), sky and lights, so whatever is drawn over it keeps
## its own. It shows when Mirmire asks for it ([method wanted]).
##
## The home flies its camera between two of its [constant VIEWS] as its row moves ([method look]); the consoles and
## games screens step it along [constant ORDER], one view a step, round and round ([method step]).

const _MODEL := "res://mirmire/home/backdrops/adventure.glb"
const _FOV := 45.0
## Each view: where the camera is and the point it looks at, in the scene's own units (Sketchfab's, turned Y-up), by
## the home's card it goes with. Parts 1 to 5 are the author's annotations; the others are views of the same street.
const VIEWS: Dictionary[StringName, Array] = {
	&"widgets": [Vector3(400, -85, -5), Vector3(0, -85, -5)],
	&"continue": [Vector3(238.92, -143.07, -299.24), Vector3(-57.32, -129.82, -82.09)],
	&"consoles": [Vector3(-349.90, -107.81, -295.78), Vector3(-149.18, -217.36, -104.43)],
	&"all": [Vector3(-124.80, -104.95, 355.69), Vector3(-162.06, -148.60, 97.43)],
	&"recent": [Vector3(-67.14, 263.45, 301.20), Vector3(-38.06, 152.72, 44.54)],
	&"favorites": [Vector3(55.31, -145.93, 342.75), Vector3(49.82, -184.81, 0.17)],
	&"apps": [Vector3(-560, -110, -10), Vector3(0, -120, -10)],
	&"settings": [Vector3(60, -120, -520), Vector3(40, -150, 0)],
	&"exit": [Vector3(760, 330, 620), Vector3(0, -60, 0)],
}
## The views in the order the consoles and games screens step through them: the street's own tour first (the alley,
## then the author's parts 1 to 5), then the other views.
const ORDER: Array[StringName] = [&"widgets", &"continue", &"consoles", &"all", &"recent", &"favorites", &"apps",
	&"settings", &"exit"]
## How long one step from a view to the next takes there, in seconds.
const STEP_S := 0.9
## Night, as the author lit it: a sky almost black (night blue), the scene's own colours and baked fill this dark, its
## lit windows and bulbs this much brighter.
const _SKY := Color(0.012, 0.016, 0.03)
const _DIM := 0.42
const _GLOW := 2.0
## The street lamps' glass, in the scene's own units; how bright they are and how far they light.
const _LAMPS: Array[Vector3] = [
	Vector3(145, -60, 223), Vector3(-171, -60, -273), Vector3(139, 26, -105), Vector3(134, -80, 128),
	Vector3(-40, -165, 10), Vector3(-140, -3, 128), Vector3(17, -150, -175), Vector3(10, -60, 0),
]
const _LAMP_ENERGY := 4.0
const _LAMP_RANGE := 200.0
## The pools of lamplight on the ground: where each spot light shines from and onto.
const _POOLS: Array[Array] = [
	[Vector3(330, 120, -5), Vector3(0, -190, -5)],
	[Vector3(-160, 150, -100), Vector3(-120, -205, -80)],
	[Vector3(180, 140, -120), Vector3(110, -196, -120)],
	[Vector3(60, 140, 300), Vector3(50, -196, 200)],
	[Vector3(-150, 120, 320), Vector3(-160, -196, 190)],
]
const _POOL_ENERGY := 18.0

## How long one breath of the soft shade (and the home's text shadows) takes, in seconds: it fades out completely and
## back, easing in and out.
const PULSE_S := 4.0
## The shade behind the item chosen, as a share of the screen's height, and how dark it gets.
const SHADE_SIZE := 1.2
const SHADE_DARK := 0.8

## Where the shade goes behind the item chosen, as a share of the street's size; (-1, -1) for none ([member shade]
## draws it).
var shade_at := Vector2(-1, -1)
## How big the shade is there, against the home's (a console or a game covers more of it).
var shade_scale := 1.0
## Whether [method step] moves the camera (the consoles and games screens); the home moves it itself ([method look]).
var stepping := false
var _camera: Camera3D
var _shade: Control
var _time := 0.0
static var _shade_texture: Texture2D
## Where [method step] has the camera along [constant ORDER], in views, and where it goes.
var _place := 0.0
var _target := 0.0


## Whether the street is wanted: Mirmire opened the app asking for it (debug runs: `-- --night=1`).
static func wanted(android: AndroidServices) -> bool:
	if Diagnostics.argument("night") == "1":
		return true
	return android != null and android.mirmire_night_street()


## The street, or null when its model is missing.
static func make() -> NightStreet:
	var scene := load(_MODEL) as PackedScene
	if scene == null:
		return null
	var street := NightStreet.new()
	street._build(scene)
	return street


func _build(scene: PackedScene) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_2X
	add_child(viewport)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = _SKY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.45, 0.5, 0.7)
	environment.ambient_light_energy = 0.22
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.glow_enabled = true
	environment.glow_intensity = 0.8
	environment.glow_bloom = 0.08
	environment.glow_hdr_threshold = 0.9
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	var world := WorldEnvironment.new()
	world.environment = environment
	viewport.add_child(world)
	var model := scene.instantiate() as Node3D
	viewport.add_child(model)
	_night(model)
	_lights(viewport)
	for found: Node in model.find_children("*", "AnimationPlayer", true, false):
		var player := found as AnimationPlayer
		var take := player.get_animation(&"Take 001")
		if take:
			take.loop_mode = Animation.LOOP_LINEAR
			player.play(&"Take 001")
	_camera = Camera3D.new()
	_camera.fov = _FOV
	_camera.near = 2.0
	_camera.far = 5000.0
	viewport.add_child(_camera)
	var first: Array = VIEWS[ORDER[0]]
	look(first, first, 0.0)


## The camera [param way] (0 to 1, eased in and out) from view [param from] to view [param to] (of [constant VIEWS]).
func look(from: Array, to: Array, way: float) -> void:
	var eased := smoothstep(0.0, 1.0, clampf(way, 0.0, 1.0))
	var from_eye: Vector3 = from[0]
	var from_at: Vector3 = from[1]
	var to_eye: Vector3 = to[0]
	var to_at: Vector3 = to[1]
	_camera.look_at_from_position(from_eye.lerp(to_eye, eased), from_at.lerp(to_at, eased), Vector3.UP)


## The soft round shade, black in the middle fading out to its edge.
static func shade_texture() -> Texture2D:
	if _shade_texture == null:
		var image := Image.create_empty(128, 128, false, Image.FORMAT_RGBA8)
		for y in 128:
			for x in 128:
				var from_middle := Vector2(x - 63.5, y - 63.5).length() / 64.0
				image.set_pixel(x, y, Color(0, 0, 0, 1.0 - smoothstep(0.15, 1.0, from_middle)))
		_shade_texture = ImageTexture.create_from_image(image)
	return _shade_texture


## Where a breath is at [param time] (seconds): 0 (gone) to 1, easing in and out.
static func pulse(time: float) -> float:
	return 0.5 - 0.5 * cos(time * TAU / PULSE_S)


## The shade, breathing, [param strength] (0 to 1) dark, [param tall] px tall, centred on [param at] in [param canvas].
static func draw_shade(canvas: CanvasItem, at: Vector2, tall: float, time: float, strength := 1.0,
		scale_by := 1.0) -> void:
	var breath := pulse(time)
	var wide := tall * SHADE_SIZE * scale_by * lerpf(0.94, 1.06, breath)
	var high := wide * 0.8
	canvas.draw_texture_rect(shade_texture(), Rect2(at.x - wide / 2.0, at.y - high / 2.0, wide, high), false,
		Color(1, 1, 1, SHADE_DARK * breath * strength))


## The layer drawing the shade at [member shade_at], to put just over the street (a SubViewportContainer draws no
## other child over its view).
func shade_layer() -> Control:
	if _shade == null:
		_shade = Control.new()
		_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
		_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_shade.draw.connect(func() -> void:
			if shade_at.x >= 0.0:
				draw_shade(_shade, shade_at * _shade.size, _shade.size.y, _time, 1.0, shade_scale))
	return _shade


## One view on along [constant ORDER] towards [param direction] (-1 or 1), round from the last to the first.
func step(direction: int) -> void:
	_target += signi(direction)
	set_process(true)


func _process(delta: float) -> void:
	_time += delta
	if _shade:
		# Shown with the street, a hidden layer drawing nothing.
		_shade.visible = visible
		_shade.queue_redraw()
	if not stepping:
		return
	_place = move_toward(_place, _target, delta / STEP_S * maxf(1.0, absf(_target - _place)))
	var from := floori(_place)
	var count := ORDER.size()
	var a: Array = VIEWS[ORDER[posmod(from, count)]]
	var b: Array = VIEWS[ORDER[posmod(from + 1, count)]]
	look(a, b, _place - from)



## The scene at night: its colours and the fill light its author baked into them darkened, and what it lights itself
## (windows, interiors, bulbs) brighter, so they glow.
static func _night(model: Node3D) -> void:
	var darkened := {}
	for found: Node in model.find_children("*", "MeshInstance3D", true, false):
		var part := found as MeshInstance3D
		for i in part.mesh.get_surface_count():
			var own := part.get_active_material(i) as BaseMaterial3D
			if own == null:
				continue
			var dark: BaseMaterial3D = darkened.get(own)
			if dark == null:
				dark = own.duplicate() as BaseMaterial3D
				dark.albedo_color = Color(dark.albedo_color * _DIM, dark.albedo_color.a)
				# Most materials glow faintly with their own colours, a fill light the author baked in: dimmed as the
				# colours are. The lights (windows, interiors, bulbs) glow brighter or have no picture to glow with.
				if dark.emission_enabled:
					if dark.emission_energy_multiplier > 1.0 or dark.emission_texture == null:
						dark.emission_energy_multiplier *= _GLOW
					else:
						dark.emission = dark.emission * _DIM
				darkened[own] = dark
			part.set_surface_override_material(i, dark)


## The street's lights, as its author has them, in the scene's own units: moonlight from above, warm light pooled on
## the ground and a warm light at each street lamp.
static func _lights(viewport: SubViewport) -> void:
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-55, 60, 0)
	moon.light_color = Color(0.55, 0.65, 1.0)
	moon.light_energy = 0.4
	viewport.add_child(moon)
	# Warm light pooled on the ground, as from the lamps overhead: down the alley, at the tram stop's benches, at the
	# corner by the tracks, before the kiosk and before the bar.
	for spot_at: Array in _POOLS:
		var spot := SpotLight3D.new()
		var from: Vector3 = spot_at[0]
		var toward: Vector3 = spot_at[1]
		spot.look_at_from_position(from, toward)
		spot.light_color = Color(1.0, 0.56, 0.26)
		spot.light_energy = _POOL_ENERGY
		spot.spot_range = 600.0
		spot.spot_angle = 32.0
		spot.spot_attenuation = 0.2
		spot.spot_angle_attenuation = 1.6
		viewport.add_child(spot)
	# The street lamps, warm pools of light round each, where their glass is: by the kiosk, at the tram stop, down the
	# alley, by the bar and at the corner by the tracks. Eight at most: the mobile renderer lights a mesh with eight.
	for lamp: Vector3 in _LAMPS:
		var warm := OmniLight3D.new()
		warm.position = lamp
		warm.light_color = Color(1.0, 0.66, 0.38)
		warm.light_energy = _LAMP_ENERGY
		warm.omni_range = _LAMP_RANGE
		warm.omni_attenuation = 0.3
		viewport.add_child(warm)
