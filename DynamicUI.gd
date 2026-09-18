extends VBoxContainer

signal uniform_changed(name: String, value: Variant)

# Stores Category Names linked to the first uniform variable inside them
var shader_categories: Dictionary = {}

var parsed_uniforms: Array = []
var active_index: int = 0
var sensitivity: float = 1.0
var sensitivity_presets: Array = [0.01, 0.1, 1.0, 5.0, 10.0]
var current_sens_index: int = 2
var active_sub_channel: int = 0
var uniform_values: Dictionary = {}
var is_input_blocked: bool = false

# Dictionary cache linking variable names directly to their parsed comments
var uniform_descriptions: Dictionary = {}

var left_upper_dock: PanelContainer
var right_upper_dock: PanelContainer
var active_color_picker: ColorPicker

# Node Layout references
var label_status: Label
var label_sens_indicator: Label 
var input_row_container: HBoxContainer
var btn_channel: Button

# Focused Sub-Group states
var current_active_category: String = ""
var active_category_uniforms: Array = []
var relative_category_index: int = 0

func _ready() -> void:
	setup_ui_layout()

func setup_ui_layout() -> void:
	label_status = Label.new()
	label_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_status.text = "Please choose an option in the 'Shader Menu'"
	add_child(label_status)
	
	input_row_container = HBoxContainer.new()
	input_row_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	input_row_container.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(input_row_container)
	
	var btn_size = Vector2(66, 66)
	var pad_total_width = 66 * 3 
	
	var left_spacer = Control.new()
	left_spacer.custom_minimum_size = Vector2(50, 0)
	input_row_container.add_child(left_spacer)
	
	# =========================================================================
	# COLUMN 1: LEFT WING STACK (Upper Dock + Left D-Pad Navigation)
	# =========================================================================
	var left_wing_stack = VBoxContainer.new()
	left_wing_stack.alignment = BoxContainer.ALIGNMENT_END 
	input_row_container.add_child(left_wing_stack)
	
	# ✅ PLAN INTEGRATION: Collapsible dynamic layout (custom_minimum_size initialized to 0)
	left_upper_dock = PanelContainer.new()
	left_upper_dock.custom_minimum_size = Vector2(pad_total_width, 0) 
	left_upper_dock.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	left_upper_dock.mouse_filter = Control.MOUSE_FILTER_PASS
	left_upper_dock.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	left_wing_stack.add_child(left_upper_dock)
	
	var nav_grid = GridContainer.new()
	nav_grid.columns = 3
	nav_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	left_wing_stack.add_child(nav_grid)
	
	nav_grid.add_child(Control.new())
	var btn_p_up = Button.new()
	btn_p_up.text = "PARAM\n▲"
	btn_p_up.custom_minimum_size = btn_size
	btn_p_up.pressed.connect(_on_left_dpad_up)
	nav_grid.add_child(btn_p_up)
	nav_grid.add_child(Control.new())
	
	var btn_ch_prev = Button.new()
	btn_ch_prev.text = "◄\nCH"
	btn_ch_prev.custom_minimum_size = btn_size
	btn_ch_prev.pressed.connect(_on_left_dpad_left)
	nav_grid.add_child(btn_ch_prev)
	
	btn_channel = Button.new()
	btn_channel.text = "CH: 0"
	btn_channel.custom_minimum_size = btn_size
	btn_channel.disabled = true
	nav_grid.add_child(btn_channel)
	var btn_ch_next = Button.new()
	btn_ch_next.text = "CH\n►"
	btn_ch_next.custom_minimum_size = btn_size
	btn_ch_next.pressed.connect(_on_left_dpad_right)
	nav_grid.add_child(btn_ch_next)
	
	nav_grid.add_child(Control.new())
	var btn_p_down = Button.new()
	btn_p_down.text = "▼\nPARAM"
	btn_p_down.custom_minimum_size = btn_size
	btn_p_down.pressed.connect(_on_left_dpad_down)
	nav_grid.add_child(btn_p_down)
	nav_grid.add_child(Control.new())
	
	# Central expanding spacer
	var middle_expanding_spacer = Control.new()
	middle_expanding_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_row_container.add_child(middle_expanding_spacer)
	
	# =========================================================================
	# COLUMN 2: RIGHT WING STACK (Right Upper Dock + Right D-Pad Modifiers)
	# =========================================================================
	var right_wing_stack = VBoxContainer.new()
	right_wing_stack.alignment = BoxContainer.ALIGNMENT_END
	input_row_container.add_child(right_wing_stack)
	
	# ✅ PLAN INTEGRATION: Collapsible dynamic layout (custom_minimum_size initialized to 0)
	right_upper_dock = PanelContainer.new()
	right_upper_dock.custom_minimum_size = Vector2(pad_total_width, 0)
	right_upper_dock.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	right_upper_dock.mouse_filter = Control.MOUSE_FILTER_PASS
	right_upper_dock.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	right_wing_stack.add_child(right_upper_dock)
	
	var val_grid = GridContainer.new()
	val_grid.columns = 3
	val_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	right_wing_stack.add_child(val_grid)
	
	val_grid.add_child(Control.new())
	var btn_val_up = Button.new()
	btn_val_up.text = "VALUE\n▲"
	btn_val_up.custom_minimum_size = btn_size
	btn_val_up.pressed.connect(_on_right_dpad_up)
	val_grid.add_child(btn_val_up)
	val_grid.add_child(Control.new())
	
	var btn_sens_down = Button.new()
	btn_sens_down.text = "◄\nSENS"
	btn_sens_down.custom_minimum_size = btn_size
	btn_sens_down.pressed.connect(_on_right_dpad_left)
	val_grid.add_child(btn_sens_down)
	
	label_sens_indicator = Label.new()
	label_sens_indicator.text = "1.0"
	label_sens_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val_grid.add_child(label_sens_indicator)
	
	var btn_sens_up = Button.new()
	btn_sens_up.text = "SENS\n►"
	btn_sens_up.custom_minimum_size = btn_size
	btn_sens_up.pressed.connect(_on_right_dpad_right)
	val_grid.add_child(btn_sens_up)
	
	val_grid.add_child(Control.new())
	var btn_val_down = Button.new()
	btn_val_down.text = "▼\nVALUE"
	btn_val_down.custom_minimum_size = btn_size
	btn_val_down.pressed.connect(_on_right_dpad_down)
	val_grid.add_child(btn_val_down)
	val_grid.add_child(Control.new())
	
	var right_spacer = Control.new()
	right_spacer.custom_minimum_size = Vector2(50, 0)
	input_row_container.add_child(right_spacer)

func apply_orientation_layout_shift(_to_portrait: bool, target_top_container: PanelContainer) -> void:
	if label_status.get_parent():
		label_status.get_parent().remove_child(label_status)
	target_top_container.add_child(label_status)
	update_status_readout()

# =========================================================================
# 🕹️ UNIFIED UNMANAGED HARDWARE DIRECT DIRECTIONAL SPACE ROUTING LINKS
# =========================================================================

func _on_left_dpad_up() -> void:
	var main_manager = get_tree().get_first_node_in_group("main_manager")
	# ✅ DUAL D-PAD SELECTION LINK: Permits navigation via either thumb while open
	if main_manager and main_manager.get("is_menu_open"):
		main_manager.active_menu_index = posmod(main_manager.active_menu_index - 1, main_manager.active_menu_categories.size())
		main_manager.redraw_shader_menu()
		return

	var target_list = active_category_uniforms if not active_category_uniforms.is_empty() else parsed_uniforms
	if target_list.is_empty(): return
	
	relative_category_index = posmod(relative_category_index - 1, target_list.size())
	var chosen_uniform_name = target_list[relative_category_index]["name"]
	for idx in range(parsed_uniforms.size()):
		if parsed_uniforms[idx]["name"] == chosen_uniform_name:
			active_index = idx
			break
			
	active_sub_channel = 0
	update_status_readout()

func _on_left_dpad_down() -> void:
	var main_manager = get_tree().get_first_node_in_group("main_manager")
	if main_manager and main_manager.get("is_menu_open"):
		main_manager.active_menu_index = posmod(main_manager.active_menu_index + 1, main_manager.active_menu_categories.size())
		main_manager.redraw_shader_menu()
		return

	var target_list = active_category_uniforms if not active_category_uniforms.is_empty() else parsed_uniforms
	if target_list.is_empty(): return
	
	relative_category_index = posmod(relative_category_index + 1, target_list.size())
	var chosen_uniform_name = target_list[relative_category_index]["name"]
	for idx in range(parsed_uniforms.size()):
		if parsed_uniforms[idx]["name"] == chosen_uniform_name:
			active_index = idx
			break
			
	active_sub_channel = 0
	update_status_readout()

func _on_left_dpad_left() -> void:
	# 🔒 SHADER MENU PARAMETER MANIPULATION LOCK
	var main_manager = get_tree().get_first_node_in_group("main_manager")
	if main_manager and main_manager.get("is_menu_open"): return

	if parsed_uniforms.is_empty(): return
	var u_type = parsed_uniforms[active_index]["type"]
	if u_type == "vec2": active_sub_channel = posmod(active_sub_channel - 1, 2)
	elif u_type == "vec4": active_sub_channel = posmod(active_sub_channel - 1, 4)
	else: active_sub_channel = 0
	update_status_readout()

func _on_left_dpad_right() -> void:
	# 🔒 SHADER MENU PARAMETER MANIPULATION LOCK
	var main_manager = get_tree().get_first_node_in_group("main_manager")
	if main_manager and main_manager.get("is_menu_open"): return

	if parsed_uniforms.is_empty(): return
	var u_type = parsed_uniforms[active_index]["type"]
	if u_type == "vec2": active_sub_channel = posmod(active_sub_channel + 1, 2)
	elif u_type == "vec4": active_sub_channel = posmod(active_sub_channel + 1, 4)
	else: active_sub_channel = 0
	update_status_readout()
func _on_right_dpad_up() -> void:
	var main_manager = get_tree().get_first_node_in_group("main_manager")
	if main_manager and main_manager.get("is_menu_open"):
		main_manager.active_menu_index = posmod(main_manager.active_menu_index - 1, main_manager.active_menu_categories.size())
		main_manager.redraw_shader_menu()
		return
	modify_active_value(1.0)

func _on_right_dpad_down() -> void:
	var main_manager = get_tree().get_first_node_in_group("main_manager")
	if main_manager and main_manager.get("is_menu_open"):
		main_manager.active_menu_index = posmod(main_manager.active_menu_index + 1, main_manager.active_menu_categories.size())
		main_manager.redraw_shader_menu()
		return
	modify_active_value(-1.0)

func _on_right_dpad_left() -> void:
	# 🔒 SHADER MENU PARAMETER MANIPULATION LOCK
	var main_manager = get_tree().get_first_node_in_group("main_manager")
	if main_manager and main_manager.get("is_menu_open"): return

	current_sens_index = max(0, current_sens_index - 1)
	sensitivity = sensitivity_presets[current_sens_index]
	update_status_readout()

func _on_right_dpad_right() -> void:
	# 🔒 SHADER MENU PARAMETER MANIPULATION LOCK
	var main_manager = get_tree().get_first_node_in_group("main_manager")
	if main_manager and main_manager.get("is_menu_open"): return

	current_sens_index = min(sensitivity_presets.size() - 1, current_sens_index + 1)
	sensitivity = sensitivity_presets[current_sens_index]
	update_status_readout()

func modify_active_value(direction_multiplier: float) -> void:
	if is_input_blocked: return
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
func load_shader_source(shader_code: String) -> void:
	parsed_uniforms.clear()
	uniform_values.clear()
	uniform_descriptions.clear()
	shader_categories.clear() 
	
	var lines = shader_code.split("\n")
	var active_cached_desc: String = ""
	var active_cached_cat: String = "🌀 GENERAL CONTROLS" 
	
	for line in lines:
		var trimmed = line.strip_edges()
		if trimmed.begins_with("// CAT:"):
			active_cached_cat = trimmed.replace("// CAT:", "").strip_edges()
			continue
		if trimmed.begins_with("// DESC:"):
			active_cached_desc = trimmed.replace("// DESC:", "").strip_edges()
			continue
			
		if trimmed.contains("uniform"):
			var regex = RegEx.new()
			regex.compile("uniform\\s+(float|vec2|vec4)\\s+(\\w+)")
			var result = regex.search(trimmed)
			
			if result:
				var u_type = result.get_string(1)
				var u_name = result.get_string(2)
				
				if u_name == "u_time" or u_name == "u_pattern_texture" or u_name == "u_warped_texture" or u_name == "manual_time": 
					continue
				
				var uniform_data = {"name": u_name, "type": u_type}
				parsed_uniforms.append(uniform_data)
				
				if not shader_categories.has(active_cached_cat):
					shader_categories[active_cached_cat] = []
				shader_categories[active_cached_cat].append(uniform_data)
				
				if active_cached_desc != "":
					uniform_descriptions[u_name] = active_cached_desc
					active_cached_desc = ""
				else:
					uniform_descriptions[u_name] = "Analog variable adjustment channel link."
				
				if u_type == "float" and not uniform_values.has(u_name): uniform_values[u_name] = 0.0
				elif u_type == "vec2" and not uniform_values.has(u_name): uniform_values[u_name] = Vector2(0.0, 0.0)
				elif u_type == "vec4" and not uniform_values.has(u_name): uniform_values[u_name] = Color.CYAN

	if shader_categories.is_empty() and not parsed_uniforms.is_empty():
		shader_categories["🌀 GENERAL CONTROLS"] = parsed_uniforms.duplicate()
		
	update_status_readout()

func update_status_readout() -> void:
	var layer_header: String = "[PASS 1: PATTERN]"
	var main_manager = get_tree().get_first_node_in_group("main_manager")
	
	if main_manager:
		match main_manager.get("active_shader_layer"):
			0: layer_header = "[PASS 1: PATTERN]"
			1: layer_header = "[PASS 2: WARP]"
			2: layer_header = "[PASS 3: FILTERS]"

	# ✅ FIXED BREAKOUT ONBOARDING STRATEGY
	if parsed_uniforms.is_empty():
		label_status.text = "Please choose an option in the 'Shader Menu'"
		if label_sens_indicator:
			label_sens_indicator.text = str(sensitivity)
		if active_color_picker:
			active_color_picker.queue_free()
			active_color_picker = null
		# ✅ COLLAPSE ON EMPTY: Zeroes out real estate box sizes instantly
		right_upper_dock.custom_minimum_size = Vector2(right_upper_dock.custom_minimum_size.x, 0)
		return 
		
	var active = parsed_uniforms[active_index]
	var u_type = active["type"]
	if u_type == "float": btn_channel.text = "FLOAT"
	else: btn_channel.text = "CH: %d" % active_sub_channel
	
	var p_name = active["name"]
	var sub_ch = get_sub_channel_name(u_type)
	var val_str = str(uniform_values[p_name])
	var sens_str = str(sensitivity)
	var desc_str = uniform_descriptions.get(p_name, "Adjustable hardware matrix parameter.")
	
	label_status.text = "  %s  •  PARAM: %s (%s)%s  •  VALUE: %s  •  SENSITIVITY: %s  \nℹ️  %s  " % [
		layer_header, p_name, u_type, sub_ch, val_str, sens_str, desc_str
	]
	if label_sens_indicator:
		label_sens_indicator.text = sens_str
		
	if active["type"] == "vec4":
		if not active_color_picker:
			# ✅ UNHIDE REAL ESTATE: Dynamically expand panel height only when picker spawns
			right_upper_dock.custom_minimum_size = Vector2(right_upper_dock.custom_minimum_size.x, 160)
			
			active_color_picker = ColorPicker.new()
			active_color_picker.picker_shape = ColorPicker.SHAPE_HSV_WHEEL
			active_color_picker.color_modes_visible = false
			active_color_picker.sampler_visible = false
			active_color_picker.sliders_visible = false
			active_color_picker.presets_visible = false
			active_color_picker.hex_visible = false
			active_color_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			active_color_picker.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			
			if uniform_values.has(p_name):
				active_color_picker.color = uniform_values[p_name]
			active_color_picker.color_changed.connect(func(new_color: Color):
				uniform_values[p_name] = new_color
				uniform_changed.emit(p_name, new_color)
			)
			right_upper_dock.add_child(active_color_picker)
	else:
		if active_color_picker:
			active_color_picker.queue_free()
			active_color_picker = null
			# ✅ COLLAPSE REAL ESTATE: Snap container height straight back to 0
			right_upper_dock.custom_minimum_size = Vector2(right_upper_dock.custom_minimum_size.x, 0)
