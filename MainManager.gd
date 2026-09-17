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


# --- DUAL PASS VIEWPORT ARCHITECTURE ---
var pass1_viewport: SubViewport
var pass1_rect: ColorRect
var pass1_material: ShaderMaterial

var canvas_container: SubViewportContainer
var pass2_viewport: SubViewport
var pass2_rect: ColorRect
var pass2_material: ShaderMaterial

# Core State Trackers
var current_preset: PatternPreset
var current_time: float = 0.0

# SELECT & START State Trackers
var active_shader_layer: int = 0 
var is_menu_open: bool = false



func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	
	current_preset = load("res://PatternPreset.gd").new()
	
	setup_dual_pass_pipeline()
	setup_interface_layer()
	load_default_test_shaders()
	
	control_panel.custom_minimum_size = Vector2(0, 220)
	control_panel.apply_orientation_layout_shift(false, top_status_holder)

func setup_dual_pass_pipeline() -> void:
	display_row_container = HBoxContainer.new()
	display_row_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	display_row_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	display_row_container.alignment = BoxContainer.ALIGNMENT_CENTER
	display_row_container.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(display_row_container)
	
	# --- SELECT BUTTON ---
	var select_spacer = Control.new()
	select_spacer.custom_minimum_size = Vector2(15, 0)
	display_row_container.add_child(select_spacer)
	
	var btn_select = Button.new()
	btn_select.text = "SELECT\n(LAYER)"
	btn_select.custom_minimum_size = Vector2(80, 80)
	btn_select.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn_select.pressed.connect(_on_select_button_pressed)
	display_row_container.add_child(btn_select)
	
	# Central Layout Anchor
	upper_display_area = CenterContainer.new()
	upper_display_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	upper_display_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	upper_display_area.mouse_filter = Control.MOUSE_FILTER_PASS
	display_row_container.add_child(upper_display_area)
	
	# Visual layout wrapper node to hold both canvas and the alert message
	var canvas_stack = VBoxContainer.new()
	canvas_stack.alignment = BoxContainer.ALIGNMENT_CENTER
	canvas_stack.mouse_filter = Control.MOUSE_FILTER_PASS
	upper_display_area.add_child(canvas_stack)
	
	canvas_container = SubViewportContainer.new()
	canvas_container.stretch = true
	canvas_container.custom_minimum_size = current_preset.target_resolution
	canvas_stack.add_child(canvas_container)
	
		# --- RENDER DIAGNOSTIC DISPLAY readouts (NOW REPOSITIONED BENEATH VIEWPORT) ---
	label_safety_alert = Label.new()
	label_safety_alert.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_safety_alert.text = ""
	label_safety_alert.add_theme_color_override("font_color", Color.RED)
	# Reduce visual label text scale settings so font stays thin
	label_safety_alert.add_theme_font_size_override("font_size", 14)
	canvas_stack.add_child(label_safety_alert)
	
	label_perf_monitor = Label.new()
	label_perf_monitor.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_perf_monitor.text = "FPS: -- | VRAM: -- MB"
	label_perf_monitor.add_theme_font_size_override("font_size", 13) # Thinner, minimal font
	# Add a light gray accent color override so it sits quietly beneath canvas
	label_perf_monitor.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 0.8))
	canvas_stack.add_child(label_perf_monitor)
	
	# --- SAFETY WARNING READOUT NODE ---
	label_safety_alert = Label.new()
	label_safety_alert.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_safety_alert.text = ""
	label_safety_alert.add_theme_color_override("font_color", Color.RED)
	canvas_stack.add_child(label_safety_alert)
	
	# =========================================================================
	# VIEWPORT LAYERS SETUP
	# =========================================================================
	pass1_viewport = SubViewport.new()
	pass1_viewport.size = current_preset.target_resolution
	pass1_viewport.disable_3d = true
	pass1_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(pass1_viewport)
	
	pass1_rect = ColorRect.new()
	pass1_rect.custom_minimum_size = current_preset.target_resolution
	pass1_rect.size = current_preset.target_resolution
	pass1_viewport.add_child(pass1_rect)
	
	pass1_material = ShaderMaterial.new()
	pass1_rect.material = pass1_material
	
	pass2_viewport = SubViewport.new()
	pass2_viewport.size = current_preset.target_resolution
	pass2_viewport.disable_3d = true
	pass2_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	canvas_container.add_child(pass2_viewport)
	
	pass2_rect = ColorRect.new()
	pass2_rect.custom_minimum_size = current_preset.target_resolution
	pass2_rect.size = current_preset.target_resolution
	pass2_viewport.add_child(pass2_rect)
	
	pass2_material = ShaderMaterial.new()
	pass2_rect.material = pass2_material
	pass2_material.set_shader_parameter("u_pattern_texture", pass1_viewport.get_texture())
	
	# --- START BUTTON ---
	var btn_start = Button.new()
	btn_start.text = "START\n(MENU)"
	btn_start.custom_minimum_size = Vector2(80, 80)
	btn_start.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn_start.pressed.connect(_on_start_button_pressed)
	display_row_container.add_child(btn_start)
	
	var start_spacer = Control.new()
	start_spacer.custom_minimum_size = Vector2(15, 0)
	display_row_container.add_child(start_spacer)

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

	# Internal layout to push performance data to the far right side
	var top_hbox = HBoxContainer.new()
	top_hbox.mouse_filter = Control.MOUSE_FILTER_PASS
	top_status_holder.add_child(top_hbox)


	
	var upper_spacer = Control.new()
	upper_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	upper_spacer.mouse_filter = Control.MOUSE_FILTER_PASS
	main_layout.add_child(upper_spacer)
	
	control_panel = load("res://DynamicUI.gd").new()
	main_layout.add_child(control_panel)
	control_panel.uniform_changed.connect(_on_ui_uniform_modified)
	
	var bottom_toolbar = HBoxContainer.new()
	bottom_toolbar.custom_minimum_size = Vector2(0, 45)
	main_layout.add_child(bottom_toolbar)
	
	var btn_save = Button.new()
	btn_save.text = "💾 EXPORT PACK (.TRES)"
	btn_save.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_save.pressed.connect(save_current_pattern_preset)
	bottom_toolbar.add_child(btn_save)

func _on_select_button_pressed() -> void:
	active_shader_layer = posmod(active_shader_layer + 1, 2)
	if active_shader_layer == 0:
		control_panel.load_shader_source(pass1_material.shader.code)
		for u_name in control_panel.uniform_values:
			var val = pass1_material.get_shader_parameter(u_name)
			if val != null: control_panel.uniform_values[u_name] = val
	else:
		control_panel.load_shader_source(pass2_material.shader.code)
		for u_name in control_panel.uniform_values:
			var val = pass2_material.get_shader_parameter(u_name)
			if val != null: control_panel.uniform_values[u_name] = val
	control_panel.update_status_readout()

func _on_start_button_pressed() -> void:
	is_menu_open = not is_menu_open
	if is_menu_open:
		open_fast_travel_menu()
	else:
		close_fast_travel_menu()

func open_fast_travel_menu() -> void:
	# 1. Ask the UI panel to give us the categories parsed from the active shader file
	active_menu_categories = control_panel.shader_categories.keys()
	if active_menu_categories.is_empty():
		is_menu_open = false
		return
		
	active_menu_index = 0
	
	# 2. Programmatically construct the layout panel overlay window
	menu_overlay_panel = PanelContainer.new()
	menu_overlay_panel.custom_minimum_size = Vector2(300, 200)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.02, 0.04, 0.95)
	style.set_border_width_all(2)
	style.border_color = Color(0.1, 0.7, 0.9, 0.8)
	menu_overlay_panel.add_theme_stylebox_override("panel", style)
	upper_display_area.add_child(menu_overlay_panel)
	
	menu_list_box = VBoxContainer.new()
	menu_list_box.alignment = BoxContainer.ALIGNMENT_CENTER
	menu_overlay_panel.add_child(menu_list_box)
	
	# Block regular thumb pad logic from firing while configuring menu options
	control_panel.set_process_input(false)
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
	
	# Fast-Travel Snap! Find the target parameter index linked to this chosen category block
	var selected_cat = active_menu_categories[active_menu_index]
	var target_param_name = control_panel.shader_categories[selected_cat]
	
	# Scan parsed uniform arrays inside the UI wrapper container to lock down indices matching names
	for idx in range(control_panel.parsed_uniforms.size()):
		if control_panel.parsed_uniforms[idx]["name"] == target_param_name:
			control_panel.active_index = idx
			break
			
	# Restore standard mobile d-pad navigation controls
	control_panel.set_process_input(true)
	control_panel.update_status_readout()
	
	menu_overlay_panel.queue_free()
	menu_overlay_panel = null


func _process(delta: float) -> void:
	current_time += delta
	if current_time > 7200.0: current_time = 0.0 
	
	if pass1_material and pass1_material.shader:
		pass1_material.set_shader_parameter("u_time", current_time)
	if pass2_material and pass2_material.shader:
		pass2_material.set_shader_parameter("u_time", current_time)
		
	# Execute hardware diagnostic checks every processing frame
	_check_hardware_gpu_safety()

# =========================================================================
# 🛡️ THE UPGRADED MOBILE VRAM SAFETY VALVE
# =========================================================================
func _check_hardware_gpu_safety() -> void:
	# 1. Pull system resource usage metrics from the engine servers
	var current_vram_mb = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1024.0 / 1024.0
	var current_fps = Engine.get_frames_per_second()
	var current_draws = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	
	# 2. Permanent Diagnostic Display Readout Sync (Top-Right)
	if label_perf_monitor:
		label_perf_monitor.text = " FPS: %d  |  VRAM: %.1f MB  |  DRAWS: %d   " % [current_fps, current_vram_mb, current_draws]
		# Color code performance text to match your original design logic
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
	if active_shader_layer == 0 and pass1_material:
		pass1_material.set_shader_parameter(u_name, u_value)
	elif active_shader_layer == 1 and pass2_material:
		pass2_material.set_shader_parameter(u_name, u_value)
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
	# PASS 1: The Inigo Quilez Domain Warping Pattern (With Description Tags)
	var p1_src = """
	shader_type canvas_item;
	uniform float u_time;
	
	// DESC: Modulates spatial compression grid boundaries.
	uniform vec2 u_warp_frequency = vec2(2.5, 2.5);
	
	// DESC: Controls absolute topological distortion strength.
	uniform float u_warp_strength = 1.1;
	
	// DESC: Adjusts fractal Brownian depth loops (1.0 to 5.0).
	uniform float u_noise_detail = 4.0;
	
	// DESC: Changes global texture drift tracking velocity.
	uniform float u_flow_speed = 0.4;
	
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
	
	# PASS 2: Animation Effect Filter (With Description Tags)
	var p2_src = """
	shader_type canvas_item;
	uniform float u_time;
	uniform sampler2D u_pattern_texture;
	
	// DESC: Sets frequency oscillation density across coordinates.
	uniform float u_wave_frequency = 10.0;
	
	// DESC: Changes physical spatial width deviation bounds.
	uniform float u_wave_amplitude = 0.02;
	
	// DESC: Accelerates linear displacement timing offsets.
	uniform float u_wave_speed = 3.0;
	
	void fragment() {
		vec2 uv = UV;
		float wave = sin(uv.y * u_wave_frequency + u_time * u_wave_speed) * u_wave_amplitude;
		uv.x += wave;
		COLOR = texture(u_pattern_texture, uv);
	}
	"""
	
	var s1 = Shader.new()
	s1.code = p1_src
	
	var s2 = Shader.new()
	s2.code = p2_src
	
	pass1_material.shader = s1
	pass2_material.shader = s2
	pass2_material.set_shader_parameter("u_pattern_texture", pass1_viewport.get_texture())
	control_panel.load_shader_source(p1_src)
