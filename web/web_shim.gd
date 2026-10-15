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
	if not InputMap.has_action("hero_auto"):
		InputMap.add_action("hero_auto")
		var key := InputEventKey.new()
		key.physical_keycode = KEY_R
		InputMap.action_add_event("hero_auto", key)


func _ready() -> void:
	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.timeout.connect(_attach_hints)
	add_child(timer)
	timer.start()


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
