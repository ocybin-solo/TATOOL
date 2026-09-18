extends Resource
class_name PatternPreset

# --- HARDWARE TARGET LAYER METRICS ---
@export var preset_name: String = "New Generative Matrix"
@export var target_resolution: Vector2 = Vector2(512, 512)

# --- PASS SHADER MODULE SLOTS ---
# Stores the compiled name references to map back to the registry matrix
@export var pass1_active_module: String = "None Selected"
@export var pass2_active_module: String = "None Selected"
@export var pass3_active_module: String = "None Selected"

# --- UNIVERSAL MULTI-PASS CACHE MATRIX ---
# Key: Uniform string identifier name (e.g. "u_warp_strength")
# Value: Data payload (float, Vector2, or Color objects)
@export var uniform_values: Dictionary = {}

## Serializes the active real-time data layer matrix down to a file pack path structure
func cache_layer_uniform(u_name: String, u_value: Variant) -> void:
	uniform_values[u_name] = u_value

## Pulls a safely formatted default if a target parameter doesn't exist in the file path
func get_cached_uniform(u_name: String, default_fallback: Variant) -> Variant:
	if uniform_values.has(u_name):
		return uniform_values[u_name]
	return default_fallback

## Completely clears the local active memory structures back to factory baselines
func reset_preset_matrix() -> void:
	uniform_values.clear()
	pass1_active_module = "None Selected"
	pass2_active_module = "None Selected"
	pass3_active_module = "None Selected"
	preset_name = "Factory Baseline Reset"
