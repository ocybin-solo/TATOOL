extends VBoxContainer

signal uniform_changed(name: String, value: Variant)

var parsed_uniforms: Array = []
var active_index: int = 0
var sensitivity: float = 1.0
var sensitivity_presets: Array = [0.01, 0.1, 1.0, 5.0, 10.0]
var current_sens_index: int = 2
var active_sub_channel: int = 0
var uniform_values: Dictionary = {}

# Dictionary cache linking variable names directly to their parsed comments
var uniform_descriptions: Dictionary = {}

# Node Layout references
var label_status: Label
var label_sens_indicator: Label # Your verified thumb indicator label
var input_row_container: HBoxContainer
var btn_channel: Button

func _ready() -> void:
	setup_ui_layout()

func setup_ui_layout() -> void:
	# Upper status text readout structure
	label_status = Label.new()
	label_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_status.text = "No Shader Loaded"
	add_child(label_status)
	
	input_row_container = HBoxContainer.new()
	input_row_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	input_row_container.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(input_row_container)
	
	var btn_size = Vector2(66, 66)
	
	# =========================================================================
	# D-PAD 1 (FAR LEFT): NAVIGATES PARAMETERS AND SUB-CHANNELS
	# =========================================================================
	var nav_grid = GridContainer.new()
	nav_grid.columns = 3
	nav_grid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	input_row_container.add_child(nav_grid)
	
	nav_grid.add_child(Control.new())
	var btn_p_up = Button.new()
	btn_p_up.text = "PARAM\n▲"
	btn_p_up.custom_minimum_size = btn_size
	btn_p_up.pressed.connect(_on_dpad_up)
	nav_grid.add_child(btn_p_up)
	nav_grid.add_child(Control.new())
	
	var btn_ch_prev = Button.new()
	btn_ch_prev.text = "◄\nCH"
	btn_ch_prev.custom_minimum_size = btn_size
	btn_ch_prev.pressed.connect(_on_channel_back)
	nav_grid.add_child(btn_ch_prev)
	
	btn_channel = Button.new()
	btn_channel.text = "CH: 0"
	btn_channel.custom_minimum_size = btn_size
	btn_channel.disabled = true
	nav_grid.add_child(btn_channel)
	
	var btn_ch_next = Button.new()
	btn_ch_next.text = "CH\n►"
	btn_ch_next.custom_minimum_size = btn_size
	btn_ch_next.pressed.connect(_on_channel_toggle_pressed)
	nav_grid.add_child(btn_ch_next)
	
	nav_grid.add_child(Control.new())
	var btn_p_down = Button.new()
	btn_p_down.text = "▼\nPARAM"
	btn_p_down.custom_minimum_size = btn_size
	btn_p_down.pressed.connect(_on_dpad_down)
	nav_grid.add_child(btn_p_down)
	nav_grid.add_child(Control.new())
	
	var central_expanding_spacer = Control.new()
	central_expanding_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_row_container.add_child(central_expanding_spacer)
	
	# =========================================================================
	# D-PAD 2 (FAR RIGHT): CONTROLS VALUES AND SENSITIVITY DEGREES
	# =========================================================================
	var val_grid = GridContainer.new()
	val_grid.columns = 3
	val_grid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	input_row_container.add_child(val_grid)
	
	val_grid.add_child(Control.new())
	var btn_val_up = Button.new()
	btn_val_up.text = "VALUE\n▲"
	btn_val_up.custom_minimum_size = btn_size
	btn_val_up.pressed.connect(func(): modify_active_value(1.0))
	val_grid.add_child(btn_val_up)
	val_grid.add_child(Control.new())
	
	var btn_sens_down = Button.new()
	btn_sens_down.text = "◄\nSENS"
	btn_sens_down.custom_minimum_size = btn_size
	btn_sens_down.pressed.connect(_on_dpad_left)
	val_grid.add_child(btn_sens_down)
	
	# Initialize your dynamic thumb feedback text layout
	label_sens_indicator = Label.new()
	label_sens_indicator.text = "1.0"
	label_sens_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val_grid.add_child(label_sens_indicator)
	
	var btn_sens_up = Button.new()
	btn_sens_up.text = "SENS\n►"
	btn_sens_up.custom_minimum_size = btn_size
	btn_sens_up.pressed.connect(_on_dpad_right)
	val_grid.add_child(btn_sens_up)
	
	val_grid.add_child(Control.new())
	var btn_val_down = Button.new()
	btn_val_down.text = "▼\nVALUE"
	btn_val_down.custom_minimum_size = btn_size
	btn_val_down.pressed.connect(func(): modify_active_value(-1.0))
	val_grid.add_child(btn_val_down)
	val_grid.add_child(Control.new())
	
	var right_pad = Control.new()
	right_pad.custom_minimum_size = Vector2(20, 0)
	input_row_container.add_child(right_pad)

func apply_orientation_layout_shift(_to_portrait: bool, target_top_container: PanelContainer) -> void:
	if label_status.get_parent():
		label_status.get_parent().remove_child(label_status)
	target_top_container.add_child(label_status)
	update_status_readout()

# Memory String Parser: Walks source strings to capture description tags
func load_shader_source(shader_code: String) -> void:
	parsed_uniforms.clear()
	uniform_values.clear()
	uniform_descriptions.clear()
	
	var lines = shader_code.split("\n")
	var active_cached_desc: String = ""
	
	for line in lines:
		var trimmed = line.strip_edges()
		
		# 1. Capture description tags
		if trimmed.begins_with("// DESC:"):
			active_cached_desc = trimmed.replace("// DESC:", "").strip_edges()
			continue
			
		# 2. Match variables via code structure syntax
		if trimmed.contains("uniform"):
			var regex = RegEx.new()
			regex.compile("uniform\\s+(float|vec2|vec4)\\s+(\\w+)")
			var result = regex.search(trimmed)
			
			if result:
				var u_type = result.get_string(1)
				var u_name = result.get_string(2)
				
				if u_name == "u_time" or u_name == "u_pattern_texture": continue
				
				parsed_uniforms.append({"name": u_name, "type": u_type})
				
				# Link description to variable if tag was cached on previous lines
				if active_cached_desc != "":
					uniform_descriptions[u_name] = active_cached_desc
					active_cached_desc = "" # Clear temporary cache buffer
				else:
					uniform_descriptions[u_name] = "Analog variable adjustment channel link."
				
				# Populate logical defaults
				if u_name == "u_warp_frequency": uniform_values[u_name] = Vector2(2.5, 2.5)
				elif u_type == "float": uniform_values[u_name] = 1.0
				elif u_type == "vec2": uniform_values[u_name] = Vector2(5.0, 5.0)
				elif u_type == "vec4": uniform_values[u_name] = Color.CYAN
				
	active_index = 0
	active_sub_channel = 0
	update_status_readout()

func _on_dpad_up() -> void:
	if parsed_uniforms.is_empty(): return
	active_index = posmod(active_index - 1, parsed_uniforms.size())
	active_sub_channel = 0
	update_status_readout()

func _on_dpad_down() -> void:
	if parsed_uniforms.is_empty(): return
	active_index = posmod(active_index + 1, parsed_uniforms.size())
	active_sub_channel = 0
	update_status_readout()

func _on_dpad_left() -> void:
	current_sens_index = max(0, current_sens_index - 1)
	sensitivity = sensitivity_presets[current_sens_index]
	update_status_readout()

func _on_dpad_right() -> void:
	current_sens_index = min(sensitivity_presets.size() - 1, current_sens_index + 1)
	sensitivity = sensitivity_presets[current_sens_index]
	update_status_readout()

func _on_channel_toggle_pressed() -> void:
	if parsed_uniforms.is_empty(): return
	var u_type = parsed_uniforms[active_index]["type"]
	if u_type == "vec2": active_sub_channel = posmod(active_sub_channel + 1, 2)
	elif u_type == "vec4": active_sub_channel = posmod(active_sub_channel + 1, 4)
	else: active_sub_channel = 0
	update_status_readout()

func _on_channel_back() -> void:
	if parsed_uniforms.is_empty(): return
	var u_type = parsed_uniforms[active_index]["type"]
	if u_type == "vec2": active_sub_channel = posmod(active_sub_channel - 1, 2)
	elif u_type == "vec4": active_sub_channel = posmod(active_sub_channel - 1, 4)
	else: active_sub_channel = 0
	update_status_readout()

func modify_active_value(direction_multiplier: float) -> void:
	if parsed_uniforms.is_empty(): return
	var active_uniform = parsed_uniforms[active_index]
	var u_name = active_uniform["name"]
	var u_type = active_uniform["type"]
	var applied_change = direction_multiplier * sensitivity
	
	if u_type == "float":
		uniform_values[u_name] += applied_change
		uniform_changed.emit(u_name, uniform_values[u_name])
	elif u_type == "vec2":
		if active_sub_channel == 0: uniform_values[u_name].x += applied_change
		else: uniform_values[u_name].y += applied_change
		uniform_changed.emit(u_name, uniform_values[u_name])
	elif u_type == "vec4":
		var col = uniform_values[u_name] as Color
		if active_sub_channel == 0: col.r = clamp(col.r + applied_change, 0.0, 1.0)
		elif active_sub_channel == 1: col.g = clamp(col.g + applied_change, 0.0, 1.0)
		elif active_sub_channel == 2: col.b = clamp(col.b + applied_change, 0.0, 1.0)
		elif active_sub_channel == 3: col.a = clamp(col.a + applied_change, 0.0, 1.0)
		uniform_values[u_name] = col
		uniform_changed.emit(u_name, uniform_values[u_name])
	update_status_readout()

func get_sub_channel_name(u_type: String) -> String:
	if u_type == "vec2": return " [X]" if active_sub_channel == 0 else " [Y]"
	elif u_type == "vec4":
		var channels = [" [RED]", " [GREEN]", " [BLUE]", " [ALPHA]"]
		return channels[active_sub_channel]
	return ""

func update_status_readout() -> void:
	if parsed_uniforms.is_empty(): return
	var active = parsed_uniforms[active_index]
	var u_type = active["type"]
	if u_type == "float": btn_channel.text = "FLOAT"
	else: btn_channel.text = "CH: %d" % active_sub_channel
	
	var p_name = active["name"]
	var sub_ch = get_sub_channel_name(u_type)
	var val_str = str(uniform_values[p_name])
	var sens_str = str(sensitivity)
	
	# Pull description string out of the cache map
	var desc_str = uniform_descriptions.get(p_name, "Adjustable hardware matrix parameter.")
	
	# --- UPGRADED DOUBLE-LINE FORMATTING BLOCK ---
	# Line 1: Real-time numeric variable states
	# Line 2 (\n): Static human-readable operational description text
	label_status.text = "  PARAM: %s (%s)%s   •   VALUE: %s   •   SENSITIVITY: %s  \nℹ️  %s  " % [
		p_name, u_type, sub_ch, val_str, sens_str, desc_str
	]
	
	if label_sens_indicator:label_sens_indicator.text = sens_str
