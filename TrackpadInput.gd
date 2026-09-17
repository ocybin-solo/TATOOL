extends Control

signal dragged_delta(val: float)

var dragging: bool = false
var last_mouse_pos: Vector2 = Vector2.ZERO
var touch_pointer_pos: Vector2 = Vector2.ZERO

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton or event is InputEventScreenTouch:
		if event.is_pressed():
			dragging = true
			last_mouse_pos = event.position
			touch_pointer_pos = event.position
			queue_redraw()
		else:
			dragging = false
			queue_redraw()
			
	elif event is InputEventMouseMotion or event is InputEventScreenDrag:
		if dragging:
			var center = size / 2
			var prev_vec = last_mouse_pos - center
			var curr_vec = event.position - center
			
			# Rotational delta computed from movement angle shifts
			var angle_delta = prev_vec.angle_to(curr_vec)
			dragged_delta.emit(angle_delta)
			
			# Constrain visual pointer marker cleanly to the trackpad radius boundary
			var radius = min(size.x, size.y) / 2 - 10
			touch_pointer_pos = center + curr_vec.normalized() * radius
			
			last_mouse_pos = event.position
			queue_redraw()

func _draw() -> void:
	var center = size / 2
	var radius = min(size.x, size.y) / 2 - 10
	
	# Draw baseline trackpad track
	draw_circle(center, radius, Color(0.15, 0.15, 0.15, 0.8))
	draw_arc(center, radius, 0, TAU, 64, Color.DIM_GRAY, 3.0)
	draw_circle(center, 8, Color.LIGHT_GRAY)
	
	# Draw touch indicator node if the surface is under active manipulation
	if dragging:
		draw_circle(touch_pointer_pos, 14, Color(1.0, 1.0, 1.0, 0.4))
		draw_circle(touch_pointer_pos, 8, Color.WHITE)
