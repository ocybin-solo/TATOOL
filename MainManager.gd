extends VBoxContainer

# Layout Structure Modules
var top_status_holder: PanelContainer
var display_row_container: HBoxContainer
var upper_display_area: CenterContainer
var main_layout: VBoxContainer
var control_panel: VBoxContainer

# Dedicated Visual Warning Label for the Safety Valve
var label_safety_alert: Label
var label_perf_monitor: Label

# --- START MENU HOOKS ---
var menu_overlay_panel: PanelContainer
var menu_list_box: VBoxContainer
var active_menu_categories: Array = []
var active_menu_index: int = 0

# --- OVERLAY LAYERING (menus always paint above the viewports) ---
var ui_canvas_layer: CanvasLayer
var menu_canvas_layer: CanvasLayer
var menu_center_host: CenterContainer

# --- SELECT PASS OVERLAY HOOKS ---
var select_pass_overlay_panel: PanelContainer
var select_pass_list_box: VBoxContainer
var select_pass_pending_index: int = 0
const PASS_LABELS: Array = ["PASS 1: BASE PATTERN", "PASS 2: WARPING", "PASS 3: FILTERS"]

# --- UNIFIED MENU STATE (only one overlay + one morphed button at a time) ---
enum MenuKind { NONE, SELECT_PASS, SHADER_MENU }
var active_menu_kind: int = MenuKind.NONE
var btn_select_pass: Button
var btn_shader_menu: Button
var btn_screensaver_stub: Button
const LABEL_SELECT_PASS_IDLE: String = "🔄 SELECT PASS"
const LABEL_SHADER_MENU_IDLE: String = "🕹️ SHADER MENU"

# --- ONBOARDING BOOT RIBBON ---
# The actual suppress/release flag lives on control_panel
# (DynamicUI.suppress_status_readout) since that's where label_status
# is owned; this is just the text it shows until then.
const ONBOARDING_TEXT: String = "Please choose an option in the 'Shader Menu'"


# --- TRIPLE PASS VIEWPORT ARCHITECTURE ---
var pass1_viewport: SubViewport
var pass1_rect: ColorRect
var pass1_material: ShaderMaterial

var pass2_viewport: SubViewport
var pass2_rect: ColorRect
var pass2_material: ShaderMaterial

var canvas_container: SubViewportContainer
var pass3_viewport: SubViewport
var pass3_rect: ColorRect
var pass3_material: ShaderMaterial




# Core State Trackers
var current_preset: PatternPreset
var current_time: float = 0.0

# SELECT & START State Trackers
var active_shader_layer: int = 0 
var is_menu_open: bool = false

func _ready() -> void:
	# 🌟 REGISTER GLOBAL NODE GROUP (Removes fixed-depth path dependencies)
	add_to_group("main_manager")
	
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	
	current_preset = load("res://PatternPreset.gd").new()
	setup_three_pass_pipeline()
	setup_interface_layer()
	load_default_test_shaders()
	
	# Cleaned up container constraints for the compact hardware chassis block
	control_panel.custom_minimum_size = Vector2(0, 240)
	control_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

func setup_three_pass_pipeline() -> void:
	display_row_container = HBoxContainer.new()
	display_row_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	display_row_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	display_row_container.alignment = BoxContainer.ALIGNMENT_CENTER
	display_row_container.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(display_row_container)
	
	upper_display_area = CenterContainer.new()
	upper_display_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	upper_display_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	upper_display_area.mouse_filter = Control.MOUSE_FILTER_PASS
	display_row_container.add_child(upper_display_area)
	
	var canvas_stack = VBoxContainer.new()
	canvas_stack.alignment = BoxContainer.ALIGNMENT_CENTER
	canvas_stack.mouse_filter = Control.MOUSE_FILTER_PASS
	upper_display_area.add_child(canvas_stack)
	
	# 🌟 STRETCH AUTO-INFLATE: Force the container to expand its textures fully
	canvas_container = SubViewportContainer.new()
	canvas_container.stretch = true
	canvas_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas_stack.add_child(canvas_container)
	
	label_safety_alert = Label.new()
	label_safety_alert.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_safety_alert.text = ""
	label_safety_alert.add_theme_color_override("font_color", Color.RED)
	label_safety_alert.add_theme_font_size_override("font_size", 14)
	canvas_stack.add_child(label_safety_alert)
	
	# 🌟 ADAPTIVE PIXEL METRICS: Query maximum available device screen height
	var max_canvas_resolution: Vector2 = Vector2(DisplayServer.window_get_size().y, DisplayServer.window_get_size().y)
	canvas_container.custom_minimum_size = max_canvas_resolution
	
	# --- PASS 1: GENERATIVE MATH BUFFER ---
	pass1_viewport = SubViewport.new()
	pass1_viewport.size = max_canvas_resolution # 🌟 Auto-inflated to max square
	pass1_viewport.disable_3d = true
	pass1_viewport.transparent_bg = false
	pass1_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	pass1_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(pass1_viewport)
	
	pass1_rect = ColorRect.new()
	pass1_rect.size = max_canvas_resolution
	pass1_rect.custom_minimum_size = max_canvas_resolution
	pass1_viewport.add_child(pass1_rect)
	
	pass1_material = ShaderMaterial.new()
	pass1_rect.material = pass1_material
	
	# --- PASS 2: GEOMETRIC WARPING BUFFER ---
	pass2_viewport = SubViewport.new()
	pass2_viewport.size = max_canvas_resolution # 🌟 Auto-inflated to max square
	pass2_viewport.disable_3d = true
	pass2_viewport.transparent_bg = false
	pass2_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	pass2_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(pass2_viewport) 
	
	pass2_rect = ColorRect.new()
	pass2_rect.size = max_canvas_resolution
	pass2_rect.custom_minimum_size = max_canvas_resolution
	pass2_viewport.add_child(pass2_rect)
	
	pass2_material = ShaderMaterial.new()
	pass2_rect.material = pass2_material
	
	# --- PASS 3: POST-PROCESS FILTER BUFFER (VISIBLE SCREEN) ---
	pass3_viewport = SubViewport.new()
	pass3_viewport.size = max_canvas_resolution # 🌟 Auto-inflated to max square
	pass3_viewport.disable_3d = true
	pass3_viewport.transparent_bg = false
	pass3_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	pass3_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	canvas_container.add_child(pass3_viewport)
	
	pass3_rect = ColorRect.new()
	pass3_rect.size = max_canvas_resolution
	pass3_rect.custom_minimum_size = max_canvas_resolution
	pass3_viewport.add_child(pass3_rect)
	
	pass3_material = ShaderMaterial.new()
	pass3_rect.material = pass3_material
	
	# Establish the explicit texture pipeline bindings
	pass2_material.set_shader_parameter("u_pattern_texture", pass1_viewport.get_texture())
	pass3_material.set_shader_parameter("u_warped_texture", pass2_viewport.get_texture())


func setup_interface_layer() -> void:
	ui_canvas_layer = CanvasLayer.new()
	ui_canvas_layer.layer = 1
	add_child(ui_canvas_layer)

	# THE HORIZONTAL LANDSCAPE BASE SPLIT CHASSIS
	var landscape_root = HBoxContainer.new()
	landscape_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	landscape_root.mouse_filter = Control.MOUSE_FILTER_PASS
	ui_canvas_layer.add_child(landscape_root)

	# MAXIMUM VIEWPORT HOST LAYER
	var viewport_host = Control.new()
	viewport_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	viewport_host.custom_minimum_size.y = DisplayServer.window_get_size().y
	viewport_host.custom_minimum_size.x = viewport_host.custom_minimum_size.y
	landscape_root.add_child(viewport_host)

	if canvas_container.get_parent():
		canvas_container.get_parent().remove_child(canvas_container)
	viewport_host.add_child(canvas_container)
	canvas_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# THE IN-VIEWPORT TEXT MENU OVERLAY LAYER
	menu_center_host = CenterContainer.new()
	menu_center_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_center_host.mouse_filter = Control.MOUSE_FILTER_PASS
	menu_center_host.visible = false
	menu_center_host.z_index = 2
	viewport_host.add_child(menu_center_host)

	# MID-LEFT TRENCH: Vertical holder for utility toggles
	var utility_trench = VBoxContainer.new()
	utility_trench.custom_minimum_size = Vector2(96, 0)
	utility_trench.alignment = BoxContainer.ALIGNMENT_CENTER
	landscape_root.add_child(utility_trench)

	# 🌟 PWR Button on TOP (Shrink Begin alignment)
	btn_shader_menu = Button.new()
	btn_shader_menu.text = "⏻\nPWR"
	btn_shader_menu.custom_minimum_size = Vector2(96, 96)
	btn_shader_menu.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	btn_shader_menu.add_theme_color_override("font_color", Color.RED)
	btn_shader_menu.add_theme_font_size_override("font_size", 14)
	utility_trench.add_child(btn_shader_menu)

	# Flexible expanding spacer between the two elements
	var util_spacer = Control.new()
	util_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	utility_trench.add_child(util_spacer)

	# 🌟 OPT Button on BOTTOM (Shrink End alignment)
	btn_select_pass = Button.new()
	btn_select_pass.text = "■\nOPT"
	btn_select_pass.custom_minimum_size = Vector2(96, 96)
	btn_select_pass.size_flags_vertical = Control.SIZE_SHRINK_END
	btn_select_pass.add_theme_color_override("font_color", Color.CYAN)
	btn_select_pass.add_theme_font_size_override("font_size", 14)
	utility_trench.add_child(btn_select_pass)

	# RIGHT SIDE CONSOLE CONTROL CHASSIS
	control_panel = load("res://DynamicUI.gd").new()
	control_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	landscape_root.add_child(control_panel)
	control_panel.uniform_changed.connect(_on_ui_uniform_modified)

	active_shader_layer = 0

# ------------------------------------------------------------------
# SELECT PASS — opens a dedicated overlay listing the three pipeline
# stages instead of silently cycling in the background. Choosing a
# pass and closing the menu is what actually updates active_shader_layer.
# ------------------------------------------------------------------
func _on_select_pass_button_pressed() -> void:
	print("🎯 DIAGNOSTIC: Bottom Bar 'Select Pass' Button was physically ")
	if active_menu_kind == MenuKind.SELECT_PASS:
		close_select_pass_menu(true)
		return
	if active_menu_kind == MenuKind.SHADER_MENU:
		close_fast_travel_menu()
	open_select_pass_menu()
func open_select_pass_menu() -> void:
	is_menu_open = true
	active_menu_kind = MenuKind.SELECT_PASS

	select_pass_pending_index = active_shader_layer

	menu_center_host.visible = true
	select_pass_overlay_panel = PanelContainer.new()
	select_pass_overlay_panel.custom_minimum_size = Vector2(340, 220)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.02, 0.04, 0.92)
	style.set_border_width_all(2)
	style.border_color = Color(1.0, 0.55, 0.0, 0.9)
	style.set_corner_radius_all(8)
	select_pass_overlay_panel.add_theme_stylebox_override("panel", style)
	menu_center_host.add_child(select_pass_overlay_panel)

	var panel_body = VBoxContainer.new()
	panel_body.alignment = BoxContainer.ALIGNMENT_CENTER
	select_pass_overlay_panel.add_child(panel_body)

	select_pass_list_box = VBoxContainer.new()
	select_pass_list_box.alignment = BoxContainer.ALIGNMENT_CENTER
	panel_body.add_child(select_pass_list_box)

	# 🌟 FORCE UNLOCKED: Ensure physical D-pads can drive menu navigation strings
	#control_panel.is_input_blocked = false
	#control_panel.set_dpad_locked(false)
	redraw_select_pass_menu()

func _step_select_pass_highlight(direction: int) -> void:
	select_pass_pending_index = posmod(select_pass_pending_index + direction, PASS_LABELS.size())
	redraw_select_pass_menu()

func redraw_select_pass_menu() -> void:
	for child in select_pass_list_box.get_children(): child.queue_free()

	var label_title = Label.new()
	label_title.text = " 🔄 SELECT PASS "
	label_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_title.add_theme_color_override("font_color", Color.ORANGE)
	select_pass_list_box.add_child(label_title)

	for i in range(PASS_LABELS.size()):
		var lbl = Label.new()
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if i == select_pass_pending_index:
			lbl.text = " ▶  %s  ◀ " % PASS_LABELS[i]
			lbl.add_theme_color_override("font_color", Color.YELLOW)
		else:
			lbl.text = "    %s    " % PASS_LABELS[i]
			lbl.add_theme_color_override("font_color", Color.DARK_GRAY)
		select_pass_list_box.add_child(lbl)
func close_select_pass_menu(confirm: bool) -> void:
	if confirm:
		active_shader_layer = select_pass_pending_index
		control_panel.active_index = 0
		control_panel.active_sub_channel = 0

		var active_mat: ShaderMaterial = null
		match active_shader_layer:
			0: active_mat = pass1_material
			1: active_mat = pass2_material
			2: active_mat = pass3_material

		if active_mat and active_mat.shader:
			control_panel.load_shader_source(active_mat.shader.code)
			for u_name in control_panel.uniform_values:
				var val = active_mat.get_shader_parameter(u_name)
				if val != null:
					control_panel.uniform_values[u_name] = val
		else:
			control_panel.parsed_uniforms.clear()
			control_panel.uniform_values.clear()

	#control_panel.is_input_blocked = false
	#control_panel.set_dpad_locked(false)
	control_panel.update_status_readout()

	is_menu_open = false
	active_menu_kind = MenuKind.NONE
	btn_select_pass.text = LABEL_SELECT_PASS_IDLE
	menu_center_host.visible = false

	if select_pass_overlay_panel and is_instance_valid(select_pass_overlay_panel):
		select_pass_overlay_panel.queue_free()
		select_pass_overlay_panel = null


# ------------------------------------------------------------------
# SHADER MENU — the existing fast-travel category menu, renamed and
# folded into the same self-renaming-button / strict-input-isolation
# contract as SELECT PASS above. Its category logic is untouched.
# ------------------------------------------------------------------
func _on_shader_menu_button_pressed() -> void:
	if active_menu_kind == MenuKind.SHADER_MENU:
		close_fast_travel_menu()
		return
	if active_menu_kind == MenuKind.SELECT_PASS:
		close_select_pass_menu(false)
	open_fast_travel_menu()
	
func open_fast_travel_menu() -> void:
	var active_mat: ShaderMaterial = null
	match active_shader_layer:
		0: active_mat = pass1_material
		1: active_mat = pass2_material
		2: active_mat = pass3_material
		
	if active_mat and active_mat.shader:
		control_panel.load_shader_source(active_mat.shader.code)

	active_menu_categories = control_panel.shader_categories.keys()
	#if active_menu_categories.is_empty():
		#control_panel.is_input_blocked = false
		#return
	active_menu_index = 0

	is_menu_open = true
	active_menu_kind = MenuKind.SHADER_MENU


	menu_center_host.visible = true
	menu_overlay_panel = PanelContainer.new()
	menu_overlay_panel.custom_minimum_size = Vector2(340, 260)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.02, 0.04, 0.92)
	style.set_border_width_all(2)
	style.border_color = Color(0.0, 0.85, 1.0, 0.9)
	style.set_corner_radius_all(8)
	menu_overlay_panel.add_theme_stylebox_override("panel", style)
	menu_center_host.add_child(menu_overlay_panel)

	var panel_body = VBoxContainer.new()
	panel_body.alignment = BoxContainer.ALIGNMENT_CENTER
	menu_overlay_panel.add_child(panel_body)

	menu_list_box = VBoxContainer.new()
	menu_list_box.alignment = BoxContainer.ALIGNMENT_CENTER
	panel_body.add_child(menu_list_box)

	# 🌟 FORCE UNLOCKED: Ensure physical D-pads can drive menu navigation strings
	#control_panel.is_input_blocked = false
	#control_panel.set_dpad_locked(false)
	redraw_fast_travel_menu()

func _step_fast_travel_selection(direction: int) -> void:
	if active_menu_categories.is_empty(): return
	active_menu_index = posmod(active_menu_index + direction, active_menu_categories.size())
	redraw_fast_travel_menu()

func redraw_fast_travel_menu() -> void:
	# Wipe old list items cleanly
	for child in menu_list_box.get_children(): child.queue_free()
	
	var label_title = Label.new()
	label_title.text = " 🕹️ FAST-TRAVEL MENU "
	label_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_title.add_theme_color_override("font_color", Color.CYAN)
	menu_list_box.add_child(label_title)
	
	# Construct list item buttons dynamically based on discovered uniform categories
	for i in range(active_menu_categories.size()):
		var lbl = Label.new()
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if i == active_menu_index:
			lbl.text = " ▶  %s  ◀ " % active_menu_categories[i].to_upper()
			lbl.add_theme_color_override("font_color", Color.YELLOW)
		else:
			lbl.text = "    %s    " % active_menu_categories[i].to_upper()
			lbl.add_theme_color_override("font_color", Color.DARK_GRAY)
		menu_list_box.add_child(lbl)
		
func close_fast_travel_menu() -> void:
	if not menu_overlay_panel: return
	
	# Safety check: Ensure we actually have categories populated
	if not active_menu_categories.is_empty() and active_menu_index < active_menu_categories.size():
		var selected_cat = active_menu_categories[active_menu_index]
		
		# SAFE LOOKUP: Use .get() to prevent hard-crashes if a key is missing
		var target_param_name = control_panel.shader_categories.get(selected_cat, "")
		
		if target_param_name != "":
			# Walk the parsed uniforms array to find the index matching our parameter name
			for idx in range(control_panel.parsed_uniforms.size()):
				if control_panel.parsed_uniforms[idx]["name"] == target_param_name:
					control_panel.active_index = idx
					break
		else:
			print("⚠️ Fast-Travel: Category key '%s' not found in active UI cache." % selected_cat)
			
	# 🌟 RESTORE INPUT CHANNEL ACCESS SAFELY
	#control_panel.is_input_blocked = false
	#control_panel.set_dpad_locked(false)

	is_menu_open = false
	active_menu_kind = MenuKind.NONE
	btn_shader_menu.text = LABEL_SHADER_MENU_IDLE
	menu_center_host.visible = false

	# First real SHADER MENU use ends the onboarding boot ribbon.
	control_panel.suppress_status_readout = false
	control_panel.update_status_readout()
	
	# Clean up the UI overlay panel node from memory safely
	menu_overlay_panel.queue_free()
	menu_overlay_panel = null

func _process(delta: float) -> void:
	current_time += delta
	if current_time > 7200.0: current_time = 0.0 # Prevents floating-point precision loss
	
	# Keep all three simulation layers running on the exact same temporal clock ticking rate
	if pass1_material and pass1_material.shader:
		pass1_material.set_shader_parameter("u_time", current_time)
	if pass2_material and pass2_material.shader:
		pass2_material.set_shader_parameter("u_time", current_time)
	if pass3_material and pass3_material.shader:
		pass3_material.set_shader_parameter("u_time", current_time)
		
	# Execute hardware diagnostic checks every processing frame
	_check_hardware_gpu_safety()

# =========================================================================
# 🛡️ THE UPGRADED MOBILE VRAM SAFETY VALVE
# =========================================================================
func _check_hardware_gpu_safety() -> void:
	# 1. Pull system resource usage metrics from the engine servers
	var current_vram_mb = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1024.0 / 1024.0
	var current_fps = Engine.get_frames_per_second()

	
	# 2. Permanent Diagnostic Display Readout Sync (Top-Right)
	# Update this specific section inside your _check_hardware_gpu_safety() function:
	if label_perf_monitor:
		label_perf_monitor.text = " FPS: %d  |  VRAM: %.1f MB   " % [current_fps, current_vram_mb]
		if current_fps > 55: label_perf_monitor.add_theme_color_override("font_color", Color.GREEN)
		elif current_fps > 30: label_perf_monitor.add_theme_color_override("font_color", Color.YELLOW)
		else: label_perf_monitor.add_theme_color_override("font_color", Color.RED)

	
	# 3. Mobile Breaker Trip Point
	var vram_safety_trip_point = 1000.0 # 1GB Limit
	
	if current_vram_mb > vram_safety_trip_point or current_fps < 30.0:
		if pass1_material:
			var active_detail = pass1_material.get_shader_parameter("u_noise_detail")
			if active_detail != null and active_detail > 2.0:
				pass1_material.set_shader_parameter("u_noise_detail", 2.0)
				control_panel.uniform_values["u_noise_detail"] = 2.0
				control_panel.update_status_readout()
				
				label_safety_alert.text = "⚠️ VRAM/PERFORMANCE OVERLOAD PREVENTED: CLAMPING NOISE DETAIL"
				get_tree().create_timer(4.0).timeout.connect(func(): label_safety_alert.text = "")
	
	
				
func _on_ui_uniform_modified(u_name: String, u_value: Variant) -> void:
	# Route the parameters dynamically based on which pass is currently selected

				
	match active_shader_layer:
		0:
			if pass1_material: pass1_material.set_shader_parameter(u_name, u_value)
		1:
			if pass2_material: pass2_material.set_shader_parameter(u_name, u_value)
		2:
			if pass3_material: pass3_material.set_shader_parameter(u_name, u_value)
			
	# Cache the modified parameter into your current active preset resource for exports
	current_preset.uniform_values[u_name] = u_value

func save_current_pattern_preset() -> void:
	var active_mat: ShaderMaterial = pass1_material if active_shader_layer == 0 else pass2_material
	if not active_mat or not active_mat.shader: return
	
	var layer_label: String = "PASS 1 (PATTERN GENERATOR)" if active_shader_layer == 0 else "PASS 2 (ANIMATION EFFECTS)"
	var output = "// 🕹️ HANDHELD SHADER CONSOLE EXPORT DATA\n// TARGET LAYER: %s\n\n" % layer_label
	
	var active_params = []
	var params = active_mat.shader.get_shader_uniform_list()
	
	for p in params:
		if p.name == "u_time" or p.name == "u_pattern_texture": continue
		var val = active_mat.get_shader_parameter(p.name)
		if val == null: continue
		active_params.append(p.name)
		
		# --- CLEAN FORMATTING HOOKS ---
		if p.type == TYPE_FLOAT: 
			output += "mat.set_shader_parameter('%s', %.3f);\n" % [p.name, val]
		elif p.type == TYPE_VECTOR2: 
			output += "mat.set_shader_parameter('%s', vec2(%.3f, %.3f));\n" % [p.name, val.x, val.y]
		elif p.type == TYPE_COLOR: 
			output += "mat.set_shader_parameter('%s', Color(%.2f, %.2f, %.2f, %.2f));\n" % [p.name, val.r, val.g, val.b, val.a]
			
	# --- UNTANGLED SYSTEM CLIPBOARD REGISTRATION ---
	output += "\n// --- SOURCE GLSL SHADER CODE CONTEXT ---\n" + active_mat.shader.code
	DisplayServer.clipboard_set(output)
	control_panel.label_status.text = " ✅ COPIED %d PARAMETERS FROM %s TO CLIPBOARD! " % [active_params.size(), layer_label]

func load_default_test_shaders() -> void:
	# =========================================================================
	# PASS 1: INIGO QUILEZ DOMAIN WARPING (GENERATIVE MATH)
	# =========================================================================
	var p1_src = """
	shader_type canvas_item;
	uniform float u_time;
	
	// CAT: Spatial Configuration
	// DESC: Modulates spatial compression grid boundaries.
	uniform vec2 u_warp_frequency = vec2(2.5, 2.5);
	
	// CAT: Warping Calculations
	// DESC: Controls absolute topological distortion strength.
	uniform float u_warp_strength = 1.1;
	uniform float u_noise_detail = 4.0;
	uniform float u_flow_speed = 0.4;
	
	// CAT: Aesthetics & Tinting
	// DESC: Sets primary tint vector values.
	uniform vec4 u_pattern_color : source_color = vec4(0.1, 0.7, 0.9, 1.0);
	
	float hash2d(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123); }
	float value_noise(vec2 p) {
		vec2 i = floor(p); vec2 f = fract(p);
		vec2 u = f * f * (3.0 - 2.0 * f);
		return mix(mix(hash2d(i + vec2(0.0, 0.0)), hash2d(i + vec2(1.0, 0.0)), u.x),
				   mix(hash2d(i + vec2(0.0, 1.0)), hash2d(i + vec2(1.0, 1.0)), u.x), u.y);
	}
	float fbm(vec2 p) {
		float value = 0.0; float amplitude = 0.5; float frequency = 1.0;
		for (int i = 0; i < 5; i++) {
			if (float(i) >= u_noise_detail) break;
			value += amplitude * value_noise(p * frequency);
			frequency *= 2.0; amplitude *= 0.5;
		}
		return value;
	}
	void fragment() {
		vec2 st = UV * u_warp_frequency;
		float scaled_time = u_time * u_flow_speed;
		vec2 q = vec2(fbm(st + vec2(scaled_time * 0.2)), fbm(st + vec2(5.2, 1.3) + vec2(scaled_time * 0.15)));
		vec2 r = vec2(fbm(st + u_warp_strength * q + vec2(1.7, 9.2) + vec2(scaled_time * 0.3)), fbm(st + u_warp_strength * q + vec2(8.3, 2.8) + vec2(scaled_time * 0.05)));
		float final_field_math = fbm(st + u_warp_strength * r);
		vec4 core_bg = mix(vec4(0.02, 0.02, 0.05, 1.0), vec4(0.12, 0.0, 0.22, 1.0), clamp(length(q), 0.0, 1.0));
		COLOR = mix(core_bg, u_pattern_color, final_field_math) * (final_field_math * 1.5 + 0.3);
	}
	"""
	
	# =========================================================================
	# PASS 2: GEOMETRIC KALEIDOSCOPE WARP (CLAUDE FIX INTEGRATED)
	# =========================================================================
	var p2_src = """
	shader_type canvas_item;
	// CLAUDE FIX: Plain user-defined sampler without screen hint conflicts
	uniform sampler2D u_pattern_texture : filter_linear;
	uniform float u_time;
	
	// CAT: Geometric Setup
	// DESC: Number of reflective segments across the radial circle matrix.
	uniform float u_segments = 6.0;
	uniform float u_rotation_speed = 0.2;
	
	void fragment() {
		vec2 uv = UV - 0.5;
		float r = length(uv);
		float a = atan(uv.y, uv.x) + (u_time * u_rotation_speed);
		float angle_step = 2.0 * 3.14159265 / max(u_segments, 1.0);
		
		a = mod(a, angle_step);
		a = abs(a - angle_step * 0.5);
		
		vec2 warped_uv = vec2(cos(a), sin(a)) * r + 0.5;
		warped_uv = clamp(warped_uv, 0.001, 0.999);
		
		COLOR = texture(u_pattern_texture, warped_uv);
	}
	"""
	
	# =========================================================================
	# PASS 3: ANALOG EDGE GLOW FILTER (CLAUDE FIX INTEGRATED)
	# =========================================================================
	var p3_src = """
	shader_type canvas_item;
	// CLAUDE FIX: Plain user-defined sampler without screen hint conflicts
	uniform sampler2D u_warped_texture : filter_linear;
	uniform float u_time;
	
	// CAT: Glow Intensity
	// DESC: Structural mathematical edge amplification threshold limits.
	uniform float u_edge_threshold = 0.15;
	uniform float u_glow_intensity = 2.5;
	uniform vec2 u_step_offset = vec2(0.003, 0.003);
	
	void fragment() {
		vec2 uv = UV;
		vec4 center_color = texture(u_warped_texture, uv);
		
		float c  = (center_color.r + center_color.g + center_color.b) / 3.0;
		float left  = (texture(u_warped_texture, uv - vec2(u_step_offset.x, 0.0)).g);
		float right = (texture(u_warped_texture, uv + vec2(u_step_offset.x, 0.0)).g);
		float up    = (texture(u_warped_texture, uv - vec2(0.0, u_step_offset.y)).g);
		float down  = (texture(u_warped_texture, uv + vec2(0.0, u_step_offset.y)).g);
		
		float edge_delta = abs(c - left) + abs(c - right) + abs(c - up) + abs(c - down);
		float edge_mask = smoothstep(u_edge_threshold, u_edge_threshold + 0.1, edge_delta);
		vec3 glowing_borders = center_color.rgb * edge_mask * u_glow_intensity;
		
		COLOR = vec4(center_color.rgb + glowing_borders, center_color.a);
	}
	"""
	
	var s1 = Shader.new(); s1.code = p1_src
	var s2 = Shader.new(); s2.code = p2_src
	var s3 = Shader.new(); s3.code = p3_src
	
	pass1_material.shader = s1
	pass2_material.shader = s2
	pass3_material.shader = s3
	
	# Apply the user-assigned textures directly to the parameters
	pass2_material.set_shader_parameter("u_pattern_texture", pass1_viewport.get_texture())
	pass3_material.set_shader_parameter("u_warped_texture", pass2_viewport.get_texture())
	
	control_panel.load_shader_source(p1_src)
