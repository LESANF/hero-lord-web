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
	var path := "user://options.json"
	var first_run := not FileAccess.file_exists(path)
	if want == "" and not first_run:
		return
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if not first_run else null
	var options: Dictionary = saved if saved is Dictionary else {}
	if want != "":
		options["new_art"] = want == "true"
	if first_run:
		options["sound"] = DEFAULT_VOLUME  # the game's own default is 10/10; too loud for a browser tab
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(options, "\t") + "\n")
		file.close()
	print("WebShim: options first_run=", first_run, " new_art=", options.get("new_art"), " sound=", options.get("sound"))


const DEFAULT_VOLUME := 5


# 환경설정 (title) gets two rows for the save bundle. The game rebuilds that page on every
# change, so this re-adds the rows whenever they are missing, just above the back key.
# Export downloads straight from GDScript; import opens the page's file picker (the page
# then calls heroLordImportSaves and reloads).
func _inject_option_rows() -> void:
	if game == null or game.get("menu_page") != "options" or not OS.has_feature("web"):
		return
	var box: Node = game.get("menu_box")
	if box == null or box.has_node("WebSaveExport"):
		return
	var export_row: Button = game.call("_paper_item", "세이브 내보내기 (파일 저장)", _export_saves.bind([]))
	export_row.name = "WebSaveExport"
	var import_row: Button = game.call("_paper_item", "세이브 가져오기 (파일 선택)", _open_import_picker)
	import_row.name = "WebSaveImport"
	for i in box.get_child_count():
		if str(box.get_child(i).get_meta("kind", "")) == "back":
			box.move_child(export_row, i)
			box.move_child(import_row, i + 1)
			break
	game.call("_layout")


func _open_import_picker() -> void:
	JavaScriptBridge.eval("document.getElementById('save-file').click()")


func _ready() -> void:
	var timer := Timer.new()
	timer.wait_time = 0.3
	timer.timeout.connect(_attach_hints)
	timer.timeout.connect(_guard_guardians)
	timer.timeout.connect(_push_art_state)
	timer.timeout.connect(_inject_option_rows)
	timer.timeout.connect(_wire_stick)
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
var _title_pushed := false

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
	var text := JSON.stringify(bundle, "\t")
	JavaScriptBridge.get_interface("window").heroLordSaveBundle = text
	JavaScriptBridge.download_buffer(text.to_utf8_buffer(), "herolord-saves-%s.json" % Time.get_date_string_from_system(), "application/json")


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
	# The page's art pill is for the press screen and the main title menu only: in game it
	# sits on the HUD, and on portrait phones it covers the headers of the other title pages
	# (영웅 선택, 가디언, 환경설정 – which has its own 그래픽 row anyway).
	var on_title: bool = game.get("mode") == "title" and str(game.get("menu_page")) in ["press", "title"]
	if on_title != _title_pushed:
		_title_pushed = on_title
		JavaScriptBridge.eval("window.dispatchEvent(new CustomEvent('herolord-title', {detail: %s}))" % ("true" if on_title else "false"))


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


# ── Mobile movement: make the touch stick feel like WASD ─────────────────────────────
# The game's VirtualJoystick is analog (dead zone, partial speed, any angle) and only
# starts when the thumb lands inside the drawn circle. On a phone that reads as sluggish
# and easy to miss. Two changes, both outside the game's code:
#  1. Floating origin: a touch anywhere in the lower-left movement zone moves the stick
#     under the thumb first (Window.window_input fires before any node's _input), so the
#     stick itself then begins on that touch as usual. It snaps back on release.
#  2. Digital output: the stick's vector is snapped to 8 directions at full length before
#     the game sees it, which is exactly what held WASD keys produce.
var _stick_wired := false
var _stick_touch := -1
var _stick_home := Vector2.ZERO


func _wire_stick() -> void:
	if _stick_wired or game == null:
		return
	var stick: Control = game.get("joystick")
	if stick == null:
		return
	var target := Callable(game, "_joystick_changed")
	if stick.vector_changed.is_connected(target):
		stick.vector_changed.disconnect(target)
	stick.vector_changed.connect(_stick_changed)
	get_tree().root.window_input.connect(_window_input)
	_stick_wired = true


func _stick_changed(value: Vector2) -> void:
	var snapped := Vector2.ZERO
	if value.length() > 0.0 and value.is_finite():
		snapped = Vector2.from_angle(roundf(value.angle() / (PI / 4.0)) * (PI / 4.0))
		snapped = Vector2(roundf(snapped.x * 1000.0), roundf(snapped.y * 1000.0)) / 1000.0
	game.call("_joystick_changed", snapped)


func _in_move_zone(stick: Control, at: Vector2) -> bool:
	var view := get_viewport().get_visible_rect().size
	if at.x > view.x * 0.5 or at.y < view.y * 0.4:
		return false
	if game.get("mode") != "play" or not stick.get("enabled") or not stick.is_visible_in_tree():
		return false
	for panel in ["menu_panel", "story_menu", "talk_log", "minimap"]:
		var node: Variant = game.get(panel)
		if node is CanvasItem and (node as CanvasItem).is_visible_in_tree():
			return false
	return true


func _window_input(event: InputEvent) -> void:
	if game == null or event.device == InputEvent.DEVICE_ID_EMULATION or not (event is InputEventScreenTouch):
		return
	_action_touch(event)
	var stick: Control = game.get("joystick")
	if stick == null:
		return
	if event.pressed and not event.canceled:
		if _stick_touch == -1 and int(stick.get("active_touch_id")) == -1 and _in_move_zone(stick, event.position):
			_stick_touch = event.index
			_stick_home = stick.position
			var centre: Vector2 = stick.get_global_transform_with_canvas() * (stick.size * 0.5)
			stick.position += event.position - centre
	elif event.index == _stick_touch:
		_stick_touch = -1
		stick.set_deferred("position", _stick_home)


# ── Mobile actions fire on touch-down, like keys ──────────────────────────────────────
# The game's touch router (game.gd _touch_ui) presses HUD buttons on touch-down but only
# emits `pressed` when the finger lifts, so attacks/skills land late and a thumb that
# slides off the button never fires. Keyboard keys act on key-down. For the action
# buttons we emit on touch-down here (window_input runs before the router) and, when that
# finger lifts, take the button out of the router's table first so it does not fire twice.
const ACTION_BUTTONS := ["talk_button", "strong_button", "item_button", "cycle_button"]
const UI_SKIN := preload("res://scripts/ui_skin.gd")
var _fired: Dictionary = {}   # touch index -> Button already fired on touch-down


func _action_buttons() -> Array:
	var list: Array = []
	for prop in ACTION_BUTTONS:
		var b: Variant = game.get(prop)
		if b is Button:
			list.append(b)
	for b in game.get("skill_buttons"):
		if b is Button:
			list.append(b)
	return list


func _action_touch(event: InputEventScreenTouch) -> void:
	if event.pressed and not event.canceled:
		if game.get("mode") != "play":
			return
		var dialogue: Variant = game.get("dialogue_panel")
		if dialogue is CanvasItem and (dialogue as CanvasItem).is_visible_in_tree():
			return
		for b in _action_buttons():
			if b.is_visible_in_tree() and not b.disabled and bool(game.call("_key_contains", b, event.position)):
				_fired[event.index] = b
				b.pressed.emit()
				return
	elif _fired.has(event.index):
		var b: Button = _fired[event.index]
		_fired.erase(event.index)
		var table: Dictionary = game.get("touch_buttons")
		if table.get(event.index) == b:
			table.erase(event.index)
		if is_instance_valid(b):
			b.set_pressed_no_signal(false)
			UI_SKIN.press(b, false)
