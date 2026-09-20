extends VBoxContainer



signal uniform_changed(name: String, value: Variant)
# 🌟 THE SEQUENTIAL HANDHELD 5-TIER ARCHITECTURE ENGINE STATES
enum ControlState { 
	HIDDEN, 
	TIER_1_PASS, 
	TIER_2_FORMULA,   # New recipe switchboard placeholder layer
	TIER_3_UNIFORM,   # Old Tier 2 Uniform List
	TIER_4_PARAMETER, # Old Tier 3 Sub-Channel Axis List
	TIER_5_TWEAK,     # Old Tier 4 Live Tweak Console Box
	SYSTEM_MENU
}

var active_state: int = ControlState.HIDDEN

# Cursor focus memory caches to remember selections when popping backwards with Button B
var last_tier1_index: int = 0  # Remembers focused Pass Layer Row
var last_tier2_index: int = 0  # Remembers focused Formula/Recipe Row
var last_tier3_index: int = 0  # Remembers focused Uniform Row (Index 0 = RESET ROW)
var last_tier4_index: int = 0  # Remembers focused Parameter/Channel Sub-Axis Row
var last_tier5_row: int = 0    # 0 = VALUE Row, 1 = SENSITIVITY Row

# System Power Menu cursor memory tracker
var system_menu_index: int = 0 # 0 = BACK, 1 = APP OPTIONS, 2 = EXIT GAME

# FUNCTION END: state_declarations



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
	# THE COMPACT HARDWARE CONTROL CONTAINER
	var chassis_stack = VBoxContainer.new()
	chassis_stack.alignment = BoxContainer.ALIGNMENT_CENTER
	chassis_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chassis_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(chassis_stack)

	# HIGH ROW: Centered horizontal box for A and B buttons
	var action_row = HBoxContainer.new()
	action_row.alignment = BoxContainer.ALIGNMENT_CENTER
	chassis_stack.add_child(action_row)

	# A Button (✔ ACCEPT)
	btn_channel = Button.new()
	btn_channel.text = "✔\n  A  "
	btn_channel.custom_minimum_size = Vector2(96, 96)
	btn_channel.add_theme_font_size_override("font_size", 13)
	btn_channel.add_theme_color_override("font_color", Color.GREEN)
	btn_channel.pressed.connect(_on_action_button_a) # Wired to Accept logic
	action_row.add_child(btn_channel)

	# Perfect visual axis alignment gap matching the structural width of the D-pad cross center
	var button_gap = Control.new()
	button_gap.custom_minimum_size = Vector2(96, 0)
	action_row.add_child(button_gap)

	# B Button (❌ BACK)
	btn_sens_left = Button.new()
	btn_sens_left.text = "❌\n  B  "
	btn_sens_left.custom_minimum_size = Vector2(96, 96)
	btn_sens_left.add_theme_font_size_override("font_size", 13)
	btn_sens_left.add_theme_color_override("font_color", Color.RED)
	btn_sens_left.pressed.connect(_on_action_button_b) # Wired to Exit/Back logic
	action_row.add_child(btn_sens_left)

	# THE LEFT SHIFT FILTER: Adding a small layout spacer on the right side of the row 
	var left_shift_spacer = Control.new()
	left_shift_spacer.custom_minimum_size = Vector2(24, 0)
	action_row.add_child(left_shift_spacer)

	# PUSH DPAD DOWN: Increased vertical separation gap between rows
	var vertical_spacer = Control.new()
	vertical_spacer.custom_minimum_size = Vector2(0, 24)
	chassis_stack.add_child(vertical_spacer)

	# LOW ROW: Singular 3x3 D-Pad Cross Grid
	var dpad_grid = GridContainer.new()
	dpad_grid.columns = 3
	chassis_stack.add_child(dpad_grid)

	# Row 1: Dead Space | UP | Dead Space
	dpad_grid.add_child(Control.new())
	btn_param_up = Button.new()
	btn_param_up.text = "▲"
	btn_param_up.custom_minimum_size = Vector2(96, 96)
	btn_param_up.add_theme_font_size_override("font_size", 20)
	btn_param_up.pressed.connect(_on_dpad_up) # Wired to Navigate Up
	dpad_grid.add_child(btn_param_up)
	dpad_grid.add_child(Control.new())

	# Row 2: LEFT | CENTER DISPLAY INDEX | RIGHT
	btn_channel_prev = Button.new()
	btn_channel_prev.text = "◄"
	btn_channel_prev.custom_minimum_size = Vector2(96, 96)
	btn_channel_prev.add_theme_font_size_override("font_size", 20)
	btn_channel_prev.pressed.connect(_on_dpad_left) # Wired to Cycle Left
	dpad_grid.add_child(btn_channel_prev)

	# Central informational readout node block
	label_sens_indicator = Label.new()
	label_sens_indicator.text = "" 
	label_sens_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_sens_indicator.custom_minimum_size = Vector2(96, 96)
	dpad_grid.add_child(label_sens_indicator)

	btn_channel_next = Button.new()
	btn_channel_next.text = "►"
	btn_channel_next.custom_minimum_size = Vector2(96, 96)
	btn_channel_next.add_theme_font_size_override("font_size", 20)
	btn_channel_next.pressed.connect(_on_dpad_right) # Wired to Cycle Right
	dpad_grid.add_child(btn_channel_next)

	# Row 3: Dead Space | DOWN | Dead Space
	dpad_grid.add_child(Control.new())
	btn_param_down = Button.new()
	btn_param_down.text = "▼"
	btn_param_down.custom_minimum_size = Vector2(96, 96)
	btn_param_down.add_theme_font_size_override("font_size", 20)
	btn_param_down.pressed.connect(_on_dpad_down) # Wired to Navigate Down
	dpad_grid.add_child(btn_param_down)
	dpad_grid.add_child(Control.new())



# Memory String Parser: Walks source strings to capture description tags
func load_shader_source(source_code: String) -> void:
	parsed_uniforms.clear()
	shader_categories.clear()
	
	var lines = source_code.split("\n")
	
	for line in lines:
		var trimmed = line.strip_edges()
		if trimmed.begins_with("uniform "):
			var clean_line = trimmed.replace(";", "").replace(":", " ")
			var tokens = clean_line.split(" ", false)
			
			if tokens.size() >= 3:
				var u_type = tokens[1]
				var u_raw_name = tokens[2]
				
				# 🌟 AUTOMATED DEFAULT EXTRACTION: Scan for inline code assignments
				var parsed_default_val: float = 0.0
				var u_name = u_raw_name
				
				if "=" in clean_line:
					var split_assignment = clean_line.split("=")
					u_name = split_assignment[0].replace("uniform", "").replace(u_type, "").strip_edges()
					var raw_assignment_value = split_assignment[1].strip_edges()
					
					# Extract numeric components for scalars vs vectors cleanly
					if u_type == "float":
						parsed_default_val = float(raw_assignment_value)
					elif u_type == "vec2" or u_type == "vec4":
						# Pull the very first component number inside brackets/vec parameters
						var cleaned_numbers = raw_assignment_value.replace("vec2", "").replace("vec4", "").replace("(", "").replace(")", "").split(",")
						if cleaned_numbers.size() > 0:
							parsed_default_val = float(cleaned_numbers[0].strip_edges())
				
				# 🛡️ EXCLUSION FILTER: Skip system textures and clock trackers completely
				if u_name == "u_time" or u_name == "u_pattern_texture" or u_name == "u_warped_texture" or u_type == "sampler2D":
					continue
				
				# Smart Sensitivity Automation matching based on target variables data architecture
				var recommended_sens: float = 0.01
				if u_name == "u_segments": recommended_sens = 1.0
				elif "speed" in u_name or "frequency" in u_name: recommended_sens = 0.05
				
				# Build out our comprehensive 5-Tier token blueprint card array
				var uniform_data = {
					"name": u_name,
					"type": u_type,
					"display_name": u_name.replace("u_", "").replace("_", " ").to_upper(),
					"default_value": parsed_default_val,
					"default_sensitivity": recommended_sens
				}
				
				parsed_uniforms.append(uniform_data)
				
				var category_label = "PARAMETERS"
				if not shader_categories.has(category_label):
					shader_categories[category_label] = u_name

	print("🔌 GLSL Auto-Parser Cached %d Uniforms with Default Reference Baselines!" % parsed_uniforms.size())

# FUNCTION END: load_shader_source
func _on_dpad_up() -> void:
	var main_manager = get_tree().get_first_node_in_group("main_manager")
	if not main_manager or active_state == ControlState.HIDDEN: return
	
	match active_state:
		ControlState.SYSTEM_MENU:
			system_menu_index = posmod(system_menu_index - 1, 3)
			main_manager.redraw_system_power_menu()
		ControlState.TIER_1_PASS:
			if main_manager.active_menu_kind == main_manager.MenuKind.SELECT_PASS:
				main_manager._step_select_pass_highlight(-1)
		ControlState.TIER_2_FORMULA:
			# 🌟 SCROLL UP TIMING: Run the formula array step increments cleanly
			main_manager._step_formula_selection(-1)
		ControlState.TIER_3_UNIFORM:
			if main_manager.active_menu_kind == main_manager.MenuKind.SHADER_MENU:
				main_manager._step_fast_travel_selection(-1)
		ControlState.TIER_4_PARAMETER:
			if parsed_uniforms.is_empty(): return
			var max_channels = 2 if parsed_uniforms[active_index]["type"] == "vec2" else 4
			last_tier4_index = posmod(last_tier4_index - 1, max_channels)
			main_manager.open_parameter_select_menu()
		ControlState.TIER_5_TWEAK:
			last_tier5_row = posmod(last_tier5_row - 1, 2)
			main_manager.open_live_tweak_console()

func _on_dpad_down() -> void:
	var main_manager = get_tree().get_first_node_in_group("main_manager")
	if not main_manager or active_state == ControlState.HIDDEN: return
	
	match active_state:
		ControlState.SYSTEM_MENU:
			system_menu_index = posmod(system_menu_index + 1, 3)
			main_manager.redraw_system_power_menu()
		ControlState.TIER_1_PASS:
			if main_manager.active_menu_kind == main_manager.MenuKind.SELECT_PASS:
				main_manager._step_select_pass_highlight(1)
		ControlState.TIER_2_FORMULA:
			# 🌟 SCROLL DOWN TIMING: Run the formula array step increments cleanly
			main_manager._step_formula_selection(1)
		ControlState.TIER_3_UNIFORM:
			if main_manager.active_menu_kind == main_manager.MenuKind.SHADER_MENU:
				main_manager._step_fast_travel_selection(1)
		ControlState.TIER_4_PARAMETER:
			if parsed_uniforms.is_empty(): return
			var max_channels = 2 if parsed_uniforms[active_index]["type"] == "vec2" else 4
			last_tier4_index = posmod(last_tier4_index + 1, max_channels)
			main_manager.open_parameter_select_menu()
		ControlState.TIER_5_TWEAK:
			last_tier5_row = posmod(last_tier5_row + 1, 2)
			main_manager.open_live_tweak_console()

# FUNCTION END: vertical_dpad_handlers


func _on_dpad_left() -> void:
	var main_manager = get_tree().get_first_node_in_group("main_manager")
	if not main_manager or active_state == ControlState.HIDDEN: return
	
	match active_state:
		ControlState.TIER_5_TWEAK:
			if last_tier5_row == 0:
				modify_active_value(-1.0)
			else:
				current_sens_index = max(0, current_sens_index - 1)
				sensitivity = sensitivity_presets[current_sens_index]
			main_manager.open_live_tweak_console()


func _on_dpad_right() -> void:
	var main_manager = get_tree().get_first_node_in_group("main_manager")
	if not main_manager or active_state == ControlState.HIDDEN: return
	
	match active_state:
		ControlState.TIER_5_TWEAK:
			if last_tier5_row == 0:
				modify_active_value(1.0)
			else:
				current_sens_index = min(sensitivity_presets.size() - 1, current_sens_index + 1)
				sensitivity = sensitivity_presets[current_sens_index]
			main_manager.open_live_tweak_console()

func _on_action_button_b() -> void:
	# 🌟 5-TIER SEQUENTIAL OVERHAUL: POP BACKWARDS ROUTER
	var main_manager = get_tree().get_first_node_in_group("main_manager")
	if not main_manager: return
	
	match active_state:
		ControlState.SYSTEM_MENU:
			print("⚙️ System: Closing Main Power Menu overlay")
			active_state = ControlState.HIDDEN
			if main_manager.menu_overlay_panel and is_instance_valid(main_manager.menu_overlay_panel):
				main_manager.menu_overlay_panel.queue_free()
				main_manager.menu_overlay_panel = null
			main_manager.menu_center_host.visible = false

		ControlState.TIER_5_TWEAK:
			print("🎮 Hierarchy Pop: TIER_5_TWEAK -> TIER_4_PARAMETER")
			active_state = ControlState.TIER_4_PARAMETER
			main_manager.open_parameter_select_menu()

		ControlState.TIER_4_PARAMETER:
			print("🎮 Hierarchy Pop: TIER_4_PARAMETER -> TIER_3_UNIFORM")
			active_state = ControlState.TIER_3_UNIFORM
			main_manager.open_fast_travel_menu()

		ControlState.TIER_3_UNIFORM:
			print("🎮 Hierarchy Pop: TIER_3_UNIFORM -> TIER_2_FORMULA")
			# 🌟 Drop backward into the Recipe selection list cleanly
			active_state = ControlState.TIER_2_FORMULA
			main_manager.open_formula_select_menu()

		ControlState.TIER_2_FORMULA:
			print("🎮 Hierarchy Pop: TIER_2_FORMULA -> TIER_1_PASS")
			# 🌟 Delete the cyan container frame completely before restoring Tier 1's unique orange frame
			if main_manager.menu_overlay_panel and is_instance_valid(main_manager.menu_overlay_panel):
				main_manager.menu_overlay_panel.queue_free()
				main_manager.menu_overlay_panel = null
				main_manager.menu_list_box = null
				
			active_state = ControlState.TIER_1_PASS
			main_manager.open_select_pass_menu()

		ControlState.TIER_1_PASS:
			print("Keep App Open: Collapsing overlay display to hidden dashboard frame")
			active_state = ControlState.HIDDEN
			if main_manager.select_pass_overlay_panel and is_instance_valid(main_manager.select_pass_overlay_panel):
				main_manager.select_pass_overlay_panel.queue_free()
				main_manager.select_pass_overlay_panel = null
			main_manager.menu_center_host.visible = false

		ControlState.HIDDEN:
			return

# FUNCTION END: _on_action_button_b

func _on_action_button_a() -> void:
	# 🌟 RECIPE TOKENS SYNC OVERHAUL: Enforces direct escape cutoffs inside Tier 2
	var main_manager = get_tree().get_first_node_in_group("main_manager")
	if not main_manager: return
	
	match active_state:
		ControlState.HIDDEN:
			return

		ControlState.SYSTEM_MENU:
			match system_menu_index:
				0: _on_action_button_b()
				1: print("⚙️ System Action: Open options panels context configuration")
				2: get_tree().quit()

		ControlState.TIER_1_PASS:
			print("🎮 Hierarchy Push: TIER_1_PASS -> TIER_2_FORMULA")
			active_state = ControlState.TIER_2_FORMULA
			main_manager.close_select_pass_menu(true)
			last_tier2_index = 0 
			main_manager.open_formula_select_menu()

		ControlState.TIER_2_FORMULA:
			print("🎮 Hierarchy Push: TIER_2_FORMULA Target Ingestion -> Pass: %d, Recipe Row: %d" % [last_tier1_index, last_tier2_index])
			
			# 🌟 INSIGHT 1 CUTOFF FIX: If selecting Row 0 (RESET ACTIVE FORMULA), compile the glass shader 
			# and immediately drop back to safety without advancing the navigation state deeper!
			if last_tier2_index == 0:
				print("🧹 Hardware Trigger: Resetting active formula back to clear window glass")
				var glass_shader = Shader.new()
				if last_tier1_index == 1:
					glass_shader.code = "shader_type canvas_item; uniform sampler2D u_pattern_texture; void fragment() { COLOR = texture(u_pattern_texture, UV); }"
					main_manager.pass2_material.shader = glass_shader
					main_manager.pass2_material.set_shader_parameter("u_pattern_texture", main_manager.pass1_viewport.get_texture())
				elif last_tier1_index == 2:
					glass_shader.code = "shader_type canvas_item; uniform sampler2D u_warped_texture; void fragment() { COLOR = texture(u_warped_texture, UV); }"
					main_manager.pass3_material.shader = glass_shader
					main_manager.pass3_material.set_shader_parameter("u_warped_texture", main_manager.pass2_viewport.get_texture())
				
				# Keep the user safely right here on the Tier 2 selection screen and force a text-mode refresh
				load_shader_source(glass_shader.code)
				main_manager.redraw_formula_select_menu()
				return # 🌟 Hard break prevents pushing down to Tier 3!
			
			var target_shader_code: String = ""
			
			match last_tier1_index:
				0: # PASS 1: Base Patterns
					target_shader_code = main_manager.pass1_material.shader.code
				1: # PASS 2: Geometric Warping
					var new_shader = Shader.new()
					if last_tier2_index == 1:
						print("🔌 Injecting: Pass 2 Real Kaleidoscope Math text string")
						target_shader_code = main_manager.real_p2_source
					
					new_shader.code = target_shader_code
					main_manager.pass2_material.shader = new_shader
					main_manager.pass2_material.set_shader_parameter("u_pattern_texture", main_manager.pass1_viewport.get_texture())
				2: # PASS 3: Post-Process Filters
					var new_shader = Shader.new()
					if last_tier2_index == 1:
						print("🔌 Injecting: Pass 3 Real Edge Glow Filter text string")
						target_shader_code = main_manager.real_p3_source
					
					new_shader.code = target_shader_code
					main_manager.pass3_material.shader = new_shader
					main_manager.pass3_material.set_shader_parameter("u_warped_texture", main_manager.pass2_viewport.get_texture())
			
			# Feed the direct code block string variable straight into the tokenizer parser cache
			load_shader_source(target_shader_code)
					
			# Advance player context straight down to Tier 3's clean Uniform listings view
			active_state = ControlState.TIER_3_UNIFORM
			last_tier3_index = 0 
			main_manager.open_fast_travel_menu()

		ControlState.TIER_3_UNIFORM:
			if last_tier3_index == 0:
				print("🧹 Hardware Trigger: Executing [ RESET ACTIVE EFFECTS ] arithmetic")
				return
				
			if parsed_uniforms.is_empty(): return
			print("🎮 Hierarchy Push: TIER_3_UNIFORM -> TIER_4_PARAMETER")
			active_state = ControlState.TIER_4_PARAMETER
			active_index = last_tier3_index - 1
			last_tier4_index = 0 
			main_manager.open_parameter_select_menu()

		ControlState.TIER_4_PARAMETER:
			print("🎮 Hierarchy Push: TIER_4_PARAMETER -> TIER_5_TWEAK")
			active_state = ControlState.TIER_5_TWEAK
			last_tier5_row = 0
			main_manager.open_live_tweak_console()

		ControlState.TIER_5_TWEAK:
			return

# FUNCTION END: _on_action_button_a







#func _on_right_dpad_up() -> void:
	#var main_manager = get_tree().get_first_node_in_group("main_manager")
	#if main_manager and main_manager.is_menu_open:
		#_on_dpad_up()
		#return
	#modify_active_value(1.0)
#
#func _on_right_dpad_down() -> void:
	#var main_manager = get_tree().get_first_node_in_group("main_manager")
	#if main_manager and main_manager.is_menu_open:
		#_on_dpad_down()
		#return
	#modify_active_value(-1.0)




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
	
	if not uniform_values.has(u_name):
		if u_type == "float": uniform_values[u_name] = 0.0
		elif u_type == "vec2": uniform_values[u_name] = Vector2.ZERO
		elif u_type == "vec4": uniform_values[u_name] = Color.BLACK
	
	if u_type == "float":
		uniform_values[u_name] += applied_change
		uniform_changed.emit(u_name, uniform_values[u_name])
	elif u_type == "vec2":
		var vec = uniform_values[u_name] as Vector2
		if last_tier4_index == 0: vec.x += applied_change
		else: vec.y += applied_change
		uniform_values[u_name] = vec # 🌟 THE SYNC: Re-cache the mutated Vector data straight back into the map key
		uniform_changed.emit(u_name, uniform_values[u_name])
	elif u_type == "vec4":
		var col = uniform_values[u_name] as Color
		if last_tier4_index == 0: col.r = clamp(col.r + applied_change, 0.0, 1.0)
		elif last_tier4_index == 1: col.g = clamp(col.g + applied_change, 0.0, 1.0)
		elif last_tier4_index == 2: col.b = clamp(col.b + applied_change, 0.0, 1.0)
		elif last_tier4_index == 3: col.a = clamp(col.a + applied_change, 0.0, 1.0)
		uniform_values[u_name] = col # 🌟 THE SYNC: Re-cache the mutated Color data straight back into the map key
		uniform_changed.emit(u_name, uniform_values[u_name])
	update_status_readout()

# FUNCTION END: modify_active_value



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
		
func refresh_menu_context_labels(_menu_is_active: bool) -> void:
	# 🌟 Safe Empty Stub: Stripped legacy text swapping to protect the single-thumb layout
	pass
