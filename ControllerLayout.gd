extends RefCounted
## ControllerLayout.gd -- TATOOL controller layout engine
##
## All eight control buttons live in ONE centered 5 x 5 grid inside the controls area (cell index = row * 5 + column).
## Any button can sit in any cell. In "Reposition Buttons" mode a transparent overlay (GridEditOverlay.gd) covers
## the grid: press and hold a button to drag it, drop it on an empty cell to move it, or on a taken cell to swap.
## A tap on the A button accepts the layout, a tap on the B button cancels the changes.
##
## Your own button code (icons, sizes, colors, wiring) is not touched. At startup the existing buttons are moved into
## the grid cells and the old spacer containers are discarded. Every cell is a plain Control, not a Container, because
## Containers reset a child's rotation and scale, which the icon rotate/flip needs.
##
## Saved per orientation (landscape / portrait, picked from the window's current shape, no menu gate):
##   pos          button id -> cell index
##   flip_screen  swaps the display area with the controls area
##   icons        per button [quarter turns 0..3, mirrored]
## Saved once: orient_mode (Auto / Landscape / Portrait), and the menu's rotation and mirroring.

const SETTINGS_PATH: String = "user://tatool_settings.cfg"
const COLUMNS: int = 5
const ROWS: int = 5
const GRID_GAP: int = 4 # pixels between cells

const ALL_IDS: Array = ["a", "b", "quick", "main", "up", "down", "left", "right"]
const BUTTON_NAMES: Dictionary = {
	"a": "A BUTTON", "b": "B BUTTON", "quick": "QUICK MENU BUTTON", "main": "MAIN MENU BUTTON",
	"up": "UP BUTTON", "down": "DOWN BUTTON", "left": "LEFT BUTTON", "right": "RIGHT BUTTON",
}
# The previous 3 x 5 look, centered in the wider grid
const DEFAULT_POS: Dictionary = {"a": 1, "quick": 3, "b": 21, "main": 23, "up": 7, "left": 11, "right": 13, "down": 17}
const ORIENT_MODE_NAMES: Array = ["AUTO", "LANDSCAPE", "PORTRAIT"]

var main         # MainManager
var owner_menu   # OptionsMenu

var ready_ok: bool = false
var configs: Array = []       # [landscape config, portrait config]
var orient_mode: int = 0      # 0 auto (follow the device), 1 landscape, 2 portrait
var menu_rot: int = 0         # menu quarter turns, clockwise
var menu_flip: bool = false   # menu mirrored left-right
var editing: bool = false

var _buttons: Dictionary = {} # id -> Button
var _holders: Array = []      # the 25 grid cells
var _cell: Vector2 = Vector2(96, 96)
var _flex_root: BoxContainer  # display + controls; stacks vertically in portrait
var _cp                       # the controls panel (DynamicUI)
var _host                     # square host of the shader display
var _overlay                  # GridEditOverlay
var _std_host_vflag: int = 0
var _spare_label              # the old center readout, kept alive but out of the tree
var _edit_orient: int = 0
var _edit_snapshot: Dictionary = {}


func _default_config() -> Dictionary:
	return {"pos": DEFAULT_POS.duplicate(), "flip_screen": false, "icons": {}}


# =========================================================================
# SETUP: move the existing buttons into the grid
# =========================================================================
func setup(main_manager, owner_options: Object) -> void:
	main = main_manager
	owner_menu = owner_options
	configs = [_default_config(), _default_config()]
	_capture()
	if not ready_ok:
		return
	load_settings()
	main.get_window().size_changed.connect(_on_window_resized)
	main.menu_center_host.resized.connect(_apply_menu_orient)
	_apply_orient_mode()
	_apply_menu_orient()
	relayout()

func _capture() -> void:
	var cp = main.control_panel
	var found: Dictionary = {
		"a": cp.btn_channel, "b": cp.btn_sens_left,
		"quick": main.btn_select_pass, "main": main.btn_shader_menu,
		"up": cp.btn_param_up, "down": cp.btn_param_down,
		"left": cp.btn_channel_prev, "right": cp.btn_channel_next,
	}
	for id in found:
		if found[id] == null:
			push_warning("ControllerLayout: button '%s' not found; layout options disabled" % id)
			return

	var old_root = cp.get_parent()
	var host = main.canvas_container.get_parent()
	var old_trench = main.btn_shader_menu.get_parent()
	var old_chassis = cp.btn_channel.get_parent().get_parent()
	if old_root == null or host == null or old_trench == null or old_chassis == null:
		push_warning("ControllerLayout: existing layout containers not found; layout options disabled")
		return

	_buttons = found
	_cp = cp
	_host = host
	_std_host_vflag = host.size_flags_vertical

	# Cells are as big as the biggest button (96 x 96 in your layout)
	_cell = Vector2.ZERO
	for id in _buttons:
		var m: Vector2 = _buttons[id].custom_minimum_size
		_cell = Vector2(maxf(_cell.x, m.x), maxf(_cell.y, m.y))
	if _cell.x <= 0.0 or _cell.y <= 0.0:
		_cell = Vector2(96, 96)

	# A plain Control holds the grid AND the edit overlay on top of it, centered in the controls area
	var grid_size := Vector2(COLUMNS * _cell.x + (COLUMNS - 1) * GRID_GAP, ROWS * _cell.y + (ROWS - 1) * GRID_GAP)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	cp.add_child(center)
	var wrapper := Control.new()
	wrapper.custom_minimum_size = grid_size
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(wrapper)
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", GRID_GAP)
	grid.add_theme_constant_override("v_separation", GRID_GAP)
	wrapper.add_child(grid)
	grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for i in range(COLUMNS * ROWS):
		var holder := Control.new()
		holder.custom_minimum_size = _cell
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grid.add_child(holder)
		_holders.append(holder)

	_overlay = load("res://GridEditOverlay.gd").new()
	wrapper.add_child(_overlay)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.setup(self)

	# Buttons out of the old containers and into cells (real positions are set by relayout())
	for i in range(ALL_IDS.size()):
		_place(_buttons[ALL_IDS[i]], _holders[i])

	# The old center readout is no longer needed. It is kept alive (DynamicUI still holds a reference to it)
	# but taken out of the tree.
	_spare_label = cp.label_sens_indicator
	if _spare_label != null and _spare_label.get_parent() != null:
		_spare_label.get_parent().remove_child(_spare_label)

	# One flexible root replaces the fixed HBox: display + controls, vertical in portrait
	_flex_root = BoxContainer.new()
	_flex_root.mouse_filter = Control.MOUSE_FILTER_PASS
	main.ui_canvas_layer.add_child(_flex_root)
	_flex_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for kid in old_root.get_children():
		old_root.remove_child(kid)
	_flex_root.add_child(host)
	_flex_root.add_child(cp)

	# The old spacers, rows, grid and PWR/OPT trench are now empty shells
	old_chassis.queue_free()
	old_trench.queue_free()
	old_root.queue_free()

	# Moving the display's nodes can drop their texture links, so re-bind them
	main.pass2_material.set_shader_parameter("u_pattern_texture", main.pass1_viewport.get_texture())
	main.pass3_material.set_shader_parameter("u_warped_texture", main.pass2_viewport.get_texture())
	ready_ok = true

func _place(btn: Control, holder: Control) -> void:
	if btn.get_parent() == holder:
		return
	if btn.get_parent() != null:
		btn.get_parent().remove_child(btn)
	holder.add_child(btn)
	btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	btn.pivot_offset = _cell * 0.5 # rotate and flip around the button's center


# =========================================================================
# SCREEN ORIENTATION
# =========================================================================
func current_orient() -> int:
	var s: Vector2i = DisplayServer.window_get_size()
	return 1 if s.y > s.x else 0

func set_orient_mode(mode: int) -> void:
	orient_mode = clampi(mode, 0, 2)
	_apply_orient_mode()
	relayout()
	save()

## Auto lets the device's sensor decide (on a phone). Landscape / Portrait force it. On desktop there is no
## sensor, so Auto leaves the window alone and the other two swap its width and height.
func _apply_orient_mode() -> void:
	if OS.has_feature("mobile"):
		match orient_mode:
			0:
				DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR)
			1:
				DisplayServer.screen_set_orientation(DisplayServer.SCREEN_LANDSCAPE)
			2:
				DisplayServer.screen_set_orientation(DisplayServer.SCREEN_PORTRAIT)
	elif orient_mode != 0:
		var size_now: Vector2i = DisplayServer.window_get_size()
		if (size_now.y > size_now.x) != (orient_mode == 2):
			main.get_window().size = Vector2i(size_now.y, size_now.x)
	# When the window changes shape, _on_window_resized() re-fits everything

func _on_window_resized() -> void:
	if owner_menu != null and owner_menu.presets != null and owner_menu.presets.typing:
		return # the on-screen keyboard can resize the window; re-check once typing ends
	if editing:
		edit_cancel() # the window changed shape mid-edit: put the layout back and leave edit mode
	relayout()


# =========================================================================
# RELAYOUT: arrange everything for the window's CURRENT shape (tall = portrait)
# =========================================================================
func relayout() -> void:
	if not ready_ok:
		return
	var win_size: Vector2i = DisplayServer.window_get_size()
	var portrait: bool = win_size.y > win_size.x
	var cfg: Dictionary = configs[1 if portrait else 0]
	var side: int = mini(win_size.x, win_size.y) # the display is always a square of the short side

	# Display and controls side by side (landscape) or stacked (portrait); Flip Screen swaps them
	_flex_root.vertical = portrait
	var order: Array = [_host, _cp]
	if cfg["flip_screen"]:
		order.reverse()
	for i in range(order.size()):
		_flex_root.move_child(order[i], i)

	# Buttons into their cells, with their icon rotation / mirroring
	for id in ALL_IDS:
		_place(_buttons[id], _holders[int(cfg["pos"][id])])
		var st: Array = _icon_state(cfg, id)
		_buttons[id].rotation_degrees = 90.0 * int(st[0])
		_buttons[id].scale = Vector2(-1.0 if bool(st[1]) else 1.0, 1.0)

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

func _icon_state(cfg: Dictionary, id: String) -> Array:
	return cfg["icons"].get(id, [0, false])


# =========================================================================
# GRID GEOMETRY AND CONTENTS (used by the edit overlay)
# =========================================================================
func cell_size() -> Vector2:
	return _cell

func cell_rect(cell: int) -> Rect2:
	var pitch: Vector2 = _cell + Vector2(GRID_GAP, GRID_GAP)
	var col: int = cell % COLUMNS
	var row: int = floori(float(cell) / float(COLUMNS))
	return Rect2(Vector2(col * pitch.x, row * pitch.y), _cell)

## The cell under a point in grid coordinates, or -1 outside the grid.
func cell_at(pos: Vector2) -> int:
	if pos.x < 0.0 or pos.y < 0.0:
		return -1
	var pitch: Vector2 = _cell + Vector2(GRID_GAP, GRID_GAP)
	var col: int = int(pos.x / pitch.x)
	var row: int = int(pos.y / pitch.y)
	if col >= COLUMNS or row >= ROWS:
		return -1
	return row * COLUMNS + col

func _active_cfg() -> Dictionary:
	return configs[_edit_orient] if editing else configs[current_orient()]

func button_at(cell: int) -> String:
	if cell < 0:
		return ""
	var pos: Dictionary = _active_cfg()["pos"]
	for id in pos:
		if int(pos[id]) == cell:
			return id
	return ""

func cell_of(id: String) -> int:
	return int(_active_cfg()["pos"][id])

## A see-through copy of a button that follows the finger during a drag (no signals, so it can never fire).
func make_ghost(id: String) -> Control:
	var g: Control = _buttons[id].duplicate(0)
	g.set_anchors_preset(Control.PRESET_TOP_LEFT, false)
	g.size = _cell
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.modulate = Color(1, 1, 1, 0.8)
	return g

func set_button_dim(id: String, dim: bool) -> void:
	_buttons[id].modulate = Color(1, 1, 1, 0.3 if dim else 1.0)


# =========================================================================
# REPOSITION SESSION
# =========================================================================
func begin_edit() -> void:
	if not ready_ok or editing:
		return
	_edit_orient = current_orient()
	_edit_snapshot = configs[_edit_orient].duplicate(true)
	editing = true
	_overlay.reset_interaction()
	_overlay.visible = true
	_overlay.queue_redraw()

## Drop: the button takes the cell; a button already there takes the vacated cell (a swap).
func edit_move(id: String, target: int) -> void:
	if not editing:
		return
	var pos: Dictionary = configs[_edit_orient]["pos"]
	var source: int = int(pos[id])
	var occupant: String = button_at(target)
	pos[id] = target
	if occupant != "" and occupant != id:
		pos[occupant] = source
	relayout()
	_overlay.queue_redraw()

func edit_accept() -> void:
	if not editing:
		return
	_end_edit()
	save()
	relayout()
	owner_menu.reposition_finished(true)

func edit_cancel() -> void:
	if not editing:
		return
	configs[_edit_orient] = _edit_snapshot
	_end_edit()
	relayout()
	owner_menu.reposition_finished(false)

func _end_edit() -> void:
	editing = false
	_overlay.reset_interaction()
	_overlay.visible = false


# =========================================================================
# EDITING (called by the options menu; every change applies at once and is saved)
# =========================================================================
func button_name(id: String) -> String:
	return BUTTON_NAMES.get(id, id)

func is_screen_flipped(orient: int) -> bool:
	return bool(configs[orient]["flip_screen"])

func toggle_flip_screen(orient: int) -> void:
	configs[orient]["flip_screen"] = not is_screen_flipped(orient)
	relayout()
	save()

func icon_rotation(orient: int, id: String) -> int:
	return int(_icon_state(configs[orient], id)[0]) * 90

func icon_flipped(orient: int, id: String) -> bool:
	return bool(_icon_state(configs[orient], id)[1])

func icon_state_text(orient: int, id: String) -> String:
	return "%d°%s" % [icon_rotation(orient, id), " FLIPPED" if icon_flipped(orient, id) else ""]

## Rotate the icon a quarter turn clockwise, as seen on screen.
func rotate_icon(orient: int, id: String) -> void:
	var st: Array = _icon_state(configs[orient], id)
	configs[orient]["icons"][id] = [(int(st[0]) + 1) % 4, bool(st[1])]
	relayout()
	save()

## Mirror the icon left-right, as seen on screen (a mirror also reverses the direction of any turn).
func flip_icon(orient: int, id: String) -> void:
	var st: Array = _icon_state(configs[orient], id)
	configs[orient]["icons"][id] = [(4 - int(st[0])) % 4, not bool(st[1])]
	relayout()
	save()

## Puts one orientation back to the default arrangement (positions, screen flip and icons).
func reset(orient: int) -> void:
	configs[orient] = _default_config()
	relayout()
	save()

# The menu overlay turns and mirrors the same way the icons do (one setting for both orientations)
func menu_state_text() -> String:
	return "%d°%s" % [menu_rot * 90, " FLIPPED" if menu_flip else ""]

func rotate_menu() -> void:
	menu_rot = (menu_rot + 1) % 4
	_apply_menu_orient()
	save()

func flip_menu() -> void:
	menu_rot = (4 - menu_rot) % 4
	menu_flip = not menu_flip
	_apply_menu_orient()
	save()

## The menu host is a square, so quarter turns map it exactly onto itself.
func _apply_menu_orient() -> void:
	var host = main.menu_center_host
	if host == null:
		return
	host.pivot_offset = host.size * 0.5
	host.rotation_degrees = 90.0 * menu_rot
	host.scale = Vector2(-1.0 if menu_flip else 1.0, 1.0)


# =========================================================================
# PERSISTENCE (same file as the colors and presets settings; other sections are preserved)
# =========================================================================
func save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("layout", "orient_mode", orient_mode)
	cfg.set_value("layout", "menu_rot", menu_rot)
	cfg.set_value("layout", "menu_flip", menu_flip)
	for i in range(2):
		var section: String = "grid_%d" % i
		cfg.set_value(section, "pos", configs[i]["pos"])
		cfg.set_value(section, "flip_screen", configs[i]["flip_screen"])
		cfg.set_value(section, "icons", configs[i]["icons"])
	cfg.save(SETTINGS_PATH)

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	orient_mode = clampi(int(cfg.get_value("layout", "orient_mode", -1)), -1, 2)
	if orient_mode == -1:
		# An older version saved a forced orientation as 0 / 1 plus a "chosen" flag
		var forced: bool = bool(cfg.get_value("layout", "orientation_custom", false))
		orient_mode = 1 + clampi(int(cfg.get_value("layout", "orientation", 0)), 0, 1) if forced else 0
	menu_rot = clampi(int(cfg.get_value("layout", "menu_rot", 0)), 0, 3)
	menu_flip = bool(cfg.get_value("layout", "menu_flip", false))
	for i in range(2):
		var section: String = "grid_%d" % i
		var c: Dictionary = _default_config()
		var pos = cfg.get_value(section, "pos", {})
		if _valid_positions(pos):
			c["pos"] = pos.duplicate()
		c["flip_screen"] = bool(cfg.get_value(section, "flip_screen", false))
		var icons = cfg.get_value(section, "icons", {})
		if icons is Dictionary:
			for id in icons:
				var st = icons[id]
				if _buttons.has(id) and st is Array and st.size() == 2:
					c["icons"][id] = [clampi(int(st[0]), 0, 3), bool(st[1])]
		configs[i] = c

## A saved arrangement is only trusted if every button appears once, each in its own valid cell.
func _valid_positions(p) -> bool:
	if not (p is Dictionary) or p.size() != ALL_IDS.size():
		return false
	var used: Array = []
	for id in ALL_IDS:
		if not p.has(id):
			return false
		var cell = p[id]
		if not (cell is int) or cell < 0 or cell >= COLUMNS * ROWS or used.has(cell):
			return false
		used.append(cell)
	return true
