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


# Uniform records for the list shown in Tier 3, built by MainManager from ShaderLibrary.
# Record keys: name, type, label, default, min, max, sens, channels, is_global, recipe
var parsed_uniforms: Array = []
var active_recipe_id: String = ""   # formula whose uniforms Tier 3 shows ("" = the pass's GLOBALS list)
var active_index: int = 0
var sensitivity: float = 1.0
var current_sens_index: int = 2     # step in the per-uniform sensitivity ladder (2 = recommended)
var sens_index_memory: Dictionary = {}  # remembers the sensitivity step chosen for each uniform
var active_sub_channel: int = 0
# Shared BY REFERENCE with MainManager.pass_values[active pass]
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
	btn_channel.text = "✔\n"
	btn_channel.custom_minimum_size = Vector2(96, 96)
	btn_channel.add_theme_font_size_override("font_size", 44)
	btn_channel.add_theme_color_override("font_color", Color.GREEN)
	btn_channel.pressed.connect(_on_action_button_a) # Wired to Accept logic
	action_row.add_child(btn_channel)

	# Perfect visual axis alignment gap matching the structural width of the D-pad cross center
	var button_gap = Control.new()
	button_gap.custom_minimum_size = Vector2(96, 0)
	action_row.add_child(button_gap)

	# B Button (❌ BACK)
	btn_sens_left = Button.new()
	btn_sens_left.text = "❌\n"
	btn_sens_left.custom_minimum_size = Vector2(96, 96)
	btn_sens_left.add_theme_font_size_override("font_size", 44)
	btn_sens_left.add_theme_color_override("font_color", Color.RED)
	btn_sens_left.pressed.connect(_on_action_button_b) # Wired to Exit/Back logic
	action_row.add_child(btn_sens_left)

	# THE LEFT SHIFT FILTER: Adding a small layout spacer on the right side of the row 
	var left_shift_spacer = Control.new()
	left_shift_spacer.custom_minimum_size = Vector2(100, 0)
	action_row.add_child(left_shift_spacer)

	# PUSH DPAD DOWN: Increased vertical separation gap between rows
	var vertical_spacer = Control.new()
	vertical_spacer.custom_minimum_size = Vector2(0, 0)
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
	btn_param_up.add_theme_font_size_override("font_size", 44)
	btn_param_up.pressed.connect(_on_dpad_up) # Wired to Navigate Up
	dpad_grid.add_child(btn_param_up)
	dpad_grid.add_child(Control.new())

	# Row 2: LEFT | CENTER DISPLAY INDEX | RIGHT
	btn_channel_prev = Button.new()
	btn_channel_prev.text = "◄"
	btn_channel_prev.custom_minimum_size = Vector2(96, 96)
	btn_channel_prev.add_theme_font_size_override("font_size", 44)
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
	btn_channel_next.add_theme_font_size_override("font_size", 44)
	btn_channel_next.pressed.connect(_on_dpad_right) # Wired to Cycle Right
	dpad_grid.add_child(btn_channel_next)

	# Row 3: Dead Space | DOWN | Dead Space
	dpad_grid.add_child(Control.new())
	btn_param_down = Button.new()
	btn_param_down.text = "▼"
	btn_param_down.custom_minimum_size = Vector2(96, 96)
	btn_param_down.add_theme_font_size_override("font_size", 44)
	btn_param_down.pressed.connect(_on_dpad_down) # Wired to Navigate Down
	dpad_grid.add_child(btn_param_down)
	dpad_grid.add_child(Control.new())


func _on_dpad_up() -> void:
	_nav_vertical(-1)

func _on_dpad_down() -> void:
	_nav_vertical(1)

func _nav_vertical(step: int) -> void:
	var main_manager = get_tree().get_first_node_in_group("main_manager")
	if not main_manager or active_state == ControlState.HIDDEN: return

	match active_state:
		ControlState.SYSTEM_MENU:
			system_menu_index = posmod(system_menu_index + step, 3)
			main_manager.redraw_system_power_menu()
		ControlState.TIER_1_PASS:
			if main_manager.active_menu_kind == main_manager.MenuKind.SELECT_PASS:
				main_manager._step_select_pass_highlight(step)
		ControlState.TIER_2_FORMULA:
			main_manager._step_formula_selection(step)
		ControlState.TIER_3_UNIFORM:
			if main_manager.active_menu_kind == main_manager.MenuKind.SHADER_MENU:
				main_manager._step_fast_travel_selection(step)
		ControlState.TIER_4_PARAMETER:
			if parsed_uniforms.is_empty(): return
			var max_channels: int = parsed_uniforms[active_index]["channels"].size()
			last_tier4_index = posmod(last_tier4_index + step, max_channels)
			main_manager.open_parameter_select_menu()
		ControlState.TIER_5_TWEAK:
			last_tier5_row = posmod(last_tier5_row + step, 2)
			main_manager.open_live_tweak_console()

# FUNCTION END: vertical_dpad_handlers


func _on_dpad_left() -> void:
	_nav_horizontal(-1)

func _on_dpad_right() -> void:
	_nav_horizontal(1)

func _nav_horizontal(step: int) -> void:
	var main_manager = get_tree().get_first_node_in_group("main_manager")
	if not main_manager or active_state != ControlState.TIER_5_TWEAK: return

	if last_tier5_row == 0:
		modify_active_value(float(step))
	else:
		_step_sensitivity(step, main_manager)
	main_manager.open_live_tweak_console()

## Move along the sensitivity ladder built around this uniform's recommended value.
func _step_sensitivity(step: int, main_manager) -> void:
	if parsed_uniforms.is_empty(): return
	var rec: Dictionary = parsed_uniforms[active_index]
	var ladder: Array = main_manager.library.sens_ladder(rec)
	current_sens_index = clampi(current_sens_index + step, 0, ladder.size() - 1)
	sensitivity = ladder[current_sens_index]
	sens_index_memory[rec["name"]] = current_sens_index

## Enter Tier 5 for the selected uniform: restore its remembered sensitivity step (default = recommended).
func enter_tweak_context() -> void:
	var main_manager = get_tree().get_first_node_in_group("main_manager")
	if not main_manager or parsed_uniforms.is_empty(): return
	var rec: Dictionary = parsed_uniforms[active_index]
	var ladder: Array = main_manager.library.sens_ladder(rec)
	current_sens_index = clampi(int(sens_index_memory.get(rec["name"], 2)), 0, ladder.size() - 1)
	sensitivity = ladder[current_sens_index]
	last_tier5_row = 0
	active_state = ControlState.TIER_5_TWEAK
	main_manager.open_live_tweak_console()


func _on_action_button_b() -> void:
	# 5-TIER POP BACKWARDS ROUTER
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
			# Single-parameter uniforms skipped Tier 4 on the way in, so skip it on the way out too
			if not parsed_uniforms.is_empty() and parsed_uniforms[active_index]["channels"].size() == 1:
				print("🎮 Hierarchy Pop: TIER_5_TWEAK -> TIER_3_UNIFORM")
				active_state = ControlState.TIER_3_UNIFORM
				main_manager.open_fast_travel_menu()
			else:
				print("🎮 Hierarchy Pop: TIER_5_TWEAK -> TIER_4_PARAMETER")
				active_state = ControlState.TIER_4_PARAMETER
				main_manager.open_parameter_select_menu()

		ControlState.TIER_4_PARAMETER:
			print("🎮 Hierarchy Pop: TIER_4_PARAMETER -> TIER_3_UNIFORM")
			active_state = ControlState.TIER_3_UNIFORM
			main_manager.open_fast_travel_menu()

		ControlState.TIER_3_UNIFORM:
			print("🎮 Hierarchy Pop: TIER_3_UNIFORM -> TIER_2_FORMULA")
			active_state = ControlState.TIER_2_FORMULA
			main_manager.open_formula_select_menu()

		ControlState.TIER_2_FORMULA:
			print("🎮 Hierarchy Pop: TIER_2_FORMULA -> TIER_1_PASS")
			# Delete the cyan container frame completely before restoring Tier 1's unique orange frame
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
			main_manager.close_select_pass_menu(true) # locks in last_tier1_index as the active pass
			main_manager.enter_formula_menu()

		ControlState.TIER_2_FORMULA:
			var rows: Array = main_manager.get_formula_rows()
			if last_tier2_index >= rows.size(): return
			var row: Dictionary = rows[last_tier2_index]
			match row["kind"]:
				"reset":
					print("🧹 Hardware Trigger: Resetting the active pass")
					main_manager.reset_active_pass()
					main_manager.redraw_formula_select_menu()
				"globals":
					print("🎮 Hierarchy Push: TIER_2_FORMULA -> TIER_3_UNIFORM (GLOBALS)")
					main_manager.prepare_uniform_list("")
					active_state = ControlState.TIER_3_UNIFORM
					main_manager.open_fast_travel_menu()
				"recipe":
					print("🎮 Hierarchy Push: TIER_2_FORMULA -> TIER_3_UNIFORM (%s)" % row["id"])
					main_manager.activate_recipe(row["id"])
					main_manager.prepare_uniform_list(row["id"])
					active_state = ControlState.TIER_3_UNIFORM
					main_manager.open_fast_travel_menu()

		ControlState.TIER_3_UNIFORM:
			if last_tier3_index == 0:
				main_manager.tier3_row0_action()
				return
			if parsed_uniforms.is_empty() or last_tier3_index - 1 >= parsed_uniforms.size(): return
			active_index = last_tier3_index - 1
			last_tier4_index = 0
			# A uniform with a single parameter has nothing to choose in Tier 4: jump straight to Tier 5
			if parsed_uniforms[active_index]["channels"].size() == 1:
				print("🎮 Hierarchy Push: TIER_3_UNIFORM -> TIER_5_TWEAK (single parameter)")
				enter_tweak_context()
			else:
				print("🎮 Hierarchy Push: TIER_3_UNIFORM -> TIER_4_PARAMETER")
				active_state = ControlState.TIER_4_PARAMETER
				main_manager.open_parameter_select_menu()

		ControlState.TIER_4_PARAMETER:
			print("🎮 Hierarchy Push: TIER_4_PARAMETER -> TIER_5_TWEAK")
			enter_tweak_context()

		ControlState.TIER_5_TWEAK:
			return

# FUNCTION END: _on_action_button_a


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
	var main_manager = get_tree().get_first_node_in_group("main_manager")
	if not main_manager: return
	var lib = main_manager.library

	var rec: Dictionary = parsed_uniforms[active_index]
	var u_name: String = rec["name"]
	var u_type: String = rec["type"]
	var idx: int = clampi(last_tier4_index, 0, rec["channels"].size() - 1)

	# Start from the cached value, or the shader's own default if this uniform was never touched
	var current: Variant = uniform_values.get(u_name, rec["default"])
	var new_comp: float = lib.get_component(current, u_type, idx) + direction_multiplier * sensitivity
	new_comp = snappedf(lib.clamp_component(rec, new_comp), 0.000001)

	uniform_values[u_name] = lib.set_component(current, u_type, idx, new_comp)
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
	if suppress_status_readout or label_status == null: return
	if parsed_uniforms.is_empty(): return
	var active = parsed_uniforms[active_index]
	var u_type = active["type"]
	if u_type == "float": btn_channel.text = "FLOAT"
	else: btn_channel.text = "CH: %d" % active_sub_channel
	
	var p_name = active["name"]
	var sub_ch = get_sub_channel_name(u_type)
	var val_str = str(uniform_values.get(p_name, active["default"]))
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
