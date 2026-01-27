extends Label

@onready var player: FirstPersonController3D = $"../Player"


var debug_info: Dictionary[String, String] = {}

func _ready() -> void:
	player.jumped.connect(_on_player_jumped)
	player.landed.connect(_on_player_landed)
	player.moved.connect(_on_player_moved)
	player.sprint_state_changed.connect(_on_player_sprint_state_changed)
	player.crouch_state_changed.connect(_on_player_crouch_state_changed)
	player.step_landed.connect(_on_player_step_landed)
	

func _physics_process(_delta: float) -> void:
	var key_sizes: Array[int]
	key_sizes.assign(debug_info.keys().map(func(x: String): return x.length()))
	var max_width: int = key_sizes.max() + 2
	var sorted_keys: Array[String] = debug_info.keys()
	sorted_keys.sort()
	text = ""
	for key in sorted_keys:
		text += "%s: %s\n" % [key.rpad(max_width), debug_info[key]]
	
	
func _on_player_jumped() -> void:
	debug_info["player_jumped"] = "TRUE"
	debug_info["player_landed"] = "FALSE"
	
func _on_player_landed(fall_speed: float) -> void:
	debug_info["player_jumped"] = "FALSE"
	debug_info["player_landed"] = "TRUE"
	debug_info["fall_speed"] = str(snappedf(fall_speed, 0.001))
	
func _on_player_moved(speed_xz: float) -> void:
	debug_info["player_move_speed"] = str(snappedf(speed_xz, 0.001))
	
func _on_player_sprint_state_changed(is_sprinting: bool) -> void:
	debug_info["is_sprinting"] = str(is_sprinting)
	
func _on_player_crouch_state_changed(is_crouching: bool) -> void:
	debug_info["is_crouching"] = str(is_crouching)
	
func _on_player_step_landed(foot: int) -> void:
	debug_info["player_stepped"] = "LEFT" if foot == 0 else "RIGHT"
	
