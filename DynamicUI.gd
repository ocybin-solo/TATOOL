extends VBoxContainer



signal uniform_changed(name: String, value: Variant)
# 🌟 THE FOUR CORE INPUT STATES FOR THE HANDHELD CHASSIS
enum ControlState { HIDDEN, MENU_NAVIGATION, VECTOR_EXPANSION, VALUE_EDITING }
var active_state: int = ControlState.HIDDEN # Starts with the menu hidden

# Focus memory trackers to remember where your cursor was last sitting
var last_menu_tab_index: int = 0 # 0 = Pass, 1 = Shader, 2 = Param



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
func _on_dpad_up() -> void:
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

func _on_dpad_down() -> void:
	var main_manager = get_tree().get_first_node_in_group("main_manager")
	if not main_manager: return
	
	match active_state:
		ControlState.MENU_NAVIGATION:
			# 1. Menu Scrolling: Move selection down based on which menu is active
			if main_manager.active_menu_kind == main_manager.MenuKind.SELECT_PASS:
				main_manager._step_select_pass_highlight(1)
			elif main_manager.active_menu_kind == main_manager.MenuKind.SHADER_MENU:
				main_manager._step_fast_travel_selection(1)
				
		ControlState.VECTOR_EXPANSION:
			# 2. Vector Sub-Channel Cycling: Move through sub-dimensions (X, Y, etc.)
			var max_channels = 2 if parsed_uniforms[active_index]["type"] == "vec2" else 4
			active_sub_channel = posmod(active_sub_channel + 1, max_channels)
			update_status_readout()
			
		ControlState.VALUE_EDITING:
			# 3. Value Tweaking: Shift shader parameter numbers downward
			modify_active_value(-1.0)


func _on_action_button_b() -> void:
	# 🌟 THE (B) BUTTON CONTROL ROUTER (CANCEL / BACK / HIDE)
	var main_manager = get_tree().get_first_node_in_group("main_manager")
	if not main_manager: return
	
	match active_state:
		ControlState.VALUE_EDITING:
			# 1. If editing a parameter value, exit edit mode and lock it back into list navigation
			print("🎮 State Transition: VALUE_EDITING -> MENU_NAVIGATION")
			active_state = ControlState.MENU_NAVIGATION
			# Keep labels showing emoji guidance for menu navigation
			refresh_menu_context_labels(true)
			
		ControlState.VECTOR_EXPANSION:
			# 2. If viewing expanded channels (like [X] or [Y]), collapse them back to the main parameter list
			print("🎮 State Transition: VECTOR_EXPANSION -> MENU_NAVIGATION")
			active_state = ControlState.MENU_NAVIGATION
			
		ControlState.MENU_NAVIGATION:
			# 3. If navigating lists, close the overlays entirely and hide the interface card
			print("🎮 State Transition: MENU_NAVIGATION -> HIDDEN")
			active_state = ControlState.HIDDEN
			
			# Call the clean-up routines on MainManager to pull down overlays
			if main_manager.active_menu_kind == main_manager.MenuKind.SELECT_PASS:
				main_manager.close_select_pass_menu(false)
			elif main_manager.active_menu_kind == main_manager.MenuKind.SHADER_MENU:
				main_manager.close_fast_travel_menu()
				
			refresh_menu_context_labels(false) # Restore regular idle dashboard labels
			
		ControlState.HIDDEN:
			# 4. If already hidden, pressing B acts as a wake-up trigger to restore menu view
			print("🎮 State Transition: HIDDEN -> MENU_NAVIGATION")
			active_state = ControlState.MENU_NAVIGATION
			
			# Re-open whichever menu tab was last remembered by the system cache
			match last_menu_tab_index:
				0, 1: main_manager.open_select_pass_menu() # Pass/Shader menu tabs
				2: main_manager.open_fast_travel_menu() # Parameter list tab
			
			refresh_menu_context_labels(true) # Activate green/red emoji guidelines

# FUNCTION END: _on_left_dpad_left

		
	current_sens_index = max(0, current_sens_index - 1)
	sensitivity = sensitivity_presets[current_sens_index]
	update_status_readout()

func _on_action_button_a() -> void:
	# 🌟 THE (A) BUTTON CONTROL ROUTER (SELECT / CONFIRM / ENTER EDIT)
	var main_manager = get_tree().get_first_node_in_group("main_manager")
	if not main_manager: return
	
	match active_state:
		ControlState.HIDDEN:
			# If hidden, the A button is locked out to prevent accidental pattern changes
			return
			
		ControlState.MENU_NAVIGATION:
			# If scrolling column items, look up what row item is highlighted
			if main_manager.active_menu_kind == main_manager.MenuKind.SELECT_PASS:
				# 1. If on the Pass Layer menu, apply selection immediately without closing view
				print("🎮 Action: Confirming Pass Layer selection without closing menu card")
				main_manager.close_select_pass_menu(true) # Apply pass selection variables
				main_manager.open_select_pass_menu() # Re-open layout stack immediately
				
			elif main_manager.active_menu_kind == main_manager.MenuKind.SHADER_MENU:
				# 2. If on a parameter row, check if it is a multi-channel vector
				if parsed_uniforms.is_empty(): return
				var active_uniform = parsed_uniforms[active_index]
				var u_type = active_uniform["type"]
				
				if u_type == "vec2" or u_type == "vec4":
					# Has sub-variables! Expand inline into the Vector sub-menu state
					print("🎮 State Transition: MENU_NAVIGATION -> VECTOR_EXPANSION")
					active_state = ControlState.VECTOR_EXPANSION
					active_sub_channel = 0
				else:
					# Standard float variable. Enter Value Editing mode directly
					print("🎮 State Transition: MENU_NAVIGATION -> VALUE_EDITING")
					active_state = ControlState.VALUE_EDITING
					
			refresh_menu_context_labels(true)
			
		ControlState.VECTOR_EXPANSION:
			# 3. If currently selecting a specific sub-channel vector coordinate row, enter Edit Mode on it
			print("🎮 State Transition: VECTOR_EXPANSION -> VALUE_EDITING")
			active_state = ControlState.VALUE_EDITING
			refresh_menu_context_labels(true)
			
		ControlState.VALUE_EDITING:
			# 4. If already in value editing mode, pressing A acts as a lock/save confirmation shortcut
			print("🎮 Action: Saving value adjustments and locking parameters")
			active_state = ControlState.MENU_NAVIGATION
			refresh_menu_context_labels(true)

# FUNCTION END: _on_left_dpad_right

		
	current_sens_index = min(sensitivity_presets.size() - 1, current_sens_index + 1)
	sensitivity = sensitivity_presets[current_sens_index]
	update_status_readout()

func _on_right_dpad_up() -> void:
	var main_manager = get_tree().get_first_node_in_group("main_manager")
	if main_manager and main_manager.is_menu_open:
		_on_dpad_up()
		return
	modify_active_value(1.0)

func _on_right_dpad_down() -> void:
	var main_manager = get_tree().get_first_node_in_group("main_manager")
	if main_manager and main_manager.is_menu_open:
		_on_dpad_down()
		return
	modify_active_value(-1.0)

func _on_dpad_left() -> void:
	var main_manager = get_tree().get_first_node_in_group("main_manager")
	if not main_manager: return
	
	match active_state:
		ControlState.MENU_NAVIGATION:
			# 1. Column Cycling: Shift left between the three core menu tabs
			last_menu_tab_index = posmod(last_menu_tab_index - 1, 3)
			print("🎮 Column Navigation: Shift Left. Tab Index: ", last_menu_tab_index)
			
			# Cycle open handlers based on tab memory index maps
			if last_menu_tab_index == 0 or last_menu_tab_index == 1:
				main_manager.open_select_pass_menu()
			elif last_menu_tab_index == 2:
				main_manager.open_fast_travel_menu()
				
		ControlState.VALUE_EDITING:
			# 2. Precision Tuning: Step sensitivity presets down (coarser steps)
			current_sens_index = max(0, current_sens_index - 1)
			sensitivity = sensitivity_presets[current_sens_index]
			update_status_readout()

func _on_dpad_right() -> void:
	var main_manager = get_tree().get_first_node_in_group("main_manager")
	if not main_manager: return
	
	match active_state:
		ControlState.MENU_NAVIGATION:
			# 1. Column Cycling: Shift right between the three core menu tabs
			last_menu_tab_index = posmod(last_menu_tab_index + 1, 3)
			print("🎮 Column Navigation: Shift Right. Tab Index: ", last_menu_tab_index)
			
			# Cycle open handlers based on tab memory index maps
			if last_menu_tab_index == 0 or last_menu_tab_index == 1:
				main_manager.open_select_pass_menu()
			elif last_menu_tab_index == 2:
				main_manager.open_fast_travel_menu()
				
		ControlState.VALUE_EDITING:
			# 2. Precision Tuning: Step sensitivity presets up (finer steps)
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
		
func refresh_menu_context_labels(_menu_is_active: bool) -> void:
	# 🌟 Safe Empty Stub: Stripped legacy text swapping to protect the single-thumb layout
	pass
