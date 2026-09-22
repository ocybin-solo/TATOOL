extends RefCounted
## PresetsMenu.gd -- System Main Menu > PRESETS (save / load / delete animation presets)
##
## A preset is a snapshot of the animation: the formulas active in each pass (in stacking order)
## plus the current value of every uniform those formulas use. App settings (colors, layout)
## are NOT part of a preset.
##
## Files live in user://presets/, one small text file (ConfigFile format) per preset. The file name
## is a timestamp; the name the user sees is stored INSIDE the file, so any typed name is safe.
## Loading is forgiving: unknown formulas are skipped, missing values fall back to their defaults,
## and every value is clamped to its allowed range, so older presets keep working as shaders change.
##
## Controls (routed here by OptionsMenu while is_active()):
##   Presets:   D-pad up/down = move, A = select, B = back
##   Load list: A = load, D-pad left/right = delete (asks first), B = back
##   Save:      A or the keyboard's Done key = save, tap the name to type one, B = cancel

const PRESET_DIR: String = "user://presets"
const FORMAT_VERSION: int = 1
const NAME_MAX_LENGTH: int = 24
const ROOT_ROWS: Array = ["LOAD PRESET", "SAVE PRESET", "BACK"]

enum Mode { ROOT, LOAD_LIST, CONFIRM_DELETE, NAME_ENTRY }

var main         # MainManager
var owner_menu   # OptionsMenu (told when typing ends so it can re-check the layout)

var is_open: bool = false
var typing: bool = false # true while the name field has focus (the on-screen keyboard may be up)
var mode: int = Mode.ROOT
var root_cursor: int = 0
var list_cursor: int = 0
var entries: Array = []  # [{file, name, created}], newest first
var status: String = ""
var _panel_ref: Object = null
var _name_edit = null


func setup(main_manager, owner_options: Object) -> void:
	main = main_manager
	owner_menu = owner_options


# =========================================================================
# OPEN / STATE
# =========================================================================
func open() -> void:
	is_open = true
	mode = Mode.ROOT
	root_cursor = 0
	status = ""
	main._ensure_cyan_panel() # recycles the System Menu's panel and clears its rows
	_panel_ref = main.menu_overlay_panel
	redraw()

## True only while our own panel is still the one on screen (PWR/OPT closing it makes this false).
func is_active() -> bool:
	return is_open and is_instance_valid(_panel_ref) and main.menu_overlay_panel == _panel_ref

func _leave() -> void:
	_end_typing()
	is_open = false
	_panel_ref = null

func _close_everything() -> void:
	_leave()
	var cp = main.control_panel
	cp.active_state = cp.ControlState.HIDDEN
	if is_instance_valid(main.menu_overlay_panel):
		main.menu_overlay_panel.queue_free()
		main.menu_overlay_panel = null
	main.menu_center_host.visible = false


# =========================================================================
# INPUT (called by OptionsMenu, which DynamicUI talks to)
# =========================================================================
func handle_vertical(step: int) -> void:
	match mode:
		Mode.ROOT:
			root_cursor = posmod(root_cursor + step, ROOT_ROWS.size())
		Mode.LOAD_LIST:
			if entries.is_empty():
				return
			list_cursor = posmod(list_cursor + step, entries.size())
		_:
			return
	status = ""
	redraw()

## In the load list, left/right asks to delete the highlighted preset.
func handle_horizontal(_step: int) -> void:
	if mode == Mode.LOAD_LIST and not entries.is_empty():
		mode = Mode.CONFIRM_DELETE
		redraw()

func handle_a() -> void:
	match mode:
		Mode.ROOT:
			match root_cursor:
				0:
					_open_load_list()
				1:
					_open_name_entry()
				2:
					_leave()
					main.redraw_system_power_menu()
		Mode.LOAD_LIST:
			if entries.is_empty():
				return
			var entry: Dictionary = entries[list_cursor]
			if _load_preset(entry):
				var shown: String = entry["name"]
				_close_everything()
				_toast("LOADED: %s" % shown)
			else:
				redraw()
		Mode.CONFIRM_DELETE:
			var entry: Dictionary = entries[list_cursor]
			DirAccess.remove_absolute(entry["file"])
			entries = _scan()
			list_cursor = clampi(list_cursor, 0, maxi(entries.size() - 1, 0))
			status = "DELETED"
			mode = Mode.LOAD_LIST
			redraw()
		Mode.NAME_ENTRY:
			_save_current(_name_edit.text if is_instance_valid(_name_edit) else "")

## Steps back one level. Returns true when the presets menu itself is closed
## (the caller then redraws the System Main Menu).
func handle_b() -> bool:
	match mode:
		Mode.NAME_ENTRY:
			_end_typing()
			mode = Mode.ROOT
		Mode.CONFIRM_DELETE:
			mode = Mode.LOAD_LIST
		Mode.LOAD_LIST:
			mode = Mode.ROOT
		Mode.ROOT:
			_leave()
			return true
	status = ""
	redraw()
	return false


# =========================================================================
# SAVING
# =========================================================================
func _open_name_entry() -> void:
	mode = Mode.NAME_ENTRY
	status = ""
	redraw()

func _on_name_submitted(new_text: String) -> void:
	# The keyboard's Done / Enter key
	_save_current(new_text)

func _default_name() -> String:
	var highest: int = 0
	for e in _scan():
		var n: String = e["name"]
		if n.begins_with("PRESET "):
			var tail: String = n.substr(7)
			if tail.is_valid_int():
				highest = maxi(highest, int(tail))
	return "PRESET %03d" % (highest + 1)

## Two presets never share a name: the second one becomes "NAME (2)", and so on.
func _unique_name(wanted: String) -> String:
	var taken: Array = []
	for e in _scan():
		taken.append(e["name"])
	if not taken.has(wanted):
		return wanted
	var n: int = 2
	while taken.has("%s (%d)" % [wanted, n]):
		n += 1
	return "%s (%d)" % [wanted, n]

func _new_path() -> String:
	var dt: Dictionary = Time.get_datetime_dict_from_system()
	var base: String = "preset_%04d%02d%02d_%02d%02d%02d" % [dt["year"], dt["month"], dt["day"], dt["hour"], dt["minute"], dt["second"]]
	var path: String = "%s/%s.cfg" % [PRESET_DIR, base]
	var n: int = 2
	while FileAccess.file_exists(path):
		path = "%s/%s_%d.cfg" % [PRESET_DIR, base, n]
		n += 1
	return path

func _save_current(raw_name: String) -> void:
	var preset_name: String = raw_name.strip_edges().left(NAME_MAX_LENGTH)
	if preset_name == "":
		preset_name = _default_name()
	preset_name = _unique_name(preset_name)

	var cfg := ConfigFile.new()
	cfg.set_value("preset", "version", FORMAT_VERSION)
	cfg.set_value("preset", "name", preset_name)
	cfg.set_value("preset", "created", Time.get_datetime_string_from_system())
	for p in range(3):
		var section: String = "pass_%d" % p
		cfg.set_value(section, "stack", main.pass_stack[p].duplicate())
		# Only the uniforms of formulas that are active right now (plus the pass globals)
		for rec in main.pass_records[p]:
			var u_name: String = rec["name"]
			cfg.set_value(section, u_name, main.pass_values[p].get(u_name, rec["default"]))

	DirAccess.make_dir_recursive_absolute(PRESET_DIR)
	var err: int = cfg.save(_new_path())
	_end_typing()
	mode = Mode.ROOT
	root_cursor = 0
	status = ("SAVED: %s" % preset_name) if err == OK else "COULD NOT SAVE (ERROR %d)" % err
	redraw()


# =========================================================================
# LOADING
# =========================================================================
func _open_load_list() -> void:
	entries = _scan()
	list_cursor = 0
	mode = Mode.LOAD_LIST
	status = ""
	redraw()

func _scan() -> Array:
	var out: Array = []
	if not DirAccess.dir_exists_absolute(PRESET_DIR):
		return out
	for f in DirAccess.get_files_at(PRESET_DIR):
		if not f.ends_with(".cfg"):
			continue
		var path: String = "%s/%s" % [PRESET_DIR, f]
		var cfg := ConfigFile.new()
		if cfg.load(path) != OK or not cfg.has_section("preset"):
			continue
		out.append({
			"file": path,
			"name": str(cfg.get_value("preset", "name", f.get_basename())),
			"created": str(cfg.get_value("preset", "created", "")),
		})
	out.sort_custom(func(a, b): return a["created"] > b["created"])
	return out

func _load_preset(entry: Dictionary) -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(entry["file"]) != OK:
		status = "COULD NOT READ THAT FILE"
		return false
	var lib = main.library
	var old_stacks: Array = main.pass_stack.duplicate(true)

	# 1) Which formulas are active, and the raw saved values
	for p in range(3):
		var section: String = "pass_%d" % p
		var ids: Array = []
		var saved = cfg.get_value(section, "stack", [])
		if saved is Array:
			for id in saved:
				if lib.recipes.has(id) and int(lib.recipes[id]["pass"]) == p and not ids.has(id):
					ids.append(id) # unknown or renamed formulas are simply skipped
		if ids.size() > 1:
			for id in ids.duplicate():
				if not lib.is_stackable(id):
					ids = [id] # single-select formulas cannot be stacked
					break
		if p == 0 and ids.is_empty():
			ids = main.pass_stack[0].duplicate() # Pass 1 always needs a pattern
		main.pass_stack[p] = ids

		main.pass_values[p].clear() # cleared in place so the menu's link to it stays valid
		if cfg.has_section(section):
			for key in cfg.get_section_keys(section):
				if key != "stack":
					main.pass_values[p][key] = cfg.get_value(section, key)

	# 2) Check every value against what the assembled shader really expects, then rebuild
	for p in range(3):
		var built: Dictionary = lib.assemble_pass(p, main.pass_stack[p])
		_sanitize(built["uniforms"], main.pass_values[p])
		if old_stacks[p] == main.pass_stack[p]:
			# Same formulas as before: only the values changed, so skip the (slow) shader rebuild
			lib.apply_values(main._pass_material(p), main.pass_records[p], main.pass_values[p])
		else:
			main.rebuild_pass(p)
	return true

func _sanitize(records: Array, values: Dictionary) -> void:
	var lib = main.library
	for rec in records:
		var u_name: String = rec["name"]
		var u_type: String = rec["type"]
		var v = values.get(u_name, null)
		var valid: bool = false
		match u_type:
			"float":
				valid = typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT
			"vec2":
				valid = typeof(v) == TYPE_VECTOR2
			"vec4":
				valid = typeof(v) == TYPE_COLOR
		if not valid:
			values[u_name] = rec["default"] # missing or unreadable: back to the default
			continue
		if u_type == "float":
			values[u_name] = clampf(float(v), rec["min"], rec["max"])
		else:
			for i in range(rec["channels"].size()):
				var c: float = lib.get_component(v, u_type, i)
				v = lib.set_component(v, u_type, i, clampf(c, rec["min"], rec["max"]))
			values[u_name] = v


# =========================================================================
# TYPING (system keyboard)
# =========================================================================
func _on_typing_started() -> void:
	typing = true

func _on_typing_stopped() -> void:
	_end_typing()

## Typing is over (focus lost, saved, cancelled or menu closed). The field itself is kept until the next
## redraw so its text can still be read when the A button (which steals focus) is pressed.
func _end_typing() -> void:
	var was_typing: bool = typing
	typing = false
	if is_instance_valid(_name_edit):
		_name_edit.release_focus()
	if was_typing and owner_menu != null:
		owner_menu.notify_typing_done() # the keyboard may have resized the window; re-check the layout


# =========================================================================
# DRAWING (uses MainManager's menu helpers so it looks like the other menus)
# =========================================================================
func redraw() -> void:
	if not is_instance_valid(main.menu_list_box):
		return
	for child in main.menu_list_box.get_children():
		child.queue_free()
	_name_edit = null
	match mode:
		Mode.ROOT:
			_draw_root()
		Mode.LOAD_LIST:
			_draw_load_list()
		Mode.CONFIRM_DELETE:
			_draw_confirm_delete()
		Mode.NAME_ENTRY:
			_draw_name_entry()

func _add_label(text: String, color: Color) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", color)
	main.menu_list_box.add_child(lbl)

func _add_status() -> void:
	if status == "":
		return
	if status.begins_with("COULD"):
		_add_label(" ⚠ %s " % status, Color.ORANGE)
	else:
		_add_label(" ✔ %s " % status, Color.CHARTREUSE)

func _draw_root() -> void:
	_add_label(" 🗂 PRESETS ", Color.RED)
	for i in range(ROOT_ROWS.size()):
		main._add_menu_row(ROOT_ROWS[i], i == root_cursor)
	_add_status()

func _draw_load_list() -> void:
	_add_label(" 📂 LOAD PRESET ", Color.CYAN)
	if entries.is_empty():
		_add_label("    [ NO SAVED PRESETS YET ]    ", Color.DARK_GRAY)
		_add_status()
		return

	var start: int = main._window_start(entries.size(), list_cursor)
	var stop: int = mini(start + main.MENU_PAGE_ROWS, entries.size())
	var scrolling: bool = entries.size() > main.MENU_PAGE_ROWS
	if scrolling: main._add_scroll_hint(start > 0, "▲")
	for i in range(start, stop):
		main._add_menu_row(String(entries[i]["name"]), i == list_cursor)
	if scrolling: main._add_scroll_hint(stop < entries.size(), "▼")
	_add_label(" ✔️= LOAD    ◄ ► DELETE ", Color.DIM_GRAY)
	_add_status()

func _draw_confirm_delete() -> void:
	_add_label(" DELETE THIS PRESET? ", Color.ORANGE)
	_add_label(String(entries[list_cursor]["name"]), Color.WHITE)
	_add_label(" ✔️ = YES, DELETE    ❌ = NO ", Color.YELLOW)

func _draw_name_entry() -> void:
	_add_label(" 💾 SAVE PRESET ", Color.CHARTREUSE)
	_add_label(" NAME (TAP THE NAME TO CHANGE IT) ", Color.DIM_GRAY)

	_name_edit = LineEdit.new()
	_name_edit.text = _default_name()
	_name_edit.max_length = NAME_MAX_LENGTH
	_name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_edit.custom_minimum_size = Vector2(300, 52)
	_name_edit.select_all_on_focus = true # typing replaces the suggested name
	_name_edit.text_submitted.connect(_on_name_submitted)
	_name_edit.focus_entered.connect(_on_typing_started)
	_name_edit.focus_exited.connect(_on_typing_stopped)
	main.menu_list_box.add_child(_name_edit)

	_add_label(" ✔️ OR KEYBOARD DONE = SAVE ", Color.YELLOW)
	_add_label(" ❌ = CANCEL ", Color.DARK_GRAY)

## A short message that outlives the menu (used after loading a preset).
func _toast(text: String) -> void:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.05, 0.02, 0.92)
	style.set_border_width_all(2)
	style.border_color = Color(0.5, 1.0, 0.0, 0.9)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", Color.CHARTREUSE)
	panel.add_child(lbl)
	main.menu_center_host.add_child(panel)
	main.menu_center_host.visible = true
	main.get_tree().create_timer(1.8).timeout.connect(_end_toast.bind(panel))

func _end_toast(panel: Node) -> void:
	if is_instance_valid(panel):
		panel.queue_free()
	var cp = main.control_panel
	if cp.active_state == cp.ControlState.HIDDEN:
		main.menu_center_host.visible = false
