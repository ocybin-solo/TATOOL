extends RefCounted
## OptionsMenu.gd -- TATOOL app options (System Main Menu > APP CONFIG OPTIONS)
## Step 1: Colors (background + button colors). Step 2: Controller Layout > Landscape mirroring.
## Everything is saved to user:// and re-applied at launch. Portrait comes in a later step by extending TREE.
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
		],
	},
	"landscape": {
		"title": " LANDSCAPE LAYOUT ",
		"cursor_from": "landscape_layout", # open with the cursor on the layout currently in use
		"rows": [
			{"label": "STANDARD", "kind": "choice", "setting": "landscape_layout", "value": 0},
			{"label": "MIRRORED HORIZONTALLY", "kind": "choice", "setting": "landscape_layout", "value": 1},
			{"label": "MIRRORED VERTICALLY", "kind": "choice", "setting": "landscape_layout", "value": 2},
			{"label": "MIRRORED HORIZ + VERT", "kind": "choice", "setting": "landscape_layout", "value": 3},
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
var custom: Dictionary = {"bg_color": false, "button_color": false}

var is_open: bool = false
var _panel_ref: Object = null
var mode: int = Mode.LIST
var node_stack: Array = []
var cursors: Dictionary = {}
var active_key: String = ""
var channel_idx: int = 0
var tweak_row: int = 0
var sens_idx: int = DEFAULT_SENS_INDEX

# Controller layout: nodes found from the existing buttons, plus their original ("standard") arrangement
var _layout_ready: bool = false
var _layout_root
var _layout_action_row
var _layout_chassis
var _layout_dpad
var _layout_trench
var _std_order: Dictionary = {}
var _std_dpad_flag: int = 0


# =========================================================================
# SETUP / PERSISTENCE
# =========================================================================
func setup(main_manager) -> void:
	main = main_manager
	# Capture what the app looks like BEFORE any customization so RESET can restore it
	defaults["bg_color"] = ProjectSettings.get_setting("rendering/environment/defaults/default_clear_color", Color(0.3, 0.3, 0.3, 1.0))
	defaults["button_color"] = _read_default_button_color()
	settings["bg_color"] = defaults["bg_color"]
	settings["button_color"] = defaults["button_color"]
	settings["landscape_layout"] = 0
	_capture_standard_layout() # before any saved layout is applied
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

func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH) # keep sections that later steps add (layout, orientation)
	for key in ["bg_color", "button_color"]:
		cfg.set_value("colors", key + "_custom", custom[key])
		cfg.set_value("colors", key, settings[key])
	cfg.set_value("layout", "landscape_layout", settings["landscape_layout"])
	cfg.save(SETTINGS_PATH)


# =========================================================================
# APPLYING COLORS
# =========================================================================
func _apply_all() -> void:
	_apply_background()
	_apply_buttons()
	_apply_landscape()

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
# CONTROLLER LAYOUT (landscape mirroring)
# The existing layout is never rebuilt: containers are found from the existing buttons and their
# children are only re-ordered, so your own button placement stays the "standard" layout.
# =========================================================================
func _capture_standard_layout() -> void:
	var cp = main.control_panel
	_layout_action_row = cp.btn_channel.get_parent()
	_layout_chassis = _layout_action_row.get_parent() if _layout_action_row else null
	_layout_dpad = cp.btn_param_up.get_parent()
	_layout_trench = main.btn_shader_menu.get_parent()
	_layout_root = cp.get_parent()
	_layout_ready = (_layout_action_row != null and _layout_chassis != null and _layout_dpad != null
			and _layout_trench != null and _layout_root != null)
	if not _layout_ready:
		push_warning("OptionsMenu: controller layout containers not found; layout options disabled")
		return
	for container in [_layout_root, _layout_action_row, _layout_chassis, _layout_trench]:
		_std_order[container] = container.get_children()
	_std_dpad_flag = _layout_dpad.size_flags_horizontal

func _apply_landscape() -> void:
	if not _layout_ready:
		return
	var index: int = int(settings["landscape_layout"])
	var flip_h: bool = index == 1 or index == 3
	var flip_v: bool = index == 2 or index == 3

	# Start from the standard arrangement every time so switching layouts never drifts
	for container in _std_order:
		var order: Array = _std_order[container]
		for i in range(order.size()):
			container.move_child(order[i], i)
	_layout_dpad.size_flags_horizontal = _std_dpad_flag

	if flip_h:
		_reverse_children(_layout_root)        # display / trench / controls swap sides
		_reverse_children(_layout_action_row)  # A and B swap sides (a true mirror)
		_layout_dpad.size_flags_horizontal = Control.SIZE_SHRINK_END # D-pad hugs the far side
	if flip_v:
		_reverse_children(_layout_chassis)     # D-pad on top, A/B underneath
		_reverse_children(_layout_trench)      # PWR and OPT swap top and bottom

func _reverse_children(container: Node) -> void:
	var kids: Array = container.get_children()
	kids.reverse()
	for i in range(kids.size()):
		container.move_child(kids[i], i)


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
	return is_open and is_instance_valid(_panel_ref) and main.menu_overlay_panel == _panel_ref


# =========================================================================
# INPUT (called by DynamicUI)
# =========================================================================
func handle_vertical(step: int) -> void:
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
	if mode != Mode.TWEAK:
		return
	if tweak_row == 0:
		var current: float = _get_channel(active_key, channel_idx)
		_set_channel(active_key, channel_idx, current + float(step) * float(SENS_LADDER[sens_idx]))
	else:
		sens_idx = clampi(sens_idx + step, 0, SENS_LADDER.size() - 1)
	redraw()

func handle_a() -> void:
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
					_apply_landscape()
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
			var chosen: bool = int(settings[row["setting"]]) == int(row["value"])
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
