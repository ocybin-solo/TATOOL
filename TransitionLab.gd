extends Node
## TransitionLab.gd -- "Screensaver Developer" mode: a test bench for transition effects
##
## A transition hides a cut between two presets behind a distortion of the final image:
##   no effect  ->  maximum effect  ->  no effect
## At the peak the next preset is swapped in (the "snap"), so the viewer never sees the cut.
##
## Developer mode (main menu > SCREENSAVER DEV, leave the menu with B):
##   D-pad left / right   transition to the previous / next saved preset (oldest first, wraps around)
##   D-pad up / down      cycle the transition time 5 s / 10 s / 20 s
##   B                    abort a running transition: the next preset is applied at once
##   A                    (saving screensaver presets comes in the next update)
##   OPT                  the transition lab menu: pick formulas (several can be active at once), then
##                        pick a uniform and dial in its MAX value (its peak). Uniforms with a rest value
##                        move from rest to your value and back; the others just keep the value you set.
##
## TRANSITION FORMULAS use the same tag comments as the shader recipes, plus one extra tag:
##   uniform float u_strength = 8.0; // @label Twist Strength | @min -40 | @max 40 | @sens 0.5 | @rest 0
##   @rest   marks a FLOAT uniform as animated and gives its value when no transition is running.
##           The formula MUST look like "no effect" at its rest values. The default (8.0) is the peak.
##   No @rest: a fixed setting (any type) that keeps the value you dial in.
## Formula kinds:  "warp"   vec2 fx_<id>(vec2 uv)                   moves where the image is sampled
##                 "color"  vec4 fx_<id>(vec4 c, vec2 uv)          changes the sampled color
## Use screen-relative units (fractions of the screen), so a setting behaves the same on any device.
## Formula ids and uniform names should stay stable once saved styles exist.

const TIMES: Array = [5.0, 10.0, 20.0]
const HOLD_FRACTION: float = 0.08 # share of the transition spent holding the peak (covers the snap hitch)
const SENS_DEFAULT_INDEX: int = 2

enum M { FORMULAS, UNIFORMS, CHANNELS, TWEAK }

var main
var owner_menu

var dev_mode: bool = false
var running: bool = false
var time_idx: int = 1

# Formula registry and what is currently active (in stacking order)
var formulas: Dictionary = {}     # id -> {id, name, kind, source}
var active: Array = []
var peak_values: Dictionary = {}  # final uniform name -> value (the peak for animated ones)
var _records: Array = []          # uniform records of the assembled effect shader
var _material: ShaderMaterial = null

# The effect layer: a picture of the final display image, on top of it, only visible during a transition
var _screen: TextureRect
var _host
var _indicator: Label

# Transition state
var _t0_msec: int = 0
var _snapped: bool = false
var _target_entry: Dictionary = {}
var _current_file: String = ""
var _playlist_pos: int = -1
var _playlist_size: int = 0
var _message: String = ""
var _snapshot_stack: Array = []
var _snapshot_values: Array = []
var _original_opt: Callable = Callable()

# Lab menu
var menu_open: bool = false
var _panel_ref: Object = null
var mode: int = M.FORMULAS
var _cursor_formula: int = 0
var _cursor_uniform: int = 1
var _formula_id: String = ""
var _uniform_idx: int = 0
var _channel_idx: int = 0
var _tweak_row: int = 0
var _sens_idx: int = SENS_DEFAULT_INDEX
var _sens_memory: Dictionary = {}

var _re_uniform: RegEx


# =========================================================================
# SETUP
# =========================================================================
func setup(main_manager, owner: Object) -> void:
	main = main_manager
	owner_menu = owner
	_re_uniform = RegEx.new()
	# groups: 1 type, 2 name, 3 hint, 4 default literal, 5 comment tags
	_re_uniform.compile("^\\s*uniform\\s+(float|vec2|vec4)\\s+(\\w+)\\s*(?::\\s*([^=;]+?))?\\s*=\\s*([^;]+);\\s*(?://(.*))?$")
	_register_formulas()
	set_process(false)

	_host = main.canvas_container.get_parent()
	_screen = TextureRect.new()
	_screen.texture = main.pass3_viewport.get_texture()
	_screen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_screen.stretch_mode = TextureRect.STRETCH_SCALE
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.visible = false
	_host.add_child(_screen)
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_host.move_child(_screen, main.canvas_container.get_index() + 1) # above the display, below the menus

	_indicator = Label.new()
	_indicator.position = Vector2(10, 8)
	_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_indicator.z_index = 3
	_indicator.add_theme_font_size_override("font_size", 20)
	_indicator.add_theme_color_override("font_color", Color(0.7, 1.0, 0.3))
	_indicator.add_theme_color_override("font_outline_color", Color.BLACK)
	_indicator.add_theme_constant_override("outline_size", 6)
	_indicator.visible = false
	_host.add_child(_indicator)


# =========================================================================
# DEVELOPER MODE ON / OFF
# =========================================================================
func toggle_dev_mode() -> void:
	dev_mode = not dev_mode
	if dev_mode:
		_snapshot_look()
		_original_opt = Callable(main, "_on_select_pass_button_pressed")
		if main.btn_select_pass.pressed.is_connected(_original_opt):
			main.btn_select_pass.pressed.disconnect(_original_opt)
		main.btn_select_pass.pressed.connect(_on_opt_pressed)
		_current_file = ""
		_playlist_pos = -1
		_message = ""
		_indicator.visible = true
		_update_indicator()
	else:
		if running:
			_finish()
		if menu_open:
			_close_menu()
		if main.btn_select_pass.pressed.is_connected(_on_opt_pressed):
			main.btn_select_pass.pressed.disconnect(_on_opt_pressed)
		if _original_opt.is_valid() and not main.btn_select_pass.pressed.is_connected(_original_opt):
			main.btn_select_pass.pressed.connect(_original_opt)
		_indicator.visible = false
		_restore_look()

## The look on screen when the mode was switched on is put back when it is switched off.
func _snapshot_look() -> void:
	_snapshot_stack = main.pass_stack.duplicate(true)
	_snapshot_values = main.pass_values.duplicate(true)

func _restore_look() -> void:
	if _snapshot_stack.is_empty():
		return
	for p in range(3):
		main.pass_stack[p] = _snapshot_stack[p].duplicate()
		main.pass_values[p].clear() # in place, so the menu's link to it stays valid
		main.pass_values[p].merge(_snapshot_values[p])
		main.rebuild_pass(p)

func _update_indicator() -> void:
	var text: String = "DEV  %d S  ·  %d FX" % [int(TIMES[time_idx]), active.size()]
	if _playlist_size > 0 and _playlist_pos >= 0:
		text += "  ·  %d/%d" % [_playlist_pos + 1, _playlist_size]
	if _message != "":
		text += "\n" + _message
	_indicator.text = text

func _say(text: String) -> void:
	_message = text
	_update_indicator()
	get_tree().create_timer(3.0).timeout.connect(_clear_message.bind(text))

func _clear_message(text: String) -> void:
	if _message == text:
		_message = ""
		_update_indicator()


# =========================================================================
# INPUT WITH THE MENUS CLOSED (DynamicUI sends it here while developer mode is on)
# =========================================================================
func dev_input(action: String) -> bool:
	if not dev_mode or menu_active():
		return false
	match action:
		"left":
			start_transition(-1)
		"right":
			start_transition(1)
		"up":
			_cycle_time(1)
		"down":
			_cycle_time(-1)
		"b":
			if running:
				_abort()
		"a":
			_say("SAVING COMES IN THE NEXT UPDATE")
	return true

func _cycle_time(step: int) -> void:
	time_idx = posmod(time_idx + step, TIMES.size())
	_say("TRANSITION TIME: %d S%s" % [int(TIMES[time_idx]), " (NEXT TRANSITION)" if running else ""])


# =========================================================================
# THE TRANSITION
# =========================================================================
func _playlist() -> Array:
	var entries: Array = owner_menu.presets._scan()
	entries.sort_custom(func(a, b): return a["created"] < b["created"]) # oldest first: new presets join the end
	return entries

func start_transition(direction: int) -> void:
	if running:
		return
	if _material == null:
		_say("NO TRANSITION FORMULA ACTIVE: PRESS OPT")
		return
	var entries: Array = _playlist()
	_playlist_size = entries.size()
	if entries.size() < 2:
		_say("NEED AT LEAST 2 SAVED PRESETS")
		return
	var pos: int = -1
	for i in range(entries.size()):
		if entries[i]["file"] == _current_file:
			pos = i
	var target: int
	if pos == -1:
		target = 0 if direction > 0 else entries.size() - 1
	else:
		target = posmod(pos + direction, entries.size())
	_target_entry = entries[target]
	_playlist_pos = target
	_snapped = false
	_t0_msec = Time.get_ticks_msec()
	running = true
	_screen.visible = true
	_apply_rest_values()
	set_process(true)
	_update_indicator()

func _process(_delta: float) -> void:
	if not running:
		set_process(false)
		return
	var duration: float = TIMES[time_idx]
	var p: float = float(Time.get_ticks_msec() - _t0_msec) / (duration * 1000.0) # by the clock, so a hitch never skips ahead
	if p >= 1.0:
		_finish()
		return
	if not _snapped and p >= 0.5:
		_snap()
	var e: float = _envelope(p)
	for rec in _records:
		if rec["animated"]:
			_material.set_shader_parameter(rec["name"], lerpf(float(rec["rest"]), float(peak_values[rec["name"]]), e))
	_material.set_shader_parameter("u_time", float(Time.get_ticks_msec()) / 1000.0)

## 0 -> 1 -> 0 with a short hold at the top.
func _envelope(p: float) -> float:
	var half_hold: float = HOLD_FRACTION * 0.5
	var rise_end: float = 0.5 - half_hold
	var fall_start: float = 0.5 + half_hold
	if p < rise_end:
		return smoothstep(0.0, 1.0, p / rise_end)
	if p <= fall_start:
		return 1.0
	return 1.0 - smoothstep(0.0, 1.0, (p - fall_start) / (1.0 - fall_start))

## Swap in the next preset while the image is at its most distorted. The time it takes is shown on screen.
func _snap() -> void:
	_snapped = true
	var before: int = Time.get_ticks_usec()
	var ok: bool = owner_menu.presets._load_preset(_target_entry)
	var took_ms: int = int(round(float(Time.get_ticks_usec() - before) / 1000.0))
	if ok:
		_current_file = _target_entry["file"]
		_say("%s   (SNAP %d MS)" % [String(_target_entry["name"]), took_ms])
	else:
		_say("COULD NOT LOAD %s" % String(_target_entry["name"]))

## B: skip to the end. If the snap has not happened yet, the next preset is applied right now.
func _abort() -> void:
	if not _snapped:
		_snap()
	_finish()

func _finish() -> void:
	running = false
	_screen.visible = false
	_apply_rest_values()
	set_process(false)
	_update_indicator()


# =========================================================================
# THE EFFECT SHADER (built from the active formulas)
# =========================================================================
func _rebuild_effect() -> void:
	if active.is_empty():
		_material = null
		_records = []
		_screen.material = null
		_update_indicator()
		return
	var built: Dictionary = _assemble()
	var effect_shader := Shader.new()
	effect_shader.code = built["code"]
	_material = ShaderMaterial.new()
	_material.shader = effect_shader
	_records = built["records"]
	for rec in _records:
		if not peak_values.has(rec["name"]):
			peak_values[rec["name"]] = rec["default"]
	_apply_rest_values()
	_screen.material = _material
	_update_indicator()

## Everything at rest: animated uniforms at their rest value, fixed ones at the value that was dialed in.
func _apply_rest_values() -> void:
	if _material == null:
		return
	for rec in _records:
		if rec["animated"]:
			_material.set_shader_parameter(rec["name"], float(rec["rest"]))
		else:
			_material.set_shader_parameter(rec["name"], peak_values[rec["name"]])

func _assemble() -> Dictionary:
	var decls: PackedStringArray = PackedStringArray()
	var funcs: PackedStringArray = PackedStringArray()
	var records: Array = []
	var warp_calls: String = ""
	var color_calls: String = ""
	for id in active:
		var f: Dictionary = formulas[id]
		var renames: Dictionary = {}
		var body: PackedStringArray = PackedStringArray()
		for line in String(f["source"]).split("\n"):
			var rec: Dictionary = _parse_line(line, id)
			if rec.is_empty():
				body.append(line)
				continue
			# Prefix with the formula id so stacked formulas never share a uniform name
			rec["name"] = "u_%s_%s" % [id, String(rec["base"]).trim_prefix("u_")]
			renames[rec["base"]] = rec["name"]
			records.append(rec)
			decls.append(_decl_line(rec))
		var text: String = "\n".join(body)
		for base in renames:
			text = _rename_word(text, base, renames[base])
		funcs.append(text)
		if f["kind"] == "warp":
			warp_calls += "\tuv = fx_%s(uv);\n" % id
		else:
			color_calls += "\tc = fx_%s(c, UV);\n" % id
	var code: String = "shader_type canvas_item;\nuniform float u_time;\n"
	code += "\n".join(decls) + "\n\n" + "\n".join(funcs) + "\n\n"
	code += "vec2 tatool_mirror(vec2 x) {\n\treturn abs(mod(x + 1.0, 2.0) - 1.0);\n}\n\n"
	code += "void fragment() {\n\tvec2 uv = UV;\n" + warp_calls
	code += "\tvec4 c = texture(TEXTURE, tatool_mirror(uv));\n" + color_calls + "\tCOLOR = c;\n}\n"
	return {"code": code, "records": records}

func _rename_word(text: String, from_name: String, to_name: String) -> String:
	var re: RegEx = RegEx.new()
	re.compile("\\b%s\\b" % from_name)
	return re.sub(text, to_name, true)

func _decl_line(rec: Dictionary) -> String:
	var hint: String = ""
	if rec["hint"] != "":
		hint = " : %s" % rec["hint"]
	var literal: String = rec["literal"]
	if rec["animated"]:
		literal = "%.6f" % float(rec["rest"]) # the shader's own default is "no effect"
	return "uniform %s %s%s = %s;" % [rec["type"], rec["name"], hint, literal]

func _parse_line(line: String, formula_id: String) -> Dictionary:
	var m: RegExMatch = _re_uniform.search(line)
	if m == null:
		return {}
	var type: String = m.get_string(1)
	var tags: Dictionary = _parse_tags(m.get_string(5))
	var literal: String = m.get_string(4).strip_edges()
	var base: String = m.get_string(2)
	var mn: float = float(tags["min"]) if tags.has("min") else -INF
	var mx: float = float(tags["max"]) if tags.has("max") else INF
	var sens: float = 0.01
	if tags.has("sens"):
		sens = float(tags["sens"])
	elif not is_inf(mn) and not is_inf(mx):
		sens = (mx - mn) / 100.0
	var channels: Array = ["VALUE"]
	if type == "vec2":
		channels = ["X", "Y"]
	elif type == "vec4":
		channels = ["R", "G", "B", "A"]
	var animated: bool = tags.has("rest") and type == "float"
	return {
		"formula": formula_id,
		"base": base,
		"name": base,
		"type": type,
		"hint": m.get_string(3).strip_edges(),
		"literal": literal,
		"default": _parse_literal(type, literal), # the peak (animated) or the fixed value
		"label": str(tags.get("label", base.trim_prefix("u_").replace("_", " ").capitalize())),
		"min": mn,
		"max": mx,
		"sens": sens,
		"channels": channels,
		"animated": animated,
		"rest": float(tags["rest"]) if animated else 0.0,
	}

func _parse_tags(comment: String) -> Dictionary:
	var tags: Dictionary = {}
	for part in comment.split("|"):
		var p: String = part.strip_edges()
		if not p.begins_with("@"):
			continue
		p = p.substr(1)
		var sp: int = p.find(" ")
		if sp == -1:
			tags[p] = true
		else:
			tags[p.substr(0, sp)] = p.substr(sp + 1).strip_edges()
	return tags

func _parse_literal(type: String, text: String) -> Variant:
	var t: String = text.strip_edges()
	if type == "float":
		return float(t)
	var nums: Array = []
	var open: int = t.find("(")
	var close: int = t.rfind(")")
	if open != -1 and close > open:
		for s in t.substr(open + 1, close - open - 1).split(","):
			nums.append(float(s.strip_edges()))
	if type == "vec2":
		if nums.size() == 1:
			nums.append(nums[0])
		while nums.size() < 2:
			nums.append(0.0)
		return Vector2(nums[0], nums[1])
	if nums.size() == 1:
		return Color(nums[0], nums[0], nums[0], nums[0])
	while nums.size() < 4:
		nums.append(0.0 if nums.size() < 3 else 1.0)
	return Color(nums[0], nums[1], nums[2], nums[3])

func _get_comp(value: Variant, type: String, idx: int) -> float:
	match type:
		"vec2":
			var v2: Vector2 = value
			return v2[idx]
		"vec4":
			var c4: Color = value
			return c4[idx]
	return float(value)

func _set_comp(value: Variant, type: String, idx: int, v: float) -> Variant:
	match type:
		"vec2":
			var v2: Vector2 = value
			v2[idx] = v
			return v2
		"vec4":
			var c4: Color = value
			c4[idx] = v
			return c4
	return v


# =========================================================================
# THE LAB MENU (OPT while developer mode is on): formulas > uniforms > (channels) > tweak
# =========================================================================
func _on_opt_pressed() -> void:
	var cp = main.control_panel
	if menu_active():
		_close_menu()
		return
	if cp.active_state != cp.ControlState.HIDDEN:
		return # another menu is open
	if running:
		_say("WAIT FOR THE TRANSITION (B TO ABORT)")
		return
	_open_menu()

func menu_active() -> bool:
	return menu_open and is_instance_valid(_panel_ref) and main.menu_overlay_panel == _panel_ref

func _open_menu() -> void:
	menu_open = true
	mode = M.FORMULAS
	_cursor_formula = 0
	var cp = main.control_panel
	cp.active_state = cp.ControlState.SYSTEM_MENU # routes the D-pad and A/B to the options menu, which forwards them here
	main._ensure_cyan_panel()
	_panel_ref = main.menu_overlay_panel
	redraw()

func _close_menu() -> void:
	menu_open = false
	_panel_ref = null
	var cp = main.control_panel
	cp.active_state = cp.ControlState.HIDDEN
	if is_instance_valid(main.menu_overlay_panel):
		main.menu_overlay_panel.queue_free()
		main.menu_overlay_panel = null
	main.menu_center_host.visible = false
	_update_indicator()

func _formula_ids() -> Array:
	return formulas.keys()

func _uniforms_of(id: String) -> Array:
	var out: Array = []
	for rec in _records:
		if rec["formula"] == id:
			out.append(rec)
	return out

func handle_vertical(step: int) -> void:
	match mode:
		M.FORMULAS:
			_cursor_formula = posmod(_cursor_formula + step, _formula_ids().size() + 1)
		M.UNIFORMS:
			_cursor_uniform = posmod(_cursor_uniform + step, _uniforms_of(_formula_id).size() + 1)
		M.CHANNELS:
			_channel_idx = posmod(_channel_idx + step, _uniforms_of(_formula_id)[_uniform_idx]["channels"].size())
		M.TWEAK:
			_tweak_row = posmod(_tweak_row + step, 2)
	redraw()

func handle_horizontal(step: int) -> void:
	if mode != M.TWEAK:
		return
	var rec: Dictionary = _uniforms_of(_formula_id)[_uniform_idx]
	var ladder: Array = _ladder(rec)
	if _tweak_row == 0:
		var current: Variant = peak_values[rec["name"]]
		var comp: float = _get_comp(current, rec["type"], _channel_idx) + float(step) * float(ladder[_sens_idx])
		comp = snappedf(clampf(comp, rec["min"], rec["max"]), 0.000001)
		peak_values[rec["name"]] = _set_comp(current, rec["type"], _channel_idx, comp)
		if _material != null and not rec["animated"]:
			_material.set_shader_parameter(rec["name"], peak_values[rec["name"]])
	else:
		_sens_idx = clampi(_sens_idx + step, 0, ladder.size() - 1)
		_sens_memory[rec["name"]] = _sens_idx
	redraw()

func handle_a() -> void:
	match mode:
		M.FORMULAS:
			var ids: Array = _formula_ids()
			if _cursor_formula == ids.size():
				# [ REMOVE ALL FORMULAS ]
				active.clear()
				peak_values.clear()
				_rebuild_effect()
			else:
				_formula_id = ids[_cursor_formula]
				if not active.has(_formula_id):
					active.append(_formula_id)
					_rebuild_effect()
				mode = M.UNIFORMS
				_cursor_uniform = 1
		M.UNIFORMS:
			if _cursor_uniform == 0:
				# [ REMOVE THIS FORMULA ]
				active.erase(_formula_id)
				for rec in _uniforms_of(_formula_id):
					peak_values.erase(rec["name"])
				_rebuild_effect()
				mode = M.FORMULAS
			else:
				_uniform_idx = _cursor_uniform - 1
				_channel_idx = 0
				var rec: Dictionary = _uniforms_of(_formula_id)[_uniform_idx]
				if rec["channels"].size() == 1:
					_enter_tweak(rec)
				else:
					mode = M.CHANNELS
		M.CHANNELS:
			_enter_tweak(_uniforms_of(_formula_id)[_uniform_idx])
		M.TWEAK:
			return
	redraw()

func _enter_tweak(rec: Dictionary) -> void:
	_tweak_row = 0
	_sens_idx = clampi(int(_sens_memory.get(rec["name"], SENS_DEFAULT_INDEX)), 0, 4)
	mode = M.TWEAK

## Returns true when the lab menu is closed (nothing for the caller to redraw: it closes itself).
func handle_b() -> bool:
	match mode:
		M.TWEAK:
			var rec: Dictionary = _uniforms_of(_formula_id)[_uniform_idx]
			mode = M.UNIFORMS if rec["channels"].size() == 1 else M.CHANNELS
		M.CHANNELS:
			mode = M.UNIFORMS
		M.UNIFORMS:
			mode = M.FORMULAS
		M.FORMULAS:
			_close_menu()
			return false
	redraw()
	return false

func _ladder(rec: Dictionary) -> Array:
	var s: float = rec["sens"]
	return [s * 0.1, s * 0.5, s, s * 5.0, s * 10.0]


# =========================================================================
# DRAWING (uses MainManager's menu helpers so it looks like the other menus)
# =========================================================================
func redraw() -> void:
	if not is_instance_valid(main.menu_list_box):
		return
	for child in main.menu_list_box.get_children():
		child.queue_free()
	match mode:
		M.FORMULAS:
			_draw_formulas()
		M.UNIFORMS:
			_draw_uniforms()
		M.CHANNELS:
			_draw_channels()
		M.TWEAK:
			_draw_tweak()

func _add_label(text: String, color: Color) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", color)
	main.menu_list_box.add_child(lbl)

func _draw_window(rows: Array, cursor: int, gold_row: int) -> void:
	var start: int = main._window_start(rows.size(), cursor)
	var stop: int = mini(start + main.MENU_PAGE_ROWS, rows.size())
	var scrolling: bool = rows.size() > main.MENU_PAGE_ROWS
	if scrolling: main._add_scroll_hint(start > 0, "▲")
	for i in range(start, stop):
		var gold: bool = i == gold_row
		main._add_menu_row(rows[i], i == cursor, Color.WHITE if gold else Color.YELLOW, Color.LIGHT_GOLDENROD if gold else Color.DARK_GRAY)
	if scrolling: main._add_scroll_hint(stop < rows.size(), "▼")

func _draw_formulas() -> void:
	_add_label(" 🌀 TRANSITION FORMULAS ", Color.CHARTREUSE)
	var rows: Array = []
	for id in _formula_ids():
		rows.append(("● " if active.has(id) else "○ ") + String(formulas[id]["name"]))
	rows.append("[ REMOVE ALL FORMULAS ]")
	_draw_window(rows, _cursor_formula, rows.size() - 1) # the last row removes everything

func _draw_uniforms() -> void:
	_add_label(" 🌀 %s " % String(formulas[_formula_id]["name"]), Color.CYAN)
	var rows: Array = ["[ REMOVE THIS FORMULA ]"]
	for rec in _uniforms_of(_formula_id):
		var shown: String = String(rec["label"]).to_upper()
		if rec["type"] == "float":
			shown += "  [%s]" % main._fmt(float(peak_values[rec["name"]]))
		if rec["animated"]:
			shown += " ▲"
		rows.append(shown)
	_draw_window(rows, _cursor_uniform, 0) # row 0 removes the formula
	_add_label(" ▲ = MOVES DURING A TRANSITION ", Color.DIM_GRAY)

func _draw_channels() -> void:
	var rec: Dictionary = _uniforms_of(_formula_id)[_uniform_idx]
	_add_label(" %s: SELECT PARAMETER " % String(rec["label"]).to_upper(), Color.MAGENTA)
	var current: Variant = peak_values[rec["name"]]
	var names: Array = rec["channels"]
	for i in range(names.size()):
		main._add_menu_row("%s   [ %s ]" % [names[i], main._fmt(_get_comp(current, rec["type"], i))], i == _channel_idx)

func _draw_tweak() -> void:
	var rec: Dictionary = _uniforms_of(_formula_id)[_uniform_idx]
	var names: Array = rec["channels"]
	var value: float = _get_comp(peak_values[rec["name"]], rec["type"], _channel_idx)
	var ladder: Array = _ladder(rec)
	var title: String = String(rec["label"]).to_upper()
	if names.size() > 1:
		title += "  ·  " + String(names[_channel_idx])
	_add_label(" +═ TRANSITION TWEAK ═+ ", Color.ORANGE)
	_add_label(" ║ NAME: %s " % title, Color.WHITE)
	var value_word: String = "PEAK " if rec["animated"] else "VALUE"
	if _tweak_row == 0:
		_add_label(" ▶ ║ %s: ◄ [ %s ] ► " % [value_word, main._fmt(value)], Color.YELLOW)
		_add_label("    ║ SENS :   [ %s ]   " % main._fmt(float(ladder[_sens_idx])), Color.DARK_GRAY)
	else:
		_add_label("    ║ %s:   [ %s ]   " % [value_word, main._fmt(value)], Color.DARK_GRAY)
		_add_label(" ▶ ║ SENS : ◄ [ %s ] ► " % main._fmt(float(ladder[_sens_idx])), Color.YELLOW)
	_add_label(" ║                            ║ ", Color.DARK_GRAY)
	if rec["animated"]:
		_add_label(" ║ REST VAL : [ %s ]   ║ " % main._fmt(float(rec["rest"])), Color.DIM_GRAY)
	else:
		var d: float = _get_comp(rec["default"], rec["type"], _channel_idx)
		_add_label(" ║ DEFAULT VAL : [ %s ]   ║ " % main._fmt(d), Color.DIM_GRAY)
	_add_label(" ║ RECOMMENDED SENS: [ %s ]   ║ " % main._fmt(float(rec["sens"])), Color.DIM_GRAY)
	_add_label(" +════════════════════════════+ ", Color.ORANGE)


# =========================================================================
# THE STARTER FORMULAS
# =========================================================================
func _register_formulas() -> void:
	_add_formula("swirl", "SWIRL", "warp", SRC_SWIRL)
	_add_formula("fisheye", "FISHEYE", "warp", SRC_FISHEYE)
	_add_formula("ripple", "RIPPLE", "warp", SRC_RIPPLE)
	_add_formula("pixelate", "PIXELATE", "warp", SRC_PIXELATE)
	_add_formula("zoom", "ZOOM", "warp", SRC_ZOOM)
	_add_formula("flash", "COLOR DIP", "color", SRC_FLASH)

func _add_formula(id: String, display_name: String, kind: String, source: String) -> void:
	formulas[id] = {"id": id, "name": display_name, "kind": kind, "source": source}

const SRC_SWIRL: String = """
uniform float u_strength = 8.0; // @label Twist Strength | @min -40 | @max 40 | @sens 0.5 | @rest 0
uniform float u_radius = 0.7; // @label Radius | @min 0.1 | @max 1.5 | @sens 0.02
uniform vec2 u_center = vec2(0.5, 0.5); // @label Center | @min 0 | @max 1 | @sens 0.01

vec2 fx_swirl(vec2 uv) {
	vec2 p = uv - u_center;
	float falloff = 1.0 - smoothstep(0.0, u_radius, length(p));
	float ang = u_strength * falloff * falloff;
	float s = sin(ang);
	float k = cos(ang);
	return vec2(k * p.x - s * p.y, s * p.x + k * p.y) + u_center;
}
"""

const SRC_FISHEYE: String = """
uniform float u_bulge = 2.5; // @label Bulge Strength | @min -0.4 | @max 6 | @sens 0.1 | @rest 0
uniform vec2 u_center = vec2(0.5, 0.5); // @label Center | @min 0 | @max 1 | @sens 0.01

vec2 fx_fisheye(vec2 uv) {
	vec2 p = uv - u_center;
	float r2 = dot(p, p);
	return u_center + p * (1.0 + u_bulge * r2 * 4.0);
}
"""

const SRC_RIPPLE: String = """
uniform float u_amount = 0.04; // @label Ripple Amount | @min 0 | @max 0.3 | @sens 0.004 | @rest 0
uniform float u_frequency = 24.0; // @label Frequency | @min 2 | @max 90 | @sens 1
uniform float u_speed = 4.0; // @label Wave Speed | @min 0 | @max 20 | @sens 0.25

vec2 fx_ripple(vec2 uv) {
	vec2 p = uv - vec2(0.5);
	float d = length(p);
	vec2 dir = p / max(d, 0.0001);
	return uv + dir * sin(d * u_frequency - u_time * u_speed) * u_amount;
}
"""

const SRC_PIXELATE: String = """
uniform float u_block = 0.1; // @label Block Size | @min 0 | @max 0.5 | @sens 0.005 | @rest 0

vec2 fx_pixelate(vec2 uv) {
	if (u_block < 0.002) {
		return uv;
	}
	return (floor(uv / u_block) + 0.5) * u_block;
}
"""

const SRC_ZOOM: String = """
uniform float u_zoom = 1.5; // @label Zoom Amount | @min -0.8 | @max 10 | @sens 0.1 | @rest 0
uniform vec2 u_center = vec2(0.5, 0.5); // @label Center | @min 0 | @max 1 | @sens 0.01

vec2 fx_zoom(vec2 uv) {
	vec2 p = uv - u_center;
	return u_center + p / max(1.0 + u_zoom, 0.05);
}
"""

const SRC_FLASH: String = """
uniform float u_dip = 1.0; // @label Dip Amount | @min 0 | @max 1 | @sens 0.05 | @rest 0
uniform vec4 u_dip_color : source_color = vec4(0.0, 0.0, 0.0, 1.0); // @label Dip Color | @min 0 | @max 1 | @sens 0.02

vec4 fx_flash(vec4 c, vec2 uv) {
	return vec4(mix(c.rgb, u_dip_color.rgb, u_dip), c.a);
}
"""
