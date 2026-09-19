extends VBoxContainer

signal uniform_changed(name: String, value: Variant)

# Stores Category Names linked to the first uniform variable inside them
# Format: {"colors": "u_pattern_color", "scales": "u_warp_frequency"}
var shader_categories: Dictionary = {}

var parsed_uniforms: Array = []
var active_index: int = 0
var sensitivity: float = 1.0
var sensitivity_presets: Array = [0.01, 0.1, 1.0, 5.0, 10.0]
var current_sens_index: int = 2
var active_sub_channel: int = 0
var uniform_values: Dictionary = {}
#var is_input_blocked: bool = false

# 🌟 STRICT INPUT ISOLATION: while a menu overlay is open, MainManager
# calls set_dpad_locked(true) and both physical D-pad clusters go
# fully inert — clicking them does nothing, menu nav is driven only
# by the overlay's own ▲/▼ buttons.
var btn_param_up: Button
var btn_param_down: Button
var btn_channel_prev: Button
var btn_channel_next: Button
var btn_value_up: Button
var btn_value_down: Button
var btn_sens_left: Button
var btn_sens_right: Button

# Onboarding boot ribbon: true until the user's first real SHADER MENU
# use, so live D-pad taps before that don't overwrite the boot message.
var suppress_status_readout: bool = true

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
	label_status = Label.new()
	label_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_status.text = "No Shader Loaded"
	add_child(label_status)
	
	input_row_container = HBoxContainer.new()
	input_row_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	input_row_container.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(input_row_container)
	
	var btn_size = Vector2(66, 66)
	
	# Left wing layout padding (Pushes left D-pad inward for natural thumb placement)
	var left_spacer = Control.new()
	left_spacer.custom_minimum_size = Vector2(50, 0)
	input_row_container.add_child(left_spacer)
	
	# --- D-PAD 1 (LEFT THUMB - NAVIGATION) ---
	var nav_grid = GridContainer.new()
	nav_grid.columns = 3
	nav_grid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	input_row_container.add_child(nav_grid)
	
	nav_grid.add_child(Control.new())
	btn_param_up = Button.new()
	btn_param_up.text = "PARAM\n▲"
	btn_param_up.custom_minimum_size = btn_size
	btn_param_up.pressed.connect(_on_left_dpad_up)
	nav_grid.add_child(btn_param_up)
	nav_grid.add_child(Control.new())
	
	btn_channel_prev = Button.new()
	btn_channel_prev.text = "◄\nCH"
	btn_channel_prev.custom_minimum_size = btn_size
	btn_channel_prev.pressed.connect(_on_left_dpad_left)
	nav_grid.add_child(btn_channel_prev)
	
	btn_channel = Button.new()
	btn_channel.text = "CH: 0"
	btn_channel.custom_minimum_size = btn_size
	btn_channel.disabled = true
	nav_grid.add_child(btn_channel)
	
	btn_channel_next = Button.new()
	btn_channel_next.text = "CH\n►"
	btn_channel_next.custom_minimum_size = btn_size
	btn_channel_next.pressed.connect(_on_left_dpad_right)
	nav_grid.add_child(btn_channel_next)
	
	nav_grid.add_child(Control.new())
	btn_param_down = Button.new()
	btn_param_down.text = "▼\nPARAM"
	btn_param_down.custom_minimum_size = btn_size
	btn_param_down.pressed.connect(_on_left_dpad_down)
	nav_grid.add_child(btn_param_down)
	nav_grid.add_child(Control.new())
	
	# Expanding Central Vault Spacer
	var middle_expanding_spacer = Control.new()
	middle_expanding_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_row_container.add_child(middle_expanding_spacer)
	
	# --- D-PAD 2 (RIGHT THUMB - VALUE MODIFIER) ---
	var val_grid = GridContainer.new()
	val_grid.columns = 3
	val_grid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	input_row_container.add_child(val_grid)
	
	val_grid.add_child(Control.new())
	btn_value_up = Button.new()
	btn_value_up.text = "VALUE\n▲"
	btn_value_up.custom_minimum_size = btn_size
	btn_value_up.pressed.connect(_on_right_dpad_up)
	val_grid.add_child(btn_value_up)
	val_grid.add_child(Control.new())
	
	btn_sens_left = Button.new()
	btn_sens_left.text = "◄\nSENS"
	btn_sens_left.custom_minimum_size = btn_size
	btn_sens_left.pressed.connect(_on_right_dpad_left)
	val_grid.add_child(btn_sens_left)
	
	label_sens_indicator = Label.new()
	label_sens_indicator.text = "1.0"
	label_sens_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val_grid.add_child(label_sens_indicator)
	
	btn_sens_right = Button.new()
	btn_sens_right.text = "SENS\n►"
	btn_sens_right.custom_minimum_size = btn_size
	btn_sens_right.pressed.connect(_on_right_dpad_right)
	val_grid.add_child(btn_sens_right)
	
	val_grid.add_child(Control.new())
	btn_value_down = Button.new()
	btn_value_down.text = "▼\nVALUE"
	btn_value_down.custom_minimum_size = btn_size
	btn_value_down.pressed.connect(_on_right_dpad_down)
	val_grid.add_child(btn_value_down)
	val_grid.add_child(Control.new())
	
	# Right wing layout padding (Balances the spacing symmetrically)
	var right_spacer = Control.new()
	right_spacer.custom_minimum_size = Vector2(50, 0)
	input_row_container.add_child(right_spacer)

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
	shader_categories.clear()
	
	var lines = shader_code.split("\n")
	var active_cached_desc: String = ""
	var active_cached_cat: String = ""
	
	for line in lines:
		var trimmed = line.strip_edges()
		
		# 1. Capture category tags
		if trimmed.begins_with("// CAT:"):
			active_cached_cat = trimmed.replace("// CAT:", "").strip_edges()
			continue
		
		# 2. Capture description tags
		if trimmed.begins_with("// DESC:"):
			active_cached_desc = trimmed.replace("// DESC:", "").strip_edges()
			continue
			
		# 3. Match uniform variables
		if trimmed.contains("uniform"):
			var regex = RegEx.new()
			regex.compile("uniform\\s+(float|vec2|vec4|sampler2D)\\s+(\\w+)")
			var result = regex.search(trimmed)
			
			if result:
				var u_type = result.get_string(1)
				var u_name = result.get_string(2)
				
				if u_name == "u_time" or u_name == "u_pattern_texture" or u_type == "sampler2D": 
					continue
				
				parsed_uniforms.append({"name": u_name, "type": u_type})
				
				# Link first discovered variable to the active category block
				if active_cached_cat != "":
					if not shader_categories.has(active_cached_cat):
						shader_categories[active_cached_cat] = u_name
					active_cached_cat = "" 
				else:
					# 🌀 FALLBACK AUTO-CATEGORIZER REGEX ENGINES
					var target_cat = "🌀 UTILITY / OTHER"
					var lower_name = u_name.to_lower()
					
					var kw_distortion = ["warp", "twist", "wave", "bend", "scroll", "distort", "zoom", "pinch", "offset"]
					var kw_chromatic = ["color", "hue", "rgb", "fade", "palette", "tint", "bright", "sat", "contrast", "alpha"]
					var kw_frequency = ["speed", "freq", "time", "scale", "step", "rate", "pulse", "bpm", "length"]
					
					for kw in kw_distortion:
						if lower_name.contains(kw):
							target_cat = "🎨 DISTORTION"
							break
					
					if target_cat == "🌀 UTILITY / OTHER":
						for kw in kw_chromatic:
							if lower_name.contains(kw):
								target_cat = "🌈 CHROMATIC"
								break
								
					if target_cat == "🌀 UTILITY / OTHER":
						for kw in kw_frequency:
							if lower_name.contains(kw):
								target_cat = "⚡ FREQUENCY"
								break
								
					# Register fallback category hook safely
					if not shader_categories.has(target_cat):
						shader_categories[target_cat] = u_name
				
				# Link descriptions
				if active_cached_desc != "":
					uniform_descriptions[u_name] = active_cached_desc
					active_cached_desc = ""
				else:
					uniform_descriptions[u_name] = "Analog variable adjustment channel link."
				
				# Populate defaults
				if u_name == "u_warp_frequency": uniform_values[u_name] = Vector2(2.5, 2.5)
				elif u_type == "float": uniform_values[u_name] = 1.0
				elif u_type == "vec2": uniform_values[u_name] = Vector2(5.0, 5.0)
				elif u_type == "vec4": uniform_values[u_name] = Color.CYAN
				
	active_index = 0
	active_sub_channel = 0
	update_status_readout()
	
#func set_dpad_locked(is_locked: bool) -> void:
	## Strict Input Isolation: flip every physical D-pad button inert ## 
	## the instant a menu overlay opens. Menu nav from here on is
	## driven only by the overlay's own ▲/▼ buttons.
	#for btn in [btn_param_up, btn_param_down, btn_channel_prev, btn_channel_next,
			#btn_value_up, btn_value_down, btn_sens_left, btn_sens_right]:
		#if btn:
			#btn.disabled = is_locked
func _on_left_dpad_up() -> void:
	var main_manager = get_tree().get_first_node_in_group("main_manager")
	if main_manager and main_manager.is_menu_open:
		if main_manager.active_menu_kind == main_manager.MenuKind.SELECT_PASS:
			main_manager._step_select_pass_highlight(-1)
		elif main_manager.active_menu_kind == main_manager.MenuKind.SHADER_MENU:
			main_manager._step_fast_travel_selection(-1)
		return
		
	if parsed_uniforms.is_empty(): return
	active_index = posmod(active_index - 1, parsed_uniforms.size())
	active_sub_channel = 0
	update_status_readout()

func _on_left_dpad_down() -> void:
	var main_manager = get_tree().get_first_node_in_group("main_manager")
	if main_manager and main_manager.is_menu_open:
		if main_manager.active_menu_kind == main_manager.MenuKind.SELECT_PASS:
			main_manager._step_select_pass_highlight(1)
		elif main_manager.active_menu_kind == main_manager.MenuKind.SHADER_MENU:
			main_manager._step_fast_travel_selection(1)
		return
		
	if parsed_uniforms.is_empty(): return
	active_index = posmod(active_index + 1, parsed_uniforms.size())
	active_sub_channel = 0 
	update_status_readout()

func _on_left_dpad_left() -> void:
	var main_manager = get_tree().get_first_node_in_group("main_manager")
	if main_manager and main_manager.is_menu_open:
		if main_manager.active_menu_kind == main_manager.MenuKind.SELECT_PASS:
			main_manager.close_select_pass_menu(false)
		elif main_manager.active_menu_kind == main_manager.MenuKind.SHADER_MENU:
			main_manager.close_fast_travel_menu()
		refresh_menu_context_labels(false)
		return
		
	current_sens_index = max(0, current_sens_index - 1)
	sensitivity = sensitivity_presets[current_sens_index]
	update_status_readout()

func _on_left_dpad_right() -> void:
	var main_manager = get_tree().get_first_node_in_group("main_manager")
	if main_manager and main_manager.is_menu_open:
		if main_manager.active_menu_kind == main_manager.MenuKind.SELECT_PASS:
			main_manager.close_select_pass_menu(true)
			main_manager.open_select_pass_menu()
		elif main_manager.active_menu_kind == main_manager.MenuKind.SHADER_MENU:
			var old_index = main_manager.active_menu_index
			main_manager.close_fast_travel_menu()
			main_manager.open_fast_travel_menu()
			main_manager.active_menu_index = old_index
			main_manager.redraw_fast_travel_menu()
		refresh_menu_context_labels(true)
		return
		
	current_sens_index = min(sensitivity_presets.size() - 1, current_sens_index + 1)
	sensitivity = sensitivity_presets[current_sens_index]
	update_status_readout()

func _on_right_dpad_up() -> void:
	var main_manager = get_tree().get_first_node_in_group("main_manager")
	if main_manager and main_manager.is_menu_open:
		_on_left_dpad_up()
		return
	modify_active_value(1.0)

func _on_right_dpad_down() -> void:
	var main_manager = get_tree().get_first_node_in_group("main_manager")
	if main_manager and main_manager.is_menu_open:
		_on_left_dpad_down()
		return
	modify_active_value(-1.0)

func _on_right_dpad_left() -> void:
	var main_manager = get_tree().get_first_node_in_group("main_manager")
	if main_manager and main_manager.is_menu_open:
		if main_manager.active_menu_kind == main_manager.MenuKind.SELECT_PASS:
			main_manager.close_select_pass_menu(true)
			main_manager.open_select_pass_menu()
		elif main_manager.active_menu_kind == main_manager.MenuKind.SHADER_MENU:
			var old_index = main_manager.active_menu_index
			main_manager.close_fast_travel_menu()
			main_manager.open_fast_travel_menu()
			main_manager.active_menu_index = old_index
			main_manager.redraw_fast_travel_menu()
		refresh_menu_context_labels(true)
		return
	_on_left_dpad_left()

func _on_right_dpad_right() -> void:
	var main_manager = get_tree().get_first_node_in_group("main_manager")
	if main_manager and main_manager.is_menu_open:
		if main_manager.active_menu_kind == main_manager.MenuKind.SELECT_PASS:
			main_manager.close_select_pass_menu(false)
		elif main_manager.active_menu_kind == main_manager.MenuKind.SHADER_MENU:
			main_manager.close_fast_travel_menu()
		refresh_menu_context_labels(false)
		return
	_on_left_dpad_right()
		
	current_sens_index = min(sensitivity_presets.size() - 1, current_sens_index + 1)
	sensitivity = sensitivity_presets[current_sens_index]
	update_status_readout()
		
	current_sens_index = min(sensitivity_presets.size() - 1, current_sens_index + 1)
	sensitivity = sensitivity_presets[current_sens_index]
	update_status_readout()
		
	# Regular Mode: Raise sensitivity steps
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


	# The rest of your existing modify_active_value function remains the same:
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
	if suppress_status_readout: return
	if parsed_uniforms.is_empty(): return
	var active = parsed_uniforms[active_index]
	var u_type = active["type"]
	if u_type == "float": btn_channel.text = "FLOAT"
	else: btn_channel.text = "CH: %d" % active_sub_channel
	
	var p_name = active["name"]
	var sub_ch = get_sub_channel_name(u_type)
	var val_str = str(uniform_values[p_name])
	var sens_str = str(sensitivity)
	var desc_str = uniform_descriptions.get(p_name, "Adjustable hardware matrix parameter.")
	
	# Query the registered global group to dynamically find our current active pass layer index
	var layer_header: String = "[PASS 1: PATTERN]"
	var main_manager = get_tree().get_first_node_in_group("main_manager")
	if main_manager:
		match main_manager.get("active_shader_layer"):
			0: layer_header = "[PASS 1: PATTERN]"
			1: layer_header = "[PASS 2: WARP]"
			2: layer_header = "[PASS 3: FILTERS]"
	
	# --- UPGRADED REAL-TIME HUD STATUS STRING CONCATENATION ---
	label_status.text = "  %s  •  PARAM: %s (%s)%s  •  VALUE: %s  •  SENSITIVITY: %s  \nℹ️  %s  " % [
		layer_header, p_name, u_type, sub_ch, val_str, sens_str, desc_str
	]
	
	if label_sens_indicator:
		label_sens_indicator.text = sens_str
		
func refresh_menu_context_labels(menu_is_active: bool) -> void:
	if menu_is_active:
		# 🪞 Mirrored Layout Labels active while any overlay sits open
		btn_channel_prev.text = "❌\nEXIT"
		btn_channel_next.text = "✔\nACCEPT"
		btn_sens_left.text = "✔\nACCEPT"
		btn_sens_right.text = "❌\nEXIT"
	else:
		# Restore standard idle hardware dashboard labels when menus close
		btn_channel_prev.text = "◄\nCH"
		btn_channel_next.text = "CH\n►"
		btn_sens_left.text = "◄\nSENS"
		btn_sens_right.text = "SENS\n►"
