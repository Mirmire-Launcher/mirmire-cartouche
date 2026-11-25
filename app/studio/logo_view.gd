# SPDX-License-Identifier: GPL-3.0-or-later
class_name LogoView
extends TextureRect
## A console's logo in one of the fixed slots, at its pixel size: each slot's pictures are made ready
## for it, so the app fits nothing. A backdrop with [member Palette.dark_logos] shows the picture made for a dark
## ground (`<console>.dark.png`) where the slot has one.

enum Slot { RAIL_TILE, GAMES_TOP, PLINTH_PLATE, RING_MIDDLE, BETWEEN_MINI }

## Each slot's folder under res://studio/logos.
const FOLDERS: Array[String] = ["rail-tile", "games-top", "plinth-plate", "ring-middle", "between-mini"]
## Each slot's logo box in pixels, as its pictures are made: where a generic console's icon is fitted.
const _BOXES: Array[Vector2i] = [Vector2i(151, 102), Vector2i(416, 101), Vector2i(358, 90), Vector2i(282, 69), Vector2i(90, 33)]
## A generic console's folder name ([method Appearance.add_generic]), its platform's id after it: its logo is the
## platform's icon as Mirmire draws it ([constant GenericConsole.ICONS]).
const GENERIC := "generic-"
## What shows for a console without a logo in the slot: nothing, no room taken.
const _NONE := preload("res://studio/no_logo.tres")
## The logos read so far, by path (null for none): Godot drops a picture nobody shows, and a list moving
## through the consoles shows a new one at every step.
static var _read: Dictionary[String, Texture2D] = {}

var _slot := Slot.RAIL_TILE
var _console := ""


func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	stretch_mode = STRETCH_KEEP
	texture = _NONE


## Shows the logo of [param console] (its folder under res://carousel/consoles, `ps2_slim`) made for
## [param slot]; nothing, and false, when the slot has none for it.
func show_logo(slot: Slot, console: String) -> bool:
	_slot = slot
	_console = console
	if console.begins_with(GENERIC):
		return _show_icon(slot, console.trim_prefix(GENERIC))
	var path := "res://studio/logos/%s/%s.png" % [FOLDERS[slot], console]
	var dark := path.replace(".png", ".dark.png")
	if Backdrop.palette.dark_logos and ResourceLoader.exists(dark):
		path = dark
	if path not in _read:
		_read[path] = load(path) if ResourceLoader.exists(path) else null
	if not _read[path]:
		# A console added for Mirmire, without logos of its own: its platform's icon, as Mirmire draws it.
		var manifest := ConsoleManifest.of(console) if console else null
		if manifest and _show_icon(slot, manifest.platform):
			return true
		Diagnostics.trace("studio", "no %s logo for %s" % [FOLDERS[slot], console])
		texture = _NONE
		return false
	texture = _read[path]
	return true


## Shows [param platform]'s icon from Mirmire fitted in [param slot]'s box; nothing, and false, without one.
func _show_icon(slot: Slot, platform: String) -> bool:
	var path := GenericConsole.ICONS % platform
	var key := "%s@%s" % [path, FOLDERS[slot]]
	# A missing icon is not remembered: the plugin copies them as the app starts, and one may land after.
	if key not in _read:
		var image := Image.load_from_file(path) if FileAccess.file_exists(path) else null
		if image and not image.is_empty():
			var box := _BOXES[slot]
			var fit := minf(float(box.x) / image.get_width(), float(box.y) / image.get_height())
			image.resize(maxi(1, roundi(image.get_width() * fit)), maxi(1, roundi(image.get_height() * fit)),
				Image.INTERPOLATE_LANCZOS)
			_read[key] = ImageTexture.create_from_image(image)
	var icon: Texture2D = _read.get(key)
	texture = icon if icon else _NONE
	return icon != null


## Lets go of the logos no view shows, as a chooser that went through every console closes: a logo shown stays, held
## by its view, and one needed again is read again.
static func drop_unseen() -> void:
	_read.clear()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and _console:
		show_logo(_slot, _console)
