class_name DayNight
extends Node
## Day/night tint cycle via CanvasModulate (world canvas only — UI layers are
## unaffected). phase 0 = midnight, 0.25 = sunrise, 0.5 = noon, 0.75 = dusk.

## Length of a full day in seconds. 480 s (an 8-minute day) meant an NPC changed
## schedule point every one to three minutes and never seemed to settle; at 20
## minutes a routine is something the player can actually notice, and the four
## slots are 3-6 minutes each.
@export var cycle_seconds := 1200.0
@export var start_phase := 0.32  # start each session in the morning

var canvas: CanvasModulate
var phase := 0.0

const KEYS: Array = [
	[0.00, Color(0.34, 0.38, 0.58)],  # night
	[0.20, Color(0.34, 0.38, 0.58)],
	[0.28, Color(0.82, 0.66, 0.58)],  # dawn
	[0.36, Color(1.00, 1.00, 1.00)],  # day
	[0.62, Color(1.00, 1.00, 1.00)],
	[0.72, Color(0.92, 0.66, 0.50)],  # dusk
	[0.80, Color(0.34, 0.38, 0.58)],  # night
	[1.00, Color(0.34, 0.38, 0.58)],
]


func _ready() -> void:
	add_to_group("day_night")  # NPC schedules read the clock through this group
	canvas = CanvasModulate.new()
	canvas.name = "DayNightModulate"
	add_child(canvas)
	phase = start_phase
	canvas.color = color_for(phase)


func _process(delta: float) -> void:
	phase = fposmod(phase + delta / cycle_seconds, 1.0)
	canvas.color = color_for(phase)


func time_of_day_name() -> String:
	if phase < 0.22 or phase >= 0.80:
		return "Night"
	elif phase < 0.32:
		return "Dawn"
	elif phase < 0.68:
		return "Day"
	return "Dusk"


func color_for(p: float) -> Color:
	for i in KEYS.size() - 1:
		var a: Array = KEYS[i]
		var b: Array = KEYS[i + 1]
		if p >= float(a[0]) and p <= float(b[0]):
			var span := maxf(float(b[0]) - float(a[0]), 0.0001)
			var t := (p - float(a[0])) / span
			return (a[1] as Color).lerp(b[1] as Color, t)
	return Color.WHITE
