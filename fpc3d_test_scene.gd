extends Node3D


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_released("ui_cancel"):
		get_tree().quit()
		
