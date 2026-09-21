extends Control
## GridEditOverlay.gd -- the "Reposition Buttons" touch layer, created and owned by ControllerLayout.gd
##
## It sits on top of the 5 x 5 button grid, lights up every cell, and receives ALL touches while editing, so the
## real buttons underneath never see them (a button can therefore never fire by accident during or after a drag).
##   tap the A button          accept the layout
##   tap the B button          cancel the changes
##   tap any other button      nothing
##   press and hold a button   starts a drag (moving the finger a little also starts it)
##   drop on an empty cell     moves the button there
##   drop on a taken cell      swaps the two buttons
##   drop outside the grid     the button stays where it was

const HOLD_MSEC: int = 350
const MOVE_PX: float = 12.0

var layout # ControllerLayout

var _pressed: bool = false
var _press_cell: int = -1
var _press_pos: Vector2 = Vector2.ZERO
var _press_msec: int = 0
var _dragging: bool = false
var _drag_id: String = ""
var _hover_cell: int = -1
var _ghost: Control = null


func setup(owner_layout) -> void:
	layout = owner_layout
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	set_process(false)

## Forget any press or drag in progress (used when edit mode starts or ends).
func reset_interaction() -> void:
	_finish_drag()
	_pressed = false
	_press_cell = -1
	set_process(false)
	queue_redraw()


# =========================================================================
# INPUT (mouse events; touches arrive as emulated mouse events, like they do for the app's real buttons)
# =========================================================================
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index != MOUSE_BUTTON_LEFT:
			return
		accept_event()
		if event.pressed:
			if _pressed:
				return # a second finger: ignore
			_pressed = true
			_press_pos = event.position
			_press_cell = layout.cell_at(event.position)
			_press_msec = Time.get_ticks_msec()
			_hover_cell = _press_cell
			set_process(true)
		elif _pressed:
			_pressed = false
			set_process(false)
			_released(event.position)
		queue_redraw()
	elif event is InputEventMouseMotion and _pressed:
		accept_event()
		if not _dragging and layout.button_at(_press_cell) != "" and event.position.distance_to(_press_pos) > MOVE_PX:
			_begin_drag(event.position)
		if _dragging:
			_move_drag(event.position)

## Holding still on a button also starts a drag once the hold time has passed.
func _process(_delta: float) -> void:
	if _pressed and not _dragging and layout.button_at(_press_cell) != "":
		if Time.get_ticks_msec() - _press_msec >= HOLD_MSEC:
			_begin_drag(get_local_mouse_position())
	if _dragging:
		_move_drag(get_local_mouse_position())

func _begin_drag(pos: Vector2) -> void:
	_drag_id = layout.button_at(_press_cell)
	if _drag_id == "":
		return
	_dragging = true
	_ghost = layout.make_ghost(_drag_id)
	add_child(_ghost)
	layout.set_button_dim(_drag_id, true) # the real button stays put, dimmed, until the drop
	_move_drag(pos)

func _move_drag(pos: Vector2) -> void:
	if _ghost != null and is_instance_valid(_ghost):
		_ghost.position = pos - layout.cell_size() * 0.5
	_hover_cell = layout.cell_at(pos)
	queue_redraw()

func _released(pos: Vector2) -> void:
	if _dragging:
		var moved_id: String = _drag_id
		var target: int = layout.cell_at(pos)
		_finish_drag()
		if target != -1 and target != _press_cell:
			layout.edit_move(moved_id, target)
	else:
		# A tap
		var id: String = layout.button_at(_press_cell)
		if id == "a":
			_press_cell = -1
			layout.edit_accept()
			return
		if id == "b":
			_press_cell = -1
			layout.edit_cancel()
			return
	_press_cell = -1

func _finish_drag() -> void:
	if _ghost != null and is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null
	if _drag_id != "":
		layout.set_button_dim(_drag_id, false)
	_drag_id = ""
	_dragging = false
	_hover_cell = -1


# =========================================================================
# DRAWING: every position lit, the accept (A, green) and cancel (B, red) buttons ringed
# =========================================================================
func _draw() -> void:
	if layout == null:
		return
	var lit: Color = Color(0.3, 1.0, 1.0)
	for i in range(layout.COLUMNS * layout.ROWS):
		var r: Rect2 = layout.cell_rect(i)
		var occupied: bool = layout.button_at(i) != ""
		draw_rect(r, Color(lit.r, lit.g, lit.b, 0.06 if occupied else 0.14), true)
		draw_rect(r, Color(lit.r, lit.g, lit.b, 0.85), false, 2.0)
	if _dragging and _hover_cell != -1:
		var h: Rect2 = layout.cell_rect(_hover_cell)
		draw_rect(h, Color(1.0, 1.0, 0.0, 0.25), true)
		draw_rect(h, Color(1.0, 1.0, 0.0, 1.0), false, 3.0)
	draw_rect(layout.cell_rect(layout.cell_of("a")), Color(0.2, 1.0, 0.2, 1.0), false, 4.0)
	draw_rect(layout.cell_rect(layout.cell_of("b")), Color(1.0, 0.25, 0.25, 1.0), false, 4.0)
