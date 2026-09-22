extends Node
## HelpViewer.gd -- "❓ HELP" (System Main Menu)
##
## Reads res://README.md as plain text at runtime and shows it in a scrollable panel: D-pad up/down
## scroll, ❌) returns to normal. Because the text is read from disk each time it opens rather than
## baked into a script, editing README.md and re-exporting is all it takes to change what Help shows.

const README_PATH: String = "res://README.md"
const SCROLL_STEP: float = 60.0

var main
var owner_menu

var is_open: bool = false
var _panel: PanelContainer
var _rtl: RichTextLabel


func setup(main_manager, owner_options: Object) -> void:
	main = main_manager
	owner_menu = owner_options
	_build_panel()

func _build_panel() -> void:
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.02, 0.04, 0.96)
	style.set_border_width_all(2)
	style.border_color = Color(1.0, 0.6, 0.0, 0.9) # matches the 🟠 main menu button
	style.set_corner_radius_all(8)
	style.set_content_margin_all(16)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.custom_minimum_size = Vector2(560, 460)
	_panel.visible = false
	main.menu_center_host.add_child(_panel)

	var box := VBoxContainer.new()
	_panel.add_child(box)

	var title := Label.new()
	title.text = " ❓ README "
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color.ORANGE)
	box.add_child(title)

	_rtl = RichTextLabel.new()
	_rtl.bbcode_enabled = false # plain text: the README's own formatting isn't reinterpreted as markup
	_rtl.scroll_active = true
	_rtl.custom_minimum_size = Vector2(520, 380)
	_rtl.add_theme_color_override("default_color", Color.WHITE)
	box.add_child(_rtl)

	var hint := Label.new()
	hint.text = " ▲▼ SCROLL    ❌ BACK "
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color.DIM_GRAY)
	box.add_child(hint)

func _read_readme() -> String:
	if not FileAccess.file_exists(README_PATH):
		return "README.md not found.\n\nPlace a README.md file in the project root to show it here."
	var f := FileAccess.open(README_PATH, FileAccess.READ)
	if f == null:
		return "Could not open README.md."
	return f.get_as_text()

func open() -> void:
	is_open = true
	_rtl.text = _read_readme()
	_rtl.scroll_to_line(0)
	main.menu_center_host.visible = true
	_panel.visible = true

func close() -> void:
	is_open = false
	_panel.visible = false
	var cp = main.control_panel
	if cp.active_state == cp.ControlState.HIDDEN:
		main.menu_center_host.visible = false

func scroll(step: int) -> void:
	if not is_open:
		return
	var bar := _rtl.get_v_scroll_bar()
	bar.value = clampf(bar.value + float(step) * SCROLL_STEP, bar.min_value, bar.max_value)
