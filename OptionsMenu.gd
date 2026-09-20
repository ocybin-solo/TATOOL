extends RefCounted
## OptionsMenu.gd -- TATOOL app options (System Main Menu > APP CONFIG OPTIONS)
## Colors (background + button colors) and Controller Layout (landscape / portrait, each with mirrors).
## It also owns PresetsMenu.gd, so DynamicUI only ever talks to this one object.
## Everything is saved to user:// and re-applied at launch.
##
## The menu is driven by TREE. Row kinds:
##   "go"     open the submenu named in "target"
##   "choice" pick one value of a setting (the active one shows a filled dot)
##   "color"  edit the color stored under "key" (channel picker, then tweak console)
##   "action" run a named action
## DynamicUI forwards D-pad / A / B to this object while is_active() is true.

const SETTINGS_PATH: String = "user://tatool_settings.cfg"
const SENS_LADDER: Array = [0.002, 0.01, 0.02, 0.1, 0.2] # index 2 is the recommended step
const DEFAULT_SENS_INDEX: int = 2
const BUTTON_STATES: Array = ["normal", "hover", "pressed", "hover_pressed"]

enum Mode { LIST, CHANNEL, TWEAK }

const TREE: Dictionary = {
	"root": {
		"title": " ⚙ APP CONFIG OPTIONS ",
		"rows": [
			{"label": "COLORS", "kind": "go", "target": "colors"},
			{"label": "CONTROLLER LAYOUT", "kind": "go", "target": "layout"},
		],
	},
	"colors": {
		"title": " 🎨 COLORS ",
		"rows": [
			{"label": "BACKGROUND COLOR", "kind": "color", "key": "bg_color"},
			{"label": "BUTTON COLOR", "kind": "color", "key": "button_color"},
			{"label": "[ RESET COLORS TO DEFAULT ]", "kind": "action", "action": "reset_colors"},
		],
	},
	"layout": {
		"title": " 🎮 CONTROLLER LAYOUT ",
		"rows": [
			{"label": "LANDSCAPE", "kind": "go", "target": "landscape"},
			{"label": "PORTRAIT", "kind": "go", "target": "portrait"},
		],
	},
	# Picking a row sets that orientation AND that mirror layout (0 standard, 1 horizontal, 2 vertical, 3 both)
	"landscape": {
		"title": " LANDSCAPE LAYOUT ",
		"cursor_from": "landscape_layout", # open with the cursor on the layout currently in use
		"rows": [
			{"label": "STANDARD", "kind": "choice", "setting": "landscape_layout", "orientation": 0, "value": 0},
			{"label": "MIRRORED HORIZONTALLY", "kind": "choice", "setting": "landscape_layout", "orientation": 0, "value": 1},
			{"label": "MIRRORED VERTICALLY", "kind": "choice", "setting": "landscape_layout", "orientation": 0, "value": 2},
			{"label": "MIRRORED HORIZ + VERT", "kind": "choice", "setting": "landscape_layout", "orientation": 0, "value": 3},
		],
	},
	"portrait": {
		"title": " PORTRAIT LAYOUT ",
		"cursor_from": "portrait_layout",
		"rows": [
			{"label": "STANDARD", "kind": "choice", "setting": "portrait_layout", "orientation": 1, "value": 0},
			{"label": "MIRRORED HORIZONTALLY", "kind": "choice", "setting": "portrait_layout", "orientation": 1, "value": 1},
			{"label": "MIRRORED VERTICALLY", "kind": "choice", "setting": "portrait_layout", "orientation": 1, "value": 2},
			{"label": "MIRRORED HORIZ + VERT", "kind": "choice", "setting": "portrait_layout", "orientation": 1, "value": 3},
		],
	},
}

# Background alpha has no visible effect on a window clear color, so it only gets R, G, B.
const COLOR_DEFS: Dictionary = {
	"bg_color": {"label": "BACKGROUND", "channels": ["R", "G", "B"]},
	"button_color": {"label": "BUTTON", "channels": ["R", "G", "B", "A"]},
}

var main # MainManager (owner of the menu panel and drawing helpers)

var settings: Dictionary = {}
var defaults: Dictionary = {}
var custom: Dictionary = {"bg_color": false, "button_color": false, "orientation": false}

var is_open: bool = false
var _panel_ref: Object = null
var mode: int = Mode.LIST
var node_stack: Array = []
var cursors: Dictionary = {}
var active_key: String = ""
var channel_idx: int = 0
var tweak_row: int = 0
var sens_idx: int = DEFAULT_SENS_INDEX

var presets # PresetsMenu.gd (System Main Menu > PRESETS)

# Controller layout. Nodes are found from the existing buttons; their original ("standard") arrangement is
# remembered so every layout is rebuilt from it and never drifts.
var _layout_ready: bool = false
var _flex_root: BoxContainer   # replaces the fixed HBox root: display | strip | controls (vertical in portrait)
var _strip: BoxContainer       # replaces the fixed VBox trench: PWR / spacer / OPT (horizontal in portrait)
var _host                      # square host of the shader display
var _action_row
var _chassis
var _dpad
var _std_root: Array = []
var _std_strip: Array = []
var _std_action: Array = []
var _std_chassis: Array = []
var _std_host_vflag: int = 0
var _std_chassis_hflag: int = 0
var _std_dpad_flag: int = 0


# =========================================================================
# SETUP / PERSISTENCE
# =========================================================================
func setup(main_manager) -> void:
	main = main_manager
	presets = load("res://PresetsMenu.gd").new()
	presets.setup(main, self)
	# Capture what the app looks like BEFORE any customization so RESET can restore it
	defaults["bg_color"] = ProjectSettings.get_setting("rendering/environment/defaults/default_clear_color", Color(0.3, 0.3, 0.3, 1.0))
	defaults["button_color"] = _read_default_button_color()
	settings["bg_color"] = defaults["bg_color"]
	settings["button_color"] = defaults["button_color"]
	settings["landscape_layout"] = 0
	settings["portrait_layout"] = 0
	settings["orientation"] = 0 # 0 landscape, 1 portrait
	_capture_standard_layout() # before any saved layout is applied
	if _layout_ready:
		main.get_window().size_changed.connect(_on_window_resized)
	_load_settings()
	_apply_all()

func _read_default_button_color() -> Color:
	var buttons: Array = _collect_buttons(main.ui_canvas_layer)
	if not buttons.is_empty():
		var sb: StyleBox = buttons[0].get_theme_stylebox("normal")
		if sb is StyleBoxFlat:
			return (sb as StyleBoxFlat).bg_color
	return Color(0.1, 0.1, 0.1, 0.6)

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	for key in ["bg_color", "button_color"]:
		if cfg.get_value("colors", key + "_custom", false):
			var c = cfg.get_value("colors", key, settings[key])
			if c is Color:
				settings[key] = c
				custom[key] = true
	settings["landscape_layout"] = clampi(int(cfg.get_value("layout", "landscape_layout", 0)), 0, 3)
	settings["portrait_layout"] = clampi(int(cfg.get_value("layout", "portrait_layout", 0)), 0, 3)
	settings["orientation"] = clampi(int(cfg.get_value("layout", "orientation", 0)), 0, 1)
	custom["orientation"] = bool(cfg.get_value("layout", "orientation_custom", false))

func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH) # keep sections that later steps add (layout, orientation)
	for key in ["bg_color", "button_color"]:
		cfg.set_value("colors", key + "_custom", custom[key])
		cfg.set_value("colors", key, settings[key])
	cfg.set_value("layout", "landscape_layout", settings["landscape_layout"])
	cfg.set_value("layout", "portrait_layout", settings["portrait_layout"])
	cfg.set_value("layout", "orientation", settings["orientation"])
	cfg.set_value("layout", "orientation_custom", custom["orientation"])
	cfg.save(SETTINGS_PATH)


# =========================================================================
# APPLYING COLORS
# =========================================================================
func _apply_all() -> void:
	_apply_background()
	_apply_buttons()
	_apply_layout()

## Background = the window color behind the whole console (the shader display is unaffected).
func _apply_background() -> void:
	var c: Color = settings["bg_color"]
	RenderingServer.set_default_clear_color(Color(c.r, c.g, c.b, 1.0))

func _collect_buttons(root: Node) -> Array:
	var out: Array = []
	for child in root.get_children():
		if child is Button:
			out.append(child)
		out.append_array(_collect_buttons(child))
	return out

## Hover and pressed are simply shades of the chosen button color.
func _state_color(base: Color, state: String) -> Color:
	match state:
		"hover":
			return base.lightened(0.15)
		"pressed":
			return base.darkened(0.25)
		"hover_pressed":
			return base.darkened(0.15)
	return base

func _apply_buttons() -> void:
	var buttons: Array = _collect_buttons(main.ui_canvas_layer)
	if not custom["button_color"]:
		# Untouched (or reset): only undo styles this menu added, never anything else
		for btn in buttons:
			if btn.has_meta("tatool_styled"):
				for state in BUTTON_STATES:
					btn.remove_theme_stylebox_override(state)
				btn.remove_meta("tatool_styled")
		return

	var base: Color = settings["button_color"]
	for btn in buttons:
		for state in BUTTON_STATES:
			var sb: StyleBoxFlat = null
			if btn.has_theme_stylebox_override(state):
				sb = btn.get_theme_stylebox(state) as StyleBoxFlat
			if sb == null:
				# Start from the button's current style so its shape and margins stay the same
				var src: StyleBox = btn.get_theme_stylebox(state)
				if src is StyleBoxFlat:
					sb = src.duplicate() as StyleBoxFlat
				else:
					sb = StyleBoxFlat.new()
					sb.set_corner_radius_all(4)
				btn.add_theme_stylebox_override(state, sb)
			sb.bg_color = _state_color(base, state)
		btn.set_meta("tatool_styled", true)

func _get_channel(key: String, idx: int) -> float:
	var c: Color = settings[key]
	return c[idx]

func _set_channel(key: String, idx: int, v: float) -> void:
	var c: Color = settings[key]
	c[idx] = clampf(snappedf(v, 0.000001), 0.0, 1.0)
	settings[key] = c
	custom[key] = true
	if key == "bg_color":
		_apply_background()
	else:
		_apply_buttons()
	_save_settings()

func _reset_colors() -> void:
	settings["bg_color"] = defaults["bg_color"]
	settings["button_color"] = defaults["button_color"]
	custom["bg_color"] = false
	custom["button_color"] = false
	_apply_all()
	_save_settings()


# =========================================================================
# CONTROLLER LAYOUT (landscape + portrait, each with mirrors)
# Your own button code is never rebuilt. Containers are found from the existing buttons, and
# only their child ORDER and a few size flags change. Two fixed containers are swapped once for
# flexible ones (BoxContainer) that can switch between horizontal and vertical.
#   landscape:  display | strip (vertical) | controls          (side by side)
#   portrait:   display / strip (horizontal) / controls        (stacked)
# Mirrors: horizontal flips left-right, vertical flips top-bottom, whichever way the axes run.
# =========================================================================
func _capture_standard_layout() -> void:
	var cp = main.control_panel
	var old_root = cp.get_parent()
	var old_trench = main.btn_shader_menu.get_parent()
	var host = main.canvas_container.get_parent()
	var action_row = cp.btn_channel.get_parent()
	var chassis = action_row.get_parent() if action_row else null
	var dpad = cp.btn_param_up.get_parent()
	if old_root == null or old_trench == null or host == null or action_row == null or chassis == null or dpad == null:
		push_warning("OptionsMenu: controller layout containers not found; layout options disabled")
		return

	_host = host
	_action_row = action_row
	_chassis = chassis
	_dpad = dpad
	_std_action = action_row.get_children()
	_std_chassis = chassis.get_children()
	_std_host_vflag = host.size_flags_vertical
	_std_chassis_hflag = chassis.size_flags_horizontal
	_std_dpad_flag = dpad.size_flags_horizontal

	# The trench becomes a BoxContainer whose direction can flip (its spacer must stretch both ways)
	_strip = BoxContainer.new()
	_strip.alignment = BoxContainer.ALIGNMENT_CENTER
	_std_strip = old_trench.get_children()
	for kid in _std_strip:
		old_trench.remove_child(kid)
		_strip.add_child(kid)
		if not (kid is Button):
			kid.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# So does the main root: same children, same order, same flags, new container
	_flex_root = BoxContainer.new()
	_flex_root.mouse_filter = Control.MOUSE_FILTER_PASS
	main.ui_canvas_layer.add_child(_flex_root)
	_flex_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_std_root = []
	for kid in old_root.get_children():
		old_root.remove_child(kid)
		if kid == old_trench:
			_flex_root.add_child(_strip)
			_std_root.append(_strip)
		else:
			_flex_root.add_child(kid)
			_std_root.append(kid)
	old_trench.queue_free()
	old_root.queue_free()

	# Moving the display's nodes can drop their texture links, so re-bind them
	main.pass2_material.set_shader_parameter("u_pattern_texture", main.pass1_viewport.get_texture())
	main.pass3_material.set_shader_parameter("u_warped_texture", main.pass2_viewport.get_texture())
	_layout_ready = true

## Ask the device (or desktop window) for the chosen orientation. Only done once the user has chosen one.
func _apply_layout() -> void:
	if not _layout_ready:
		return
	if custom["orientation"]:
		_request_orientation(int(settings["orientation"]) == 1)
	_relayout()

func _request_orientation(portrait: bool) -> void:
	var size_now: Vector2i = DisplayServer.window_get_size()
	if (size_now.y > size_now.x) == portrait:
		return # the window already has that shape
	if OS.has_feature("mobile"):
		DisplayServer.screen_set_orientation(DisplayServer.SCREEN_PORTRAIT if portrait else DisplayServer.SCREEN_LANDSCAPE)
	else:
		main.get_window().size = Vector2i(size_now.y, size_now.x) # desktop: swap width and height
	# The new size arrives a moment later; _on_window_resized() then re-fits everything

func _on_window_resized() -> void:
	if presets != null and presets.typing:
		return # the on-screen keyboard can resize the window; re-check once typing ends
	_relayout()

## Called by PresetsMenu when the name field loses focus.
func notify_typing_done() -> void:
	_relayout()

## Arrange everything for the window's CURRENT shape (tall = portrait) using that shape's saved layout.
func _relayout() -> void:
	if not _layout_ready:
		return
	var win_size: Vector2i = DisplayServer.window_get_size()
	var portrait: bool = win_size.y > win_size.x
	var index: int = int(settings["portrait_layout"]) if portrait else int(settings["landscape_layout"])
	var flip_h: bool = index == 1 or index == 3
	var flip_v: bool = index == 2 or index == 3
	var side: int = mini(win_size.x, win_size.y) # the display is always a square of the short side

	# Directions
	_flex_root.vertical = portrait
	_strip.vertical = not portrait
	_strip.custom_minimum_size = Vector2(0, 96) if portrait else Vector2(96, 0)

	# Order: start from standard, reverse whichever containers run along the flipped axis
	_set_order(_flex_root, _std_root, flip_v if portrait else flip_h)
	_set_order(_strip, _std_strip, flip_h if portrait else flip_v)
	_set_order(_action_row, _std_action, flip_h)   # A and B swap sides (a true mirror)
	_set_order(_chassis, _std_chassis, flip_v)     # D-pad above, A/B below
	_dpad.size_flags_horizontal = Control.SIZE_SHRINK_END if flip_h else _std_dpad_flag

	# Portrait: shrink the controls to their natural width and center them, which brings
	# the D-pad and A/B together exactly as tuned instead of stretching across the wide screen
	_chassis.size_flags_horizontal = Control.SIZE_SHRINK_CENTER if portrait else _std_chassis_hflag

	# The shader display stays square: host, container, the three buffers and their rectangles
	_host.custom_minimum_size = Vector2(side, side)
	_host.size_flags_vertical = Control.SIZE_FILL if portrait else _std_host_vflag
	main.canvas_container.custom_minimum_size = Vector2(side, side)
	# (pass 3 sits inside the stretching SubViewportContainer, which sizes it by itself)
	for vp in [main.pass1_viewport, main.pass2_viewport]:
		vp.size = Vector2i(side, side)
	for rect in [main.pass1_rect, main.pass2_rect, main.pass3_rect]:
		rect.custom_minimum_size = Vector2(side, side)
		rect.size = Vector2(side, side)

func _set_order(container: Node, nodes: Array, reversed: bool) -> void:
	var list: Array = nodes.duplicate()
	if reversed:
		list.reverse()
	for i in range(list.size()):
		container.move_child(list[i], i)


# =========================================================================
# OPEN / STATE
# =========================================================================
func open() -> void:
	is_open = true
	mode = Mode.LIST
	node_stack = ["root"]
	cursors.clear()
	main._ensure_cyan_panel() # recycles the System Menu's panel and clears its rows
	_panel_ref = main.menu_overlay_panel
	redraw()

## True only while our own panel is still the one on screen (PWR/OPT closing it makes this false).
func is_active() -> bool:
	if presets != null and presets.is_active():
		return true
	return is_open and is_instance_valid(_panel_ref) and main.menu_overlay_panel == _panel_ref

## System Main Menu > PRESETS
func open_presets() -> void:
	presets.open()


# =========================================================================
# INPUT (called by DynamicUI)
# =========================================================================
func handle_vertical(step: int) -> void:
	if presets != null and presets.is_active():
		presets.handle_vertical(step)
		return
	match mode:
		Mode.LIST:
			var node_id: String = node_stack.back()
			var total: int = TREE[node_id]["rows"].size()
			cursors[node_id] = posmod(int(cursors.get(node_id, 0)) + step, total)
		Mode.CHANNEL:
			channel_idx = posmod(channel_idx + step, COLOR_DEFS[active_key]["channels"].size())
		Mode.TWEAK:
			tweak_row = posmod(tweak_row + step, 2)
	redraw()

func handle_horizontal(step: int) -> void:
	if presets != null and presets.is_active():
		presets.handle_horizontal(step)
		return
	if mode != Mode.TWEAK:
		return
	if tweak_row == 0:
		var current: float = _get_channel(active_key, channel_idx)
		_set_channel(active_key, channel_idx, current + float(step) * float(SENS_LADDER[sens_idx]))
	else:
		sens_idx = clampi(sens_idx + step, 0, SENS_LADDER.size() - 1)
	redraw()

func handle_a() -> void:
	if presets != null and presets.is_active():
		presets.handle_a()
		return
	match mode:
		Mode.LIST:
			var node_id: String = node_stack.back()
			var rows: Array = TREE[node_id]["rows"]
			var row: Dictionary = rows[int(cursors.get(node_id, 0))]
			match row["kind"]:
				"go":
					var target: String = row["target"]
					node_stack.append(target)
					if TREE[target].has("cursor_from"):
						cursors[target] = int(settings[TREE[target]["cursor_from"]])
				"choice":
					settings[row["setting"]] = int(row["value"])
					settings["orientation"] = int(row["orientation"])
					custom["orientation"] = true
					_apply_layout()
					_save_settings()
				"color":
					active_key = row["key"]
					channel_idx = 0
					mode = Mode.CHANNEL
				"action":
					if row["action"] == "reset_colors":
						_reset_colors()
		Mode.CHANNEL:
			tweak_row = 0
			sens_idx = DEFAULT_SENS_INDEX
			mode = Mode.TWEAK
		Mode.TWEAK:
			return
	redraw()

## Steps back one level. Returns true when the options menu itself is closed
## (the caller then redraws the System Main Menu).
func handle_b() -> bool:
	if presets != null and presets.is_active():
		return presets.handle_b()
	match mode:
		Mode.TWEAK:
			mode = Mode.CHANNEL
		Mode.CHANNEL:
			mode = Mode.LIST
		Mode.LIST:
			if node_stack.size() > 1:
				node_stack.pop_back()
			else:
				is_open = false
				_panel_ref = null
				return true
	redraw()
	return false


# =========================================================================
# DRAWING (uses MainManager's menu helpers so it looks like the other menus)
# =========================================================================
func redraw() -> void:
	if not is_instance_valid(main.menu_list_box):
		return
	for child in main.menu_list_box.get_children():
		child.queue_free()
	match mode:
		Mode.LIST:
			_draw_list()
		Mode.CHANNEL:
			_draw_channels()
		Mode.TWEAK:
			_draw_tweak()

func _add_label(text: String, color: Color) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", color)
	main.menu_list_box.add_child(lbl)

func _add_swatch(c: Color) -> void:
	var sw := ColorRect.new()
	sw.custom_minimum_size = Vector2(0, 16)
	sw.color = c
	main.menu_list_box.add_child(sw)

func _draw_list() -> void:
	var node_id: String = node_stack.back()
	var node: Dictionary = TREE[node_id]
	_add_label(node["title"], Color.RED)

	var rows: Array = node["rows"]
	var cursor: int = int(cursors.get(node_id, 0))
	var start: int = main._window_start(rows.size(), cursor)
	var stop: int = mini(start + main.MENU_PAGE_ROWS, rows.size())
	var scrolling: bool = rows.size() > main.MENU_PAGE_ROWS

	if scrolling: main._add_scroll_hint(start > 0, "▲")
	for i in range(start, stop):
		var row: Dictionary = rows[i]
		var is_action: bool = row["kind"] == "action"
		var hl: Color = Color.WHITE if is_action else Color.YELLOW
		var dim: Color = Color.LIGHT_GOLDENROD if is_action else Color.DARK_GRAY
		var text: String = row["label"]
		if row["kind"] == "choice":
			var chosen: bool = (int(settings["orientation"]) == int(row["orientation"])
					and int(settings[row["setting"]]) == int(row["value"]))
			text = ("● " if chosen else "○ ") + text
		main._add_menu_row(text, i == cursor, hl, dim)
	if scrolling: main._add_scroll_hint(stop < rows.size(), "▼")

func _draw_channels() -> void:
	var def: Dictionary = COLOR_DEFS[active_key]
	_add_label(" ◈ %s COLOR ◈ SELECT PARAMETER " % def["label"], Color.MAGENTA)
	_add_swatch(_opaque_if_background(active_key))
	var names: Array = def["channels"]
	for i in range(names.size()):
		var value_text: String = main._fmt(_get_channel(active_key, i))
		main._add_menu_row("%s   [ %s ]" % [names[i], value_text], i == channel_idx)

func _draw_tweak() -> void:
	var def: Dictionary = COLOR_DEFS[active_key]
	var names: Array = def["channels"]
	var value: float = _get_channel(active_key, channel_idx)
	var default_color: Color = defaults[active_key]
	var default_value: float = default_color[channel_idx]
	var sens_now: float = SENS_LADDER[sens_idx]

	_add_label(" +═ COLOR TWEAK CONSOLE ═+ ", Color.ORANGE)
	_add_swatch(_opaque_if_background(active_key))
	_add_label(" ║ NAME: %s  ·  %s " % [def["label"], names[channel_idx]], Color.WHITE)

	if tweak_row == 0:
		_add_label(" ▶ ║ VALUE: ◄ [ %s ] ► " % main._fmt(value), Color.YELLOW)
		_add_label("    ║ SENS :   [ %s ]   " % main._fmt(sens_now), Color.DARK_GRAY)
	else:
		_add_label("    ║ VALUE:   [ %s ]   " % main._fmt(value), Color.DARK_GRAY)
		_add_label(" ▶ ║ SENS : ◄ [ %s ] ► " % main._fmt(sens_now), Color.YELLOW)

	_add_label(" ║                            ║ ", Color.DARK_GRAY)
	_add_label(" ║ DEFAULT VAL : [ %s ]   ║ " % main._fmt(default_value), Color.DIM_GRAY)
	_add_label(" ║ RECOMMENDED SENS: [ %s ]   ║ " % main._fmt(SENS_LADDER[DEFAULT_SENS_INDEX]), Color.DIM_GRAY)
	_add_label(" +════════════════════════════+ ", Color.ORANGE)

func _opaque_if_background(key: String) -> Color:
	var c: Color = settings[key]
	if key == "bg_color":
		return Color(c.r, c.g, c.b, 1.0)
	return c
