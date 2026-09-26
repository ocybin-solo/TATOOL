extends Node
## HelpViewer.gd -- "❓ HELP" (System Main Menu)
##
## Reads res://README.md as plain text at runtime and shows it in a scrollable, ALWAYS FULL-SCREEN
## panel: D-pad up/down scroll, ❌ or the on-screen ✕ CLOSE button return to normal. Deliberately its
## own CanvasLayer rather than a child of menu_center_host -- Menu Center/Menu Size are user-movable
## and user-scalable, and Help has to stay fully reachable no matter where those end up.
## Because the text is read from disk each time it opens rather than baked into a script, editing
## README.md and re-exporting is all it takes to change what Help shows.

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
	# A dedicated top-layer, above every other menu/overlay in the app, so Help is always genuinely
	# on top and full-screen regardless of anything else happening underneath.
	var overlay_layer := CanvasLayer.new()
	overlay_layer.layer = 10
	main.add_child(overlay_layer)

	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT) # always the whole window
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.02, 0.04, 0.98)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.visible = false
	overlay_layer.add_child(_panel)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 24)
	_panel.add_child(margin)

	var box := VBoxContainer.new()
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(box)

	var title := Label.new()
	title.text = " ❓ README "
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color.ORANGE)
	box.add_child(title)

	_rtl = RichTextLabel.new()
	_rtl.bbcode_enabled = false # plain text: the README's own formatting isn't reinterpreted as markup
	_rtl.scroll_active = true
	_rtl.size_flags_vertical = Control.SIZE_EXPAND_FILL # fills whatever room is left, any screen size
	_rtl.add_theme_color_override("default_color", Color.WHITE)
	box.add_child(_rtl)

	var hint := Label.new()
	hint.text = " ▲▼ SCROLL    ❌ OR TAP CLOSE BELOW "
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color.DIM_GRAY)
	box.add_child(hint)

	var close_btn := Button.new()
	close_btn.text = "✕ CLOSE"
	close_btn.custom_minimum_size = Vector2(0, 64)
	close_btn.add_theme_font_size_override("font_size", 28)
	close_btn.pressed.connect(close_and_return)
	box.add_child(close_btn)

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
	_panel.visible = true

## Hides the panel only. Used where the caller (DynamicUI, MainManager's close-everything paths)
## still needs to update active_state itself -- see close_and_return() for the common case.
func close() -> void:
	is_open = false
	_panel.visible = false

## The one true "Help is done" action -- called by both the physical ❌ button (via DynamicUI's
## B-handler) and the on-screen ✕ CLOSE button, so the two can never disagree about app state.
func close_and_return() -> void:
	close()
	main.control_panel.active_state = main.control_panel.ControlState.HIDDEN

func scroll(step: int) -> void:
	if not is_open:
		return
	var bar := _rtl.get_v_scroll_bar()
	bar.value = clampf(bar.value + float(step) * SCROLL_STEP, bar.min_value, bar.max_value)
