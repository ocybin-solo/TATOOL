class_name PatternPreset
extends Resource

@export var shader_code: String = ""
@export var uniform_values: Dictionary = {}  # Format: {"u_scale": 3.0, "u_color": Color.WHITE}
@export var target_resolution: Vector2 = Vector2(512, 512)
