# SPDX-License-Identifier: GPL-3.0-or-later
class_name MirmireHome
extends CanvasLayer
## Mirmire Cartouche's home, as Mirmire's Big Picture has it (Mirmire Cartouche only): a row of 3D cards, Widgets,
## Continue, Consoles, All games, Recent, Favorites, Apps, Settings and Exit Big Picture, the one in the middle bigger
## and floating, its name and count under it. Consoles goes on to the carousel's consoles screen, whose Back comes
## back here; Continue plays the last game through Mirmire; Exit goes back to Mirmire, which leaves Big Picture; the
## others open Mirmire's own screens over Big Picture, and leaving them comes back here.
##
## Drawn over the carousel on its own layer: its own backdrop, clock and battery, and a bar along the bottom with the
## button hints, the player's RetroAchievements and the Mirmire and Cartouche logos side by side. Each card is the
## model `res://mirmire/home/models/<card>.glb` when there is one, a plain shape in the card's colour otherwise.

## The carousel's consoles screen is wanted: the home has hidden itself.
signal consoles_chosen

const MODELS := "res://mirmire/home/models/%s.glb"
const _BAR_ON_LIGHT := preload("res://mirmire/branding/bar_on_light.png")
const _BAR_ON_DARK := preload("res://mirmire/branding/bar_on_dark.png")
const _HINT_ROW := preload("res://studio/hint_row.tscn")
const _GLASS_SHADER := preload("res://mirmire/home/glass.gdshader")
const _PROFILES := "res://data/platforms/profiles.json"
## Cards side by side this far apart, in world units; the one in the middle this big, the others smaller.
const _SPACING := 1.85
const _CHOSEN := 1.4
const _OTHERS := 0.72
## How long a step along the row takes, and how high the chosen card floats.
const _STEP_S := 0.18
const _BOB := 0.05
const _TURN_DEGREES := 18.0
const _LOGO_PX := 48.0
const _AVATAR_PX := 44.0
## Each model as downloaded, set right: turned about Y then tilted about X (degrees) to face the camera, and the parts
## left out (a cable, a glass ball), by their node's name.
const _FIXES: Dictionary[StringName, Array] = {
	&"widgets": [0.0, 0.0, []],
	&"consoles": [0.0, 0.0, []],
	&"all": [0.0, 55.0, ["Ground_Plane"]],
	&"recent": [0.0, 0.0, []],
	&"favorites": [0.0, 0.0, []],
	&"settings": [0.0, 90.0, []],
	&"exit": [-90.0, 0.0, []],
}

## A card: its key (also its model's name), its title, the line under it and its colour as a plain shape.
class Card:
	var key: StringName
	var title: String
	var detail := ""
	var colour: Color
	var holder: Node3D
	## Its model's animations, played while it is the card chosen.
	var players: Array[AnimationPlayer] = []

	func _init(k: StringName, t: String, c: Color) -> void:
		key = k; title = t; colour = c


var android: AndroidServices
var _cards: Array[Card] = []
var _index := 0
var _scroll := 0.0
var _time := 0.0
var _home: Dictionary = {}
var _root: Control
var _row: Node3D
var _texts: Control
var _bar: Control
var _clock: StudioPill
var _battery: BatteryChip
var _avatar: Texture2D
## A finger down on the row: where it went down, the row's place then, and whether it has moved far enough to be a
## swipe; -1 for none.
var _finger_x := -1.0
var _finger_scroll := 0.0
var _finger_down := Vector2.ZERO
var _swiping := false
var _swipe_speed := 0.0
## A finger turning the chosen model, as a model viewer does: whether it went down on the model, whether it is turning
## it, the model's turn (degrees about Y, then X) and how fast it keeps turning once let go.
var _on_model := false
var _orbiting := false
var _orbit := Vector2.ZERO
var _orbit_speed := Vector2.ZERO
## How far a finger turns the model, in degrees per px, and how fast a let-go turn slows (per second).
const _ORBIT_DEGREES_PX := 0.45
const _ORBIT_DAMPING := 3.0
## Left alone this long, in seconds, a turned model comes slowly back to its pose, at this rate (per second).
const _ORBIT_REST_S := 1.5
const _ORBIT_RETURN := 1.2
var _orbit_idle := 0.0
## A finger moving less than this, in px, is a tap; a swipe moves the row one card per this share of the width.
const _TAP_PX := 24.0
const _CARD_WIDTH_SHARE := 0.17


func _ready() -> void:
	layer = 1
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var backdrop := Cyclorama.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(backdrop)
	_root.add_child(_stage())
	_texts = Control.new()
	_texts.set_anchors_preset(Control.PRESET_FULL_RECT)
	_texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_texts.draw.connect(_draw_texts)
	_root.add_child(_texts)
	_root.add_child(_top_bar())
	_root.add_child(_hints())
	_bar = Control.new()
	_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.draw.connect(_draw_bar)
	_root.add_child(_bar)
	_root.gui_input.connect(_on_touch)
	visible = false
	set_process(false)


## Shows the home, its counts, game to continue and trophies read again from Mirmire.
func open() -> void:
	_home = android.mirmire_home() if android else {}
	var ra: Dictionary = _home.get("achievements", {})
	_avatar = _texture(str(ra.get("avatar", "")))
	_build_cards()
	visible = true
	set_process(true)
	_texts.queue_redraw()
	_bar.queue_redraw()
	_clock.text = Time.get_time_string_from_system().left(5)
	Diagnostics.trace("home", "open: %d cards, continue %s" % [_cards.size(), _home.has("continue")])


func is_open() -> bool:
	return visible


func _process(delta: float) -> void:
	_time += delta
	# A finger swiping holds the row where it puts it; then it settles on the card chosen.
	if not _swiping:
		_scroll = move_toward(_scroll, float(_index), delta / _STEP_S * maxf(1.0, absf(_scroll - _index)))
	for i in _cards.size():
		var holder := _cards[i].holder
		var shift := float(i) - _scroll
		var near := clampf(1.0 - absf(shift), 0.0, 1.0)
		var size := lerpf(_OTHERS, _CHOSEN, near)
		holder.position = Vector3(shift * _SPACING, sin(_time * 1.6) * _BOB * near, -absf(shift) * 0.35)
		holder.scale = Vector3.ONE * size
		holder.rotation_degrees.y = sin(_time * 0.7) * _TURN_DEGREES * near - shift * 12.0
		holder.visible = absf(shift) < 6.0
	# The chosen model turned by a finger, carrying on a little once let go; the others ease back to their pose.
	if _orbiting:
		_orbit_idle = 0.0
	else:
		_orbit += _orbit_speed * delta
		_orbit_speed = _orbit_speed.lerp(Vector2.ZERO, clampf(delta * _ORBIT_DAMPING, 0.0, 1.0))
		_orbit_idle += delta
		# Left alone, it turns slowly back to its pose, the short way round, however far it was turned.
		if _orbit_idle > _ORBIT_REST_S and _orbit_speed.length() < 5.0:
			_orbit = Vector2(wrapf(_orbit.x, -180.0, 180.0), wrapf(_orbit.y, -180.0, 180.0))
			_orbit = _orbit.lerp(Vector2.ZERO, clampf(delta * _ORBIT_RETURN, 0.0, 1.0))
	for i in _cards.size():
		var model := _cards[i].holder.get_child(0) as Node3D
		var turned := Vector3(_orbit.y, _orbit.x, 0.0) if i == _index else Vector3.ZERO
		model.rotation_degrees = model.rotation_degrees.lerp(turned, 1.0 if i == _index else clampf(delta * 6.0, 0.0, 1.0))
	if int(_time * 2.0) != int((_time - delta) * 2.0):
		_clock.text = Time.get_time_string_from_system().left(5)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_left") or event.is_action_pressed(&"carousel_left"):
		_step(-1)
	elif event.is_action_pressed(&"ui_right") or event.is_action_pressed(&"carousel_right"):
		_step(1)
	elif event.is_action_pressed(&"ui_accept"):
		_choose(_cards[_index].key)
	elif event.is_action_pressed(&"screen_back"):
		# Back (B, or Android's swipe from the edge) goes to Exit first; Back there leaves, so a stray swipe never does.
		if _cards[_index].key == &"exit":
			_choose(&"exit")
		else:
			_step(_cards.size() - 1 - _index)
	elif event.is_action_pressed(&"open_settings"):
		_choose(&"settings")
	elif event is InputEventScreenTouch or event is InputEventScreenDrag or event is InputEventMouse:
		return # Taps go to the home's own control, over the carousel's.
	# Every other press is the home's too: the carousel under it must not act on it.
	get_viewport().set_input_as_handled()


## A tap: on the card in the middle, chooses it; beside it, brings the one tapped to the middle.
func _on_touch(event: InputEvent) -> void:
	var card_px := maxf(1.0, _root.size.x * _CARD_WIDTH_SHARE)
	var motion := event as InputEventMouseMotion
	# A finger down on the chosen model turns it, any way; anywhere else, it swipes along the row.
	if motion and _finger_x >= 0.0 and _on_model:
		if not _orbiting and motion.position.distance_to(_finger_down) > _TAP_PX:
			_orbiting = true
		if _orbiting:
			var turn := motion.relative * _ORBIT_DEGREES_PX
			_orbit += turn
			_orbit_speed = _orbit_speed.lerp(turn / maxf(get_process_delta_time(), 0.001), 0.5)
		return
	if motion and _finger_x >= 0.0:
		if not _swiping and absf(motion.position.x - _finger_x) > _TAP_PX:
			_swiping = true
		if _swiping:
			var last := _scroll
			_scroll = clampf(_finger_scroll - (motion.position.x - _finger_x) / card_px, -0.4, _cards.size() - 0.6)
			_swipe_speed = lerpf(_swipe_speed, (_scroll - last) / maxf(get_process_delta_time(), 0.001), 0.5)
			_texts.queue_redraw()
		return
	var press := event as InputEventMouseButton
	if press == null or press.button_index != MOUSE_BUTTON_LEFT:
		return
	if press.pressed:
		# The bottom bar is the hints' own.
		if press.position.y > _root.size.y * 0.85:
			return
		_finger_x = press.position.x
		_finger_down = press.position
		_finger_scroll = _scroll
		_swiping = false
		_swipe_speed = 0.0
		_orbiting = false
		_orbit_speed = Vector2.ZERO
		var size := _root.size
		_on_model = absf(press.position.x - size.x / 2.0) < card_px * 0.8 and press.position.y > size.y * 0.12 \
			and press.position.y < size.y * 0.66
		return
	if _finger_x < 0.0:
		return
	_finger_x = -1.0
	if _orbiting:
		_orbiting = false
		return
	if _swiping:
		_swiping = false
		# Where the row was let go, carried on a little by a flick, and at least one card for a flick.
		var landing := _scroll + clampf(_swipe_speed * 0.12, -2.0, 2.0)
		var to := clampi(roundi(landing), 0, _cards.size() - 1)
		if to == _index and absf(_swipe_speed) > 3.0:
			to = clampi(_index + signi(roundi(_swipe_speed)), 0, _cards.size() - 1)
		_step(to - _index)
		return
	# A tap: the card in the middle is chosen; one beside it comes to the middle.
	var from_middle := (press.position.x - _root.size.x / 2.0) / card_px
	if absf(from_middle) < 0.6:
		_choose(_cards[_index].key)
	else:
		var places := clampi(roundi(from_middle), -3, 3)
		_step(places if places != 0 else (1 if from_middle > 0.0 else -1))


func _step(way: int) -> void:
	var to := clampi(_index + way, 0, _cards.size() - 1)
	if to == _index:
		return
	_index = to
	_orbit = Vector2.ZERO
	_orbit_speed = Vector2.ZERO
	_play_chosen()
	Sounds.play(SoundEffects.Cue.MOVE)
	_texts.queue_redraw()


func _choose(key: StringName) -> void:
	Sounds.play(SoundEffects.Cue.SELECT)
	match key:
		&"consoles":
			_hide()
			consoles_chosen.emit()
		&"continue":
			var game: Dictionary = _home.get("continue", {})
			if game.has("game"):
				android.play_in_mirmire(str(game.game))
		&"exit":
			android.back_to_mirmire()
		&"settings", &"widgets", &"all", &"recent", &"favorites", &"apps":
			android.open_in_mirmire(String(key))
		&"achievements":
			android.open_in_mirmire("achievements")


func _hide() -> void:
	visible = false
	set_process(false)


## The cards, as Mirmire's Big Picture lists them; the one chosen before stays chosen.
func _build_cards() -> void:
	var chosen: StringName = _cards[_index].key if not _cards.is_empty() else &"consoles"
	# Debug runs open on a card with `-- --home_card=<card>`.
	if _cards.is_empty() and Diagnostics.argument("home_card") != "":
		chosen = StringName(Diagnostics.argument("home_card"))
	for card in _cards:
		card.holder.queue_free()
	_cards.clear()
	var add := func(key: StringName, title: String, colour: Color, detail := "") -> void:
		var card := Card.new(key, tr(title), colour)
		card.detail = detail
		_cards.append(card)
	add.call(&"widgets", "Widgets", Color(0.36, 0.62, 0.95), tr("Your home page"))
	var last: Dictionary = _home.get("continue", {})
	if last.has("game"):
		add.call(&"continue", "Continue", Color(0.3, 0.8, 0.45), str(last.get("title", "")))
	add.call(&"consoles", "Consoles", Color(0.55, 0.55, 0.6), _count(_home.get("consoles", 0), "console", "consoles"))
	add.call(&"all", "All games", Color(0.8, 0.6, 0.35), _count(_home.get("games", 0), "game", "games"))
	add.call(&"recent", "Recent", Color(0.95, 0.75, 0.3))
	var favorites := str(_home.get("favorites", 0)).to_int()
	add.call(&"favorites", "Favorites", Color(0.9, 0.3, 0.35), _count(favorites, "game", "games") if favorites > 0 else "")
	add.call(&"apps", "Apps", Color(0.45, 0.45, 0.85))
	add.call(&"settings", "Settings", Color(0.85, 0.7, 0.3))
	add.call(&"exit", "Exit Big Picture", Color(0.55, 0.38, 0.26), tr("Back to Mirmire"))
	_index = 0
	for i in _cards.size():
		if _cards[i].key == chosen:
			_index = i
	_scroll = float(_index)
	for card in _cards:
		card.holder = Node3D.new()
		card.holder.add_child(_model_of(card, last))
		_row.add_child(card.holder)
	_play_chosen()


func _count(value: Variant, one: String, many: String) -> String:
	var n := str(value).to_int()
	return "%d %s" % [n, tr(one if n == 1 else many)]


## The card's model, fitted in a unit box round its middle: its own, the last game's medium for Continue, or a shape.
func _model_of(card: Card, last: Dictionary) -> Node3D:
	var model: Node3D = null
	if ResourceLoader.exists(MODELS % card.key):
		var scene := load(MODELS % card.key) as PackedScene
		if scene:
			model = scene.instantiate() as Node3D
			_fix(model, card.key)
			card.players = _animations(model, card.key)
	# Continue without a model of its own: the last game's medium, its label on it.
	if model == null and card.key == &"continue":
		model = _medium_of(str(last.get("platform", "")), str(last.get("game", "")))
	if model == null:
		model = _shape(card)
	var fitted := Node3D.new()
	fitted.add_child(model)
	var box := _bounds(model)
	var longest := maxf(box.size.x, maxf(box.size.y, box.size.z))
	if longest > 0.0:
		var fit: float = _SIZES.get(card.key, 1.0) / longest
		model.scale *= fit
		model.position -= box.get_center() * fit
	return fitted


## Each card's model a little bigger or smaller than the others, as it reads best.
const _SIZES: Dictionary[StringName, float] = {
	&"widgets": 1.2, &"continue": 1.2, &"all": 1.2,
	&"recent": 0.85, &"apps": 0.85, &"settings": 0.85, &"exit": 0.85, &"favorites": 0.85,
}


## How much brighter a model's own glow is than its maker set: the steampunk clock's lit faces, which a pale backdrop
## would wash out.
const _GLOWS: Dictionary[StringName, float] = {
	&"recent": 4.0,
}


## The parts drawn as clear glass, by their node's name: the heart's glass ball, which its own material draws dark.
const _GLASS: Dictionary[StringName, Array] = {
	&"favorites": ["Marble"],
}


## Turns and tilts [param model] to face the camera and leaves out its parts not wanted ([constant _FIXES]).
static func _fix(model: Node3D, key: StringName) -> void:
	var fix: Array = _FIXES.get(key, [0.0, 0.0, []])
	var turn: float = fix[0]
	var tilt: float = fix[1]
	model.basis = Basis(Vector3.RIGHT, deg_to_rad(tilt)) * Basis(Vector3.UP, deg_to_rad(turn))
	var glass: Array = _GLASS.get(key, [])
	for found: Node in model.find_children("*", "MeshInstance3D", true, false):
		if found.get_parent().name in glass or found.name in glass:
			var clear := ShaderMaterial.new()
			clear.shader = _GLASS_SHADER
			(found as MeshInstance3D).material_override = clear
	var glow: float = _GLOWS.get(key, 0.0)
	if glow > 0.0:
		var brightened := {}
		for found: Node in model.find_children("*", "MeshInstance3D", true, false):
			var part := found as MeshInstance3D
			for i in part.mesh.get_surface_count():
				var material := part.get_active_material(i) as BaseMaterial3D
				if material == null or not material.emission_enabled:
					continue
				var bright: BaseMaterial3D = brightened.get(material)
				if bright == null:
					bright = material.duplicate() as BaseMaterial3D
					bright.emission_energy_multiplier = material.emission_energy_multiplier * glow
					brightened[material] = bright
				part.set_surface_override_material(i, bright)
	var left_out: Array = fix[2]
	for found: Node in model.find_children("*", "MeshInstance3D", true, false):
		for part: String in left_out:
			if found.get_parent().name == part or found.name == part:
				found.get_parent().remove_child(found)
				found.queue_free()
				break


## The models that move as their makers animated them: the take played over and over, or [code]&"own"[/code] for
## a model whose every object has its own take, `Object|ObjectAction`, each looped on its own (the toy desktop, exported
## from Blender with every action on every object).
const _ANIMATED: Dictionary[StringName, StringName] = {
	&"recent": &"Take 001",
	&"continue": &"Experiment",
	&"widgets": &"own",
}


## [param model]'s animations as [constant _ANIMATED] has them for [param key], set to loop, not playing yet.
static func _animations(model: Node3D, key: StringName) -> Array[AnimationPlayer]:
	var players: Array[AnimationPlayer] = []
	var take: StringName = _ANIMATED.get(key, &"")
	if take == &"":
		return players
	for found: Node in model.find_children("*", "AnimationPlayer", true, false):
		var source := found as AnimationPlayer
		for take_name: StringName in source.get_animation_list():
			var own := String(take_name).split("|")
			var wanted := take_name == take if take != &"own" else (own.size() == 2 and own[1].begins_with(own[0]))
			if not wanted:
				continue
			var animation := source.get_animation(take_name).duplicate() as Animation
			animation.loop_mode = Animation.LOOP_LINEAR
			var library := AnimationLibrary.new()
			library.add_animation(&"take", animation)
			var player := AnimationPlayer.new()
			player.add_animation_library(&"", library)
			# Beside the model's own player, so its tracks' paths are read from the same node.
			player.root_node = source.root_node
			source.get_parent().add_child(player)
			players.append(player)
	return players


## Plays the chosen card's animations and pauses the others'.
func _play_chosen() -> void:
	for i in _cards.size():
		for player in _cards[i].players:
			if i == _index:
				player.play(&"take")
			else:
				player.pause()


## A plain shape in the card's colour, until its model is in [constant MODELS].
static func _shape(card: Card) -> Node3D:
	var mesh: Mesh
	match card.key:
		&"settings":
			var torus := TorusMesh.new()
			torus.inner_radius = 0.25
			torus.outer_radius = 0.5
			mesh = torus
		&"favorites", &"recent":
			var sphere := SphereMesh.new()
			sphere.radius = 0.5
			sphere.height = 1.0
			mesh = sphere
		_:
			var box := BoxMesh.new()
			box.size = {&"widgets": Vector3(1.0, 0.7, 0.1), &"apps": Vector3(0.5, 1.0, 0.08),
				&"exit": Vector3(0.55, 1.0, 0.1), &"all": Vector3(0.8, 1.0, 0.35)}.get(card.key, Vector3(1.0, 0.45, 0.6))
			mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = card.colour
	material.roughness = 0.5
	mesh.surface_set_material(0, material)
	var shape := MeshInstance3D.new()
	shape.mesh = mesh
	return shape


## The last game's medium as its shelf shows it, its label on it when the app has kept one.
func _medium_of(platform: String, game_id: String) -> Node3D:
	var medium := "gba_cart"
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_PROFILES))
	var profiles: Dictionary = parsed if parsed is Dictionary else {}
	if profiles.has(platform):
		var profile: Dictionary = profiles[platform]
		var media: Variant = profile.get("medium", {})
		var defaults: Dictionary = media if media is Dictionary else {}
		medium = str(defaults.get("default", medium))
	var manifest_path := "res://carousel/media/%s/medium.tres" % medium
	if not ResourceLoader.exists(manifest_path):
		return null
	var manifest := load(manifest_path) as MediumManifest
	var scene := load(manifest.scene) as PackedScene
	if scene == null:
		return null
	var model := scene.instantiate() as Node3D
	model.scale = Vector3.ONE
	var label := model.get_node_or_null(^"Label") as MeshInstance3D
	var art := "user://art/%s.jpg" % game_id.sha1_text()
	if label and FileAccess.file_exists(art):
		var image := Image.load_from_file(art)
		var material := label.get_surface_override_material(0)
		if image and material is ShaderMaterial:
			var own := (material as ShaderMaterial).duplicate() as ShaderMaterial
			own.set_shader_parameter(&"label_texture", ImageTexture.create_from_image(image))
			own.set_shader_parameter(&"has_label", true)
			label.set_surface_override_material(0, own)
	return model


static func _bounds(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for found: Node in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := found as MeshInstance3D
		var part := _relative(node, mesh) * mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box


## [param node]'s transform in [param root]'s space, without the scene tree.
static func _relative(root: Node3D, node: Node3D) -> Transform3D:
	var placed := Transform3D.IDENTITY
	var at: Node = node
	while at != null and at != root:
		if at is Node3D:
			placed = (at as Node3D).transform * placed
		at = at.get_parent()
	return root.transform * placed


## The 3D row: its own world, lit as the studio is, seen from the front a little above.
func _stage() -> Control:
	var container := SubViewportContainer.new()
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var viewport := SubViewport.new()
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	container.add_child(viewport)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.8, 0.82, 0.86)
	environment.ambient_light_energy = 0.7
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# What glows in a model (the steampunk clock's lit parts) glows here too, as in a model viewer.
	environment.glow_enabled = true
	environment.glow_intensity = 0.9
	environment.glow_strength = 1.0
	environment.glow_bloom = 0.05
	environment.glow_hdr_threshold = 0.85
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	var world := WorldEnvironment.new()
	world.environment = environment
	viewport.add_child(world)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 25, 0)
	key.light_energy = 1.4
	viewport.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15, -140, 0)
	fill.light_energy = 0.5
	viewport.add_child(fill)
	var camera := Camera3D.new()
	camera.fov = 34.0
	camera.position = Vector3(0, 0.5, 5.0)
	camera.rotation_degrees.x = -4.0
	viewport.add_child(camera)
	_row = Node3D.new()
	_row.position.y = 0.35
	viewport.add_child(_row)
	return container


## The time and the battery, where the carousel has them.
func _top_bar() -> Control:
	var bar := Control.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clock = StudioPill.new()
	_clock.position = StudioTokens.CLOCK.position
	_clock.size = StudioTokens.CLOCK.size
	bar.add_child(_clock)
	_battery = BatteryChip.new()
	_battery.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_battery.offset_left = -157.0
	_battery.offset_top = 29.0
	_battery.offset_right = -32.0
	_battery.offset_bottom = 64.0
	bar.add_child(_battery)
	_battery.ready.connect(func() -> void:
		if android:
			_battery.show_battery(android.battery())
			android.battery_changed.connect(_battery.show_battery), CONNECT_ONE_SHOT)
	return bar


## A Select, Y Settings, B Exit: the carousel's hint row, at its place.
func _hints() -> Control:
	var row := _HINT_ROW.instantiate() as Control
	for hint: Array in [[&"a", "Select"], [&"y", "Settings"], [&"b", "Exit"]]:
		var shown := ButtonHint.new()
		shown.button = hint[0]
		shown.text = hint[1]
		row.add_child(shown)
	return row


## The chosen card's name, big, and its line under it.
func _draw_texts() -> void:
	if _cards.is_empty():
		return
	var card := _cards[_index]
	var middle := _root.size.x / 2.0
	var title := StudioText.new(card.title, StudioTokens.Face.JAKARTA_800, 48.0, -0.02)
	var top := _root.size.y * 0.7
	title.draw(_texts, Vector2(middle - title.width / 2.0, top), Backdrop.palette.ink)
	if card.detail != "":
		var detail := StudioText.new(card.detail, StudioTokens.Face.JAKARTA_500, 24.0)
		detail.fit(_root.size.x * 0.6)
		detail.draw(_texts, Vector2(middle - detail.width / 2.0, top + 66.0), Backdrop.palette.mute)


## Bottom middle, the Mirmire × Cartouche logo, for the backdrop's light or dark; bottom right, the player's
## RetroAchievements.
func _draw_bar() -> void:
	var bottom := 922.0
	var dark := Backdrop.palette.ink.get_luminance() > 0.5
	var logo: Texture2D = _BAR_ON_DARK if dark else _BAR_ON_LIGHT
	var tall := _LOGO_PX
	var wide := tall * logo.get_width() / maxf(1.0, logo.get_height())
	_bar.draw_texture_rect(logo, Rect2(_root.size.x / 2.0 - wide / 2.0, bottom - tall, wide, tall), false)
	var ra: Dictionary = _home.get("achievements", {})
	if ra.is_empty():
		return
	var right := _root.size.x - 40.0
	var y := bottom - _AVATAR_PX
	var line := StudioText.of(StudioTokens.Role.HINT, tr("{points} pts · {week} this week").format(
		{"points": str(ra.get("points", 0)).to_int(), "week": str(ra.get("week_unlocks", 0)).to_int()}))
	right -= line.width
	line.draw(_bar, Vector2(right, y + (_AVATAR_PX - 28.0) / 2.0), Backdrop.palette.ink)
	if _avatar:
		right -= _AVATAR_PX + 10.0
		_bar.draw_texture_rect(_avatar, Rect2(right, y, _AVATAR_PX, _AVATAR_PX), false)


static func _texture(path: String) -> Texture2D:
	if path == "" or not FileAccess.file_exists(path):
		return null
	var image := Image.load_from_file(path)
	return ImageTexture.create_from_image(image) if image and not image.is_empty() else null
