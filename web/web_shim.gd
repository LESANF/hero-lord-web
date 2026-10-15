extends Node
# Autoloaded only in the web build (see web/override.cfg). Runtime fixes for
# what the Android build took for granted; keep this list short and explained.


func _init() -> void:
	# The UI is touch-first and project.binary stores emulate_mouse_from_touch=false.
	# A mouse-only browser would never produce InputEventScreenTouch otherwise.
	Input.set_emulate_touch_from_mouse(true)
	print("WebShim: emulate_touch_from_mouse=", Input.is_emulating_touch_from_mouse())
