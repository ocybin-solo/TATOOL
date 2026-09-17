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
	setup_dual_pass_pipeline()
	setup_interface_layer()
	load_default_test_shaders()
	
	# Update the final size constraints at the bottom of MainManager.gd -> _ready()
	control_panel.custom_minimum_size = Vector2(0, 240) # Slightly expanded vertical container boundary box
	control_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL # Forces vertical centering
	control_panel.apply_orientation_layout_shift(false, top_status_holder)
func setup_dual_pass_pipeline() -> void:
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
	
	canvas_container = SubViewportContainer.new()
	canvas_container.stretch = true
	canvas_container.custom_minimum_size = current_preset.target_resolution
	canvas_stack.add_child(canvas_container)
	
	label_safety_alert = Label.new()
	label_safety_alert.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_safety_alert.text = ""
	label_safety_alert.add_theme_color_override("font_color", Color.RED)
	label_safety_alert.add_theme_font_size_override("font_size", 14)
	canvas_stack.add_child(label_safety_alert)
	
	# --- PASS 1: GENERATIVE MATH BUFFER ---
	pass1_viewport = SubViewport.new()
	pass1_viewport.size = current_preset.target_resolution
	pass1_viewport.disable_3d = true
	pass1_viewport.transparent_bg = false
	pass1_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	pass1_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(pass1_viewport)
	
	pass1_rect = ColorRect.new()
	pass1_rect.size = current_preset.target_resolution
	pass1_rect.custom_minimum_size = current_preset.target_resolution
	pass1_viewport.add_child(pass1_rect)
	
	pass1_material = ShaderMaterial.new()
	pass1_rect.material = pass1_material
	
	# --- PASS 2: GEOMETRIC WARPING BUFFER ---
	pass2_viewport = SubViewport.new()
	pass2_viewport.size = current_preset.target_resolution
	pass2_viewport.disable_3d = true
	pass2_viewport.transparent_bg = false
	pass2_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	pass2_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(pass2_viewport) 
	
	pass2_rect = ColorRect.new()
	pass2_rect.size = current_preset.target_resolution
	pass2_rect.custom_minimum_size = current_preset.target_resolution
	pass2_viewport.add_child(pass2_rect)
	
	pass2_material = ShaderMaterial.new()
	pass2_rect.material = pass2_material
	
	# --- PASS 3: POST-PROCESS FILTER BUFFER (VISIBLE SCREEN) ---
	pass3_viewport = SubViewport.new()
	pass3_viewport.size = current_preset.target_resolution
	pass3_viewport.disable_3d = true
	pass3_viewport.transparent_bg = false
	pass3_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	pass3_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	canvas_container.add_child(pass3_viewport)
	
	pass3_rect = ColorRect.new()
	pass3_rect.size = current_preset.target_resolution
	pass3_rect.custom_minimum_size = current_preset.target_resolution
	pass3_viewport.add_child(pass3_rect)
	
	pass3_material = ShaderMaterial.new()
	pass3_rect.material = pass3_material
	
	# Establish the explicit texture pipeline bindings
	pass2_material.set_shader_parameter("u_pattern_texture", pass1_viewport.get_texture())
	pass3_material.set_shader_parameter("u_warped_texture", pass2_viewport.get_texture())


func setup_interface_layer() -> void:
	var ui_layer = CanvasLayer.new()
	add_child(ui_layer)
	
	main_layout = VBoxContainer.new()
	main_layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_layout.mouse_filter = Control.MOUSE_FILTER_PASS
	ui_layer.add_child(main_layout)
	
	top_status_holder = PanelContainer.new()
	top_status_holder.mouse_filter = Control.MOUSE_FILTER_PASS
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.07, 0.7)
	top_status_holder.add_theme_stylebox_override("panel", style)
	main_layout.add_child(top_status_holder)

	var top_hbox = HBoxContainer.new()
	top_hbox.mouse_filter = Control.MOUSE_FILTER_PASS
	top_status_holder.add_child(top_hbox)
	
	var top_banner_expanding_spacer = Control.new()
	top_banner_expanding_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hbox.add_child(top_banner_expanding_spacer)

	label_perf_monitor = Label.new()
	label_perf_monitor.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label_perf_monitor.text = "FPS: -- | VRAM: -- MB"
	label_perf_monitor.add_theme_font_size_override("font_size", 13)
	label_perf_monitor.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 0.8))
	top_hbox.add_child(label_perf_monitor)
	
	var upper_spacer = Control.new()
	upper_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	upper_spacer.mouse_filter = Control.MOUSE_FILTER_PASS
	main_layout.add_child(upper_spacer)
	
	control_panel = load("res://DynamicUI.gd").new()
	main_layout.add_child(control_panel)
	control_panel.uniform_changed.connect(_on_ui_uniform_modified)
	
	# =========================================================================
	# 🕹️ UNIFIED THREE-BUTTON HARDWARE CLUSTER ROW
	# =========================================================================
	var bottom_toolbar = HBoxContainer.new()
	bottom_toolbar.custom_minimum_size = Vector2(0, 50)
	bottom_toolbar.alignment = BoxContainer.ALIGNMENT_CENTER
	main_layout.add_child(bottom_toolbar)
	
	# 1. SELECT (Left Side of Group)
	var btn_select_layer = Button.new()
	btn_select_layer.text = "🔄 SELECT"
	btn_select_layer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_select_layer.pressed.connect(_on_select_button_pressed)
	bottom_toolbar.add_child(btn_select_layer)
	
	# 2. EXPORT PACK (Center Anchor)
	var btn_save = Button.new()
	btn_save.text = "💾 EXPORT PACK (.TRES)"
	btn_save.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_save.pressed.connect(save_current_pattern_preset)
	bottom_toolbar.add_child(btn_save)
	
	# 3. START MENU (Right Side of Group)
	var btn_start_menu = Button.new()
	btn_start_menu.text = "🕹️ START"
	btn_start_menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_start_menu.pressed.connect(_on_start_button_pressed)
	bottom_toolbar.add_child(btn_start_menu)

	# CRITICAL COMPILER CORRECTION: 
	# Let setup finish cleanly without querying uncompiled shader source data yet!
	active_shader_layer = 0

func _on_select_button_pressed() -> void:
	# 🔒 CRITICAL UI LOCK: Prevent layer switching while the fast-travel menu is open
	if is_menu_open: 
		print("⚠️ UI Input Blocked: Cannot switch layers while Fast-Travel menu is active.")
		return

	# 1. Cycle focus cleanly between 3 discrete layers (0 -> 1 -> 2 -> 0)
	active_shader_layer = posmod(active_shader_layer + 1, 3)
	
	# Reset the UI pointer safely before loading new parameter variables
	control_panel.active_index = 0
	control_panel.active_sub_channel = 0
	# 1. Cycle focus cleanly between 3 discrete layers (0 -> 1 -> 2 -> 0)
	active_shader_layer = posmod(active_shader_layer + 1, 3)
	
	# Reset the UI pointer safely before loading new parameter variables
	control_panel.active_index = 0
	control_panel.active_sub_channel = 0
	
	# 2. Select the material based on the active layer
	var active_mat: ShaderMaterial = null
	
	match active_shader_layer:
		0:
			print("Console Focus: [PASS 1 - GENERATIVE MATH]")
			active_mat = pass1_material
		1:
			print("Console Focus: [PASS 2 - GEOMETRIC WARPING]")
			active_mat = pass2_material
		2:
			print("Console Focus: [PASS 3 - POST-PROCESS FILTERS]")
			active_mat = pass3_material

	# 3. Securely ingest the active shader parameters into the DynamicUI control block
	if active_mat and active_mat.shader:
		control_panel.load_shader_source(active_mat.shader.code)
		
		# Synchronize live runtime parameters back into the UI cache values
		for u_name in control_panel.uniform_values:
			var val = active_mat.get_shader_parameter(u_name)
			if val != null: 
				control_panel.uniform_values[u_name] = val
	else:
		# Safety guard if a shader pass is temporarily empty or uncompiled
		control_panel.parsed_uniforms.clear()
		control_panel.uniform_values.clear()
		print("⚠️ Warning: Focused layer material or shader is unassigned.")
			
	# 4. Redraw the HUD status banner text across the top of the device screen
	control_panel.update_status_readout()

func _on_start_button_pressed() -> void:
	is_menu_open = not is_menu_open
	if is_menu_open:
		open_fast_travel_menu()
	else:
		close_fast_travel_menu()

func open_fast_travel_menu() -> void:
	# Force the UI to refresh its category dictionary based on the currently active layer code
	var active_mat: ShaderMaterial = null
	match active_shader_layer:
		0: active_mat = pass1_material
		1: active_mat = pass2_material
		2: active_mat = pass3_material
		
	if active_mat and active_mat.shader:
		control_panel.load_shader_source(active_mat.shader.code)

	active_menu_categories = control_panel.shader_categories.keys()
	if active_menu_categories.is_empty():
		is_menu_open = false
		control_panel.is_input_blocked = false
		return
	active_menu_index = 0
	
	menu_overlay_panel = PanelContainer.new()
	menu_overlay_panel.custom_minimum_size = Vector2(340, 240)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.02, 0.04, 0.92)
	style.set_border_width_all(2)
	style.border_color = Color(0.0, 0.85, 1.0, 0.9)
	style.set_corner_radius_all(8)
	menu_overlay_panel.add_theme_stylebox_override("panel", style)
	upper_display_area.add_child(menu_overlay_panel)
	
	menu_list_box = VBoxContainer.new()
	menu_list_box.alignment = BoxContainer.ALIGNMENT_CENTER
	menu_overlay_panel.add_child(menu_list_box)
	
	# 🌟 FIX THE LOOPS: Set our custom safety flag instead of modifying core input loops
	control_panel.is_input_blocked = true
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
	control_panel.is_input_blocked = false
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
