extends Node
# Autoloaded only in the web build (see web/override.cfg). Runtime fixes for
# what the Android build took for granted; keep this list short and explained.

# Keyboard hints drawn on the touch HUD. Keys come from game.gd _install_actions();
# "auto" has no action in the game, so the shim adds hero_auto = R below.
const HINTS := {
	"menu_button": "ESC", "map_button": "M", "auto_button": "R",
	"talk_button": "SPACE", "strong_button": "X", "item_button": "Q", "cycle_button": "E",
}
const SKILL_HINTS := ["1", "3"]

var game: Node


func _init() -> void:
	# The UI is touch-first and project.binary stores emulate_mouse_from_touch=false.
	# A mouse-only browser would never produce InputEventScreenTouch otherwise.
	Input.set_emulate_touch_from_mouse(true)
	print("WebShim: emulate_touch_from_mouse=", Input.is_emulating_touch_from_mouse())
	_apply_art_choice()
	if not InputMap.has_action("hero_auto"):
		InputMap.add_action("hero_auto")
		var key := InputEventKey.new()
		key.physical_keycode = KEY_R
		InputMap.action_add_event("hero_auto", key)


# The landing page passes `art=original` or `art=remaster` after `--`. The game reads
# user://options.json in _load_options() (new_art, default true), so write the choice
# there before the main scene exists; every other key keeps its saved or default value.
func _apply_art_choice() -> void:
	var want := ""
	for arg in OS.get_cmdline_user_args():
		if arg == "art=original":
			want = "false"
		elif arg == "art=remaster":
			want = "true"
	if want == "":
		return
	var path := "user://options.json"
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	var options: Dictionary = saved if saved is Dictionary else {}
	options["new_art"] = want == "true"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(options, "\t") + "\n")
		file.close()
	print("WebShim: new_art=", options["new_art"])


func _ready() -> void:
	var timer := Timer.new()
	timer.wait_time = 0.3
	timer.timeout.connect(_attach_hints)
	timer.timeout.connect(_guard_guardians)
	timer.timeout.connect(_push_art_state)
	add_child(timer)
	timer.start()
	if OS.has_feature("web"):
		# window.heroLordSetArt('original'|'remaster') from the page's toggle
		_js_set_art = JavaScriptBridge.create_callback(_set_art_from_page)
		_js_export = JavaScriptBridge.create_callback(_export_saves)
		_js_import = JavaScriptBridge.create_callback(_import_saves)
		var window := JavaScriptBridge.get_interface("window")
		window.heroLordSetArt = _js_set_art
		window.heroLordExportSaves = _js_export
		window.heroLordImportSaves = _js_import


var _js_set_art: JavaScriptObject
var _js_export: JavaScriptObject
var _js_import: JavaScriptObject
var _art_pushed := ""

# Save transfer between browsers. The game keeps plain JSON under user://
# (saves/*.json plus the files below); a bundle is just those texts in one JSON.
# JavaScriptBridge callbacks cannot return values, so results go to window.*.
const USER_FILES := ["options.json", "progress.json", "cutscenes-seen.json"]


func _export_saves(_args: Array) -> void:
	var files := {}
	for name in USER_FILES:
		if FileAccess.file_exists("user://" + name):
			files[name] = FileAccess.get_file_as_string("user://" + name)
	var dir := DirAccess.open("user://saves")
	if dir != null:
		for f in dir.get_files():
			if f.ends_with(".json"):
				files["saves/" + f] = FileAccess.get_file_as_string("user://saves/" + f)
	var bundle := {"game": "HeroLordRemaster", "exported": Time.get_datetime_string_from_system(), "files": files}
	JavaScriptBridge.get_interface("window").heroLordSaveBundle = JSON.stringify(bundle, "\t")


func _import_saves(args: Array) -> void:
	var window := JavaScriptBridge.get_interface("window")
	window.heroLordImportResult = -1
	var parsed: Variant = JSON.parse_string(str(args[0])) if not args.is_empty() else null
	if not (parsed is Dictionary) or not (parsed.get("files") is Dictionary):
		return
	DirAccess.make_dir_recursive_absolute("user://saves")
	var count := 0
	for name in parsed.files:
		var n := str(name)
		var ok := n in USER_FILES or (n.begins_with("saves/") and n.ends_with(".json") and not "/" in n.trim_prefix("saves/"))
		if not ok:
			continue  # only the files the game itself writes, never arbitrary paths
		var file := FileAccess.open("user://" + n, FileAccess.WRITE)
		if file != null:
			file.store_string(str(parsed.files[name]))
			file.close()
			count += 1
	window.heroLordImportResult = count


# Same steps as the game's own toggles (_title_art / _story_menu_art), minus the
# screen-specific refresh, so it works from any screen.
func _set_art_from_page(args: Array) -> void:
	if game == null or args.is_empty():
		return
	var want: bool = str(args[0]) == "remaster"
	var world: Node = game.get("world")
	if world == null or bool(world.get("modern_art_enabled")) == want:
		return
	world.call("set_modern_art_enabled", want)
	var options: Dictionary = game.get("options")
	options["new_art"] = want
	game.call("_save_options")
	game.call("_apply_art_choice")
	game.call("_layout")
	if game.get("menu_page") == "options":
		game.call("_show_options")


# Keep the page's toggle in sync when the art is changed inside the game.
func _push_art_state() -> void:
	if game == null or not OS.has_feature("web"):
		return
	var world: Node = game.get("world")
	if world == null:
		return
	var state := "remaster" if bool(world.get("modern_art_enabled")) else "original"
	if state != _art_pushed:
		_art_pushed = state
		JavaScriptBridge.eval("window.dispatchEvent(new CustomEvent('herolord-art', {detail: '%s'}))" % state)


# New game -> "함께할 가디언": the game toggles guardian_picks without a cap, so a third
# card can be picked (header shows 3 / 2 and 모험 시작 greys out). Disable the unpicked
# cards once two are chosen; the game's own touch router skips disabled buttons.
func _guard_guardians() -> void:
	if game == null or game.get("menu_page") != "guardians":
		return
	for card in game.get("guardian_buttons"):
		if is_instance_valid(card) and not card.pressed.is_connected(_limit_guardians):
			card.pressed.connect(_limit_guardians)  # runs after the game's _toggle_guardian
	_limit_guardians()


func _limit_guardians() -> void:
	var picks: Array = game.get("guardian_picks")
	var cards: Array = game.get("guardian_buttons")
	var full: bool = picks.count(true) >= 2
	for i in mini(picks.size(), cards.size()):
		if is_instance_valid(cards[i]):
			cards[i].disabled = full and not picks[i]


func _input(event: InputEvent) -> void:
	# One input path, like Android. Every left click already arrives a second time as an
	# emulated touch that the game's own router handles; if the real mouse event also reached
	# the GUI, a Button would fire twice (the dialogue "빨리 ▶▶" toggle cancelled itself and
	# "다음" advanced two lines per click). Scene nodes' _input (virtual joystick, title) have
	# already seen this event by the time an autoload gets it, so only the GUI stage is cut.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and event.device != InputEvent.DEVICE_ID_EMULATION:
		get_viewport().set_input_as_handled()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("hero_auto") and not event.is_echo() and game != null:
		var button: Button = game.get("auto_button")
		if button != null and button.is_visible_in_tree() and not button.disabled:
			button.pressed.emit()


func _attach_hints() -> void:
	var scene := get_tree().current_scene
	if scene == null or not scene.has_method("_layout_nodes"):
		return
	game = scene
	for prop in HINTS:
		_hint(game.get(prop), HINTS[prop])
	var skills: Array = game.get("skill_buttons")
	for i in mini(skills.size(), SKILL_HINTS.size()):
		_hint(skills[i], SKILL_HINTS[i])
	_hint(game.get("joystick"), "WASD")


func _hint(target: Control, text: String) -> void:
	if target == null or target.has_node("KeyHint"):
		return
	var label := Label.new()
	label.name = "KeyHint"
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 1
	var scale: float = maxf(1.0, float(game.get("ui_scale")))
	label.add_theme_font_size_override("font_size", roundi(11 * scale))
	label.add_theme_color_override("font_color", Color(0.97, 0.97, 0.97, 0.9))
	var pill := StyleBoxFlat.new()
	pill.bg_color = Color(0.25, 0.25, 0.27, 0.6)
	pill.set_corner_radius_all(roundi(4 * scale))
	pill.content_margin_left = 5 * scale
	pill.content_margin_right = 5 * scale
	pill.content_margin_top = 1 * scale
	pill.content_margin_bottom = 1 * scale
	label.add_theme_stylebox_override("normal", pill)
	target.add_child(label)
	# Centered on the top edge, half outside the button, so it never covers the icon.
	var half := label.get_minimum_size() / 2.0
	label.anchor_left = 0.5
	label.anchor_right = 0.5
	label.anchor_top = 0.0
	label.anchor_bottom = 0.0
	label.offset_left = -half.x
	label.offset_right = half.x
	label.offset_top = -half.y
	label.offset_bottom = half.y
