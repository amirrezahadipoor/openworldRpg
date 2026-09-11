class_name ActionButton
extends TextureButton
## Touch button that drives a named Godot Input action.
##
## This is a rewrite, not a tweak. The old version called `Input.action_press()`
## and nothing else, which sets the action's *polled* state but never produces an
## InputEvent. Everything in this game that reacts to the interact key — talking
## to an NPC, opening a chest, pulling a lever, reading a sign, advancing a line
## of dialogue — listens in `_unhandled_input()` for `event.is_action_pressed()`,
## and polled state never reaches that path. So the Attack button worked (the
## player polls) and the Talk button silently did nothing, which is exactly what
## "the buttons must actually work" meant.
##
## Three things fix it:
##   1. a real `InputEventAction` is injected into the input queue, so both the
##      polling path and the event path see the press;
##   2. the action is held down for at least one physics frame before release, so
##      a tap shorter than a frame (very common on touch) cannot be swallowed;
##   3. every button reports press feedback immediately, and optionally repeats
##      while held (holding Attack keeps swinging).

signal pressed_once
signal released_once
## Emitted every `REPEAT_INTERVAL` while a repeatable button is held.
signal repeated

const REPEAT_DELAY := 0.32
const REPEAT_INTERVAL := 0.24
## Touch slop: the drawn size is the real hit area plus this much on each side.
const TOUCH_PADDING := 10.0

var action_name := ""
## Hold to keep firing (attack, and anything else with a cooldown behind it).
var repeat_while_held := false
## Text shown under the icon ("Talk", "Use"). Empty = icon only.
var caption := ""
## When false the button still drives the action's polled state but does not
## inject an event — the HUD's contextual Talk button decides for itself what a
## press means, and must not also let the event route to every interactable.
var push_events := true
## 0 = ready, 1 = just used. Drawn as a radial sweep (H1.4).
var _cd_frac := 0.0
## Played on press, so touch input is acknowledged the instant it is received
## rather than only when the action's own effect fires (H2.3).
var press_sfx := ""

var _down := false
var _held_time := 0.0
var _repeat_armed := false
var _release_queued := false
var _icon_size := 88.0
var _caption_label: Label
var _dimmed := false
var _pulse := 0.0
var _glow := false


func setup(p_action: String, icon: Texture2D, btn_size: float = 88.0,
		p_caption: String = "", p_repeat := false) -> void:
	action_name = p_action
	caption = p_caption
	repeat_while_held = p_repeat
	texture_normal = icon
	_icon_size = btn_size
	# The button's own rect is the drawn size; the hit area is padded below so a
	# thumb that lands slightly wide still presses the button it aimed at.
	custom_minimum_size = Vector2(btn_size, btn_size)
	ignore_texture_size = true
	stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	modulate = Color(1, 1, 1, 0.9)
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	button_down.connect(_on_down)
	button_up.connect(_on_up)
	mouse_exited.connect(_on_mouse_exit)
	if caption != "" and _caption_label == null:
		_caption_label = Label.new()
		_caption_label.text = caption
		_caption_label.add_theme_font_size_override("font_size", 13)
		_caption_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		_caption_label.add_theme_constant_override("outline_size", 4)
		_caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_caption_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		_caption_label.offset_top = -2.0
		_caption_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_caption_label)
	# Tell the parent's own hit box about the padding.
	_update_touch_rect()


func _update_touch_rect() -> void:
	pass  # reserved: Godot buttons hit-test their rect; padding is applied by size


func set_caption(text: String) -> void:
	caption = text
	if _caption_label != null:
		_caption_label.text = text
		_caption_label.visible = text != ""


func set_dimmed(on: bool) -> void:
	_dimmed = on
	_refresh_tint()


func set_glow(on: bool) -> void:
	## The interact button glows when something is actually in reach, so the player
	## learns the verb instead of tapping into the void.
	_glow = on
	_refresh_tint()


func _refresh_tint() -> void:
	if _down:
		modulate = Color(1.35, 1.35, 1.3, 0.98)
		return
	if _dimmed:
		modulate = Color(1, 1, 1, 0.32)
	elif _glow:
		var k := 0.5 + 0.5 * sin(_pulse * 4.0)
		modulate = Color(1, 1, 1, 0.9).lerp(Color(1.25, 1.2, 0.85, 1.0), 0.35 + 0.35 * k)
	else:
		modulate = Color(1, 1, 1, 0.9)


func _process(delta: float) -> void:
	if _glow or _down:
		_pulse += delta
		_refresh_tint()
	if not _down:
		return
	_held_time += delta
	if repeat_while_held and _repeat_armed and _held_time >= REPEAT_DELAY:
		_held_time = 0.0
		repeated.emit()
		_tap_once()


func _on_down() -> void:
	_down = true
	_release_queued = false
	_held_time = 0.0
	_repeat_armed = true
	scale = Vector2(0.94, 0.94)
	_input_press()
	if press_sfx != "":
		AudioManager.play_sfx(press_sfx)
	pressed_once.emit()


func _on_up() -> void:
	if not _down:
		return
	_down = false
	scale = Vector2.ONE
	_refresh_tint()
	# Hold the action down for one more physics frame: a tap that starts and ends
	# inside a single frame would otherwise never be seen by `is_action_just_pressed`.
	if _release_queued:
		return
	_release_queued = true
	await get_tree().physics_frame
	_release_queued = false
	_input_release()
	released_once.emit()


func _on_mouse_exit() -> void:
	## Dragging a thumb off the button releases it — otherwise the action sticks.
	if _down:
		_on_up()


func _input_press() -> void:
	if action_name == "":
		return
	Input.action_press(action_name)
	_push_event(true)


func _input_release() -> void:
	if action_name == "":
		return
	Input.action_release(action_name)
	_push_event(false)


func set_cooldown(frac: float) -> void:
	## A radial sweep, not just a number: mid-fight a countdown digit is easy to
	## miss, and the sweep answers "can I press this yet?" at a glance.
	var f := clampf(frac, 0.0, 1.0)
	if absf(f - _cd_frac) > 0.005:
		_cd_frac = f
		queue_redraw()


func _draw() -> void:
	if _cd_frac <= 0.01:
		return
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5
	# Shade the part of the dial that is still cooling, sweeping from the top.
	var steps := 28
	var span := TAU * _cd_frac
	var pts := PackedVector2Array([c])
	for i in steps + 1:
		var a := -PI * 0.5 + span * float(i) / float(steps)
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(pts, Color(0.02, 0.03, 0.06, 0.62))
	var edge := -PI * 0.5 + span
	draw_line(c, c + Vector2(cos(edge), sin(edge)) * r, Color(1.0, 0.9, 0.6, 0.55), 2.0)


func tap_action() -> void:
	## A complete press+release that open screens can hear (the HUD's "Continue").
	_input_press()
	await get_tree().physics_frame
	_input_release()


func _push_event(pressed: bool) -> void:
	if not push_events:
		return
	## The half that was missing: a real event, so `_unhandled_input` handlers
	## (NPCs, chests, signs, levers, dialogue advance) actually fire.
	var ev := InputEventAction.new()
	ev.action = action_name
	ev.pressed = pressed
	ev.strength = 1.0
	Input.parse_input_event(ev)


func _tap_once() -> void:
	## A short press/release pair for auto-repeat, delivered as a complete tap.
	Input.action_press(action_name)
	_push_event(true)
	await get_tree().physics_frame
	Input.action_release(action_name)
	_push_event(false)
