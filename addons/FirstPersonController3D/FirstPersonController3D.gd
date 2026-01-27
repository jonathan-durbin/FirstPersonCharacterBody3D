class_name FirstPersonController3D
extends CharacterBody3D
## First Person CharacterBody3D Controller
##
## Supports sprint, crouch, headbob, fov changes, and variable jump heights.
## Works pretty well on sloped surfaces - testing has not revealed any issues so far.


@export_group("Features")
@export var enable_sprint: bool = true
@export var enable_crouch: bool = true
# Slight up and down motion while moving
@export var enable_headbob: bool = true
@export var enable_fov_kick: bool = true
@export var enable_variable_jump_height: bool = true


@export_group("Nodes")
@export var head: Node3D
@export var camera: Camera3D


@export_group("Inputs")
@export var input_move_left: StringName = &"move_left"
@export var input_move_right: StringName = &"move_right"
@export var input_move_forward: StringName = &"move_forward"
@export var input_move_backward: StringName = &"move_backward"
@export var input_jump: StringName = &"jump"
@export var input_sprint: StringName = &"sprint"
@export var input_crouch: StringName = &"crouch"


@export_group("Look")
@export var mouse_sensitivity: float = 0.1
@export var invert_mouse_y: bool = false
@export var min_pitch_degrees: float = -89.0
@export var max_pitch_degrees: float = 89.0


@export_group("Speeds")
@export_range(0.1, 10.0, 0.01) var walk_speed: float = 5.0
@export_range(0.0, 5.0, 0.01) var sprint_multiplier: float = 1.5
@export_range(0.0, 5.0, 0.01) var crouch_multiplier: float = 0.6
# @export_range(0.0, 1.0, 0.01) var air_speed_multiplier: float = 1.0

@export_range(1.0, 4.0, 0.01) var steering_boost: float = 1.5
@export_range(0.0, 1.0, 0.01) var steering_boost_start_dot: float = 0.95


@export_group("Acceleration")
@export var motion_smoothing: bool = true
@export var remove_opposing_velocity_on_ground: bool = false

@export var ground_accel: float = 40.0 # m/s^2
@export var ground_decel: float = 30.0 # m/s^2
@export var air_accel: float = 12.0     # m/s^2 (pre-scale)
@export var air_decel: float = 7.0     # m/s^2 (pre-scale)
@export_range(0.0, 1.0, 0.01) var air_control: float = 0.5

@export_group("Movement Curves")
@export var accel_curve: Curve
@export var decel_curve: Curve
@export_range(0.0, 3.0, 0.01) var curve_multiplier_min: float = 0.0
@export_range(0.0, 3.0, 0.01) var curve_multiplier_max: float = 2.0


@export_group("Jump")
@export var jump_velocity: float = 5.0
@export var gravity_up_multiplier: float = 0.9
@export var gravity_down_multiplier: float = 1.1
@export var jump_cut_multiplier: float = 5.0


@export_group("Headbob")
@export var headbob_amplitude: float = 0.08
## How frequently the head bobs. 
## May need to be adjusted according to the sprinting speed.
@export var headbob_frequency: float = 15.0
## Minimum speed before bob starts
@export var headbob_min_speed: float = 0.1

@export_group("FOV Kick")
@export var fov_walk: float = 75.0
@export var fov_sprint: float = 82.0
@export var fov_lerp_speed: float = 8.0

@export_group("Footsteps")
## Distance per step. Lower corresponds with more frequent steps.
@export_range(0.1, 3.0) var step_length: float = 1.0
## Minimum speed before steps start
@export var steps_min_speed: float = 0.6


signal jumped
signal landed(fall_speed: float)
signal moved(speed_xz: float)
signal sprint_state_changed(is_sprinting: bool)
signal crouch_state_changed(is_crouching: bool)
signal step_landed(foot: int) # 0 is left, 1 is right


const EPS: float = 1e-6

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var _mouse_delta: Vector2 = Vector2.ZERO
var _yaw: float
var _pitch: float

var _is_sprinting: bool = false
var _is_crouching: bool = false
var _prev_sprinting: bool = false
var _prev_crouching: bool = false

var _was_on_floor: bool = true
var _last_fall_speed: float = 0.0

## Where the position of the head is by default. Shouldn't change after setting.
var _head_base_local_pos: Vector3
var _headbob_phase: float = 0.0

var _step_phase: float = 0.0
var _step_foot: int = 0


func _ready() -> void:
	_yaw = rotation.y

	if is_instance_valid(head):
		_pitch = head.rotation.x
		_head_base_local_pos = head.position
	else:
		push_error("FirstPersonController3D: Head is not defined!")

	_was_on_floor = is_on_floor()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if is_instance_valid(camera):
		if enable_fov_kick:
			camera.fov = fov_walk
	else:
		push_error("FirstPersonController3D: Camera is not defined!")


func _physics_process(delta: float) -> void:
	_update_states()
	_apply_look()

	_apply_vertical(delta)
	_apply_horizontal(delta)

	move_and_slide()

	_post_move_events()
	_apply_extras(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_mouse_delta += event.relative


#region State

func _update_states() -> void:
	_is_sprinting = enable_sprint and Input.is_action_pressed(input_sprint)
	_is_crouching = enable_crouch and Input.is_action_pressed(input_crouch)
	if _is_sprinting and _is_crouching:
		_is_sprinting = false


func _current_max_speed() -> float:
	var speed := walk_speed

	if _is_sprinting:
		speed *= sprint_multiplier
	if _is_crouching:
		speed *= crouch_multiplier

	return speed


func _desired_direction_world() -> Vector3:
	var input_dir: Vector2 = Input.get_vector(
		input_move_left, input_move_right,
		input_move_forward, input_move_backward
	)

	var forward: Vector3 = -global_transform.basis.z
	var right: Vector3 = global_transform.basis.x
	forward.y = 0.0
	right.y = 0.0

	var dir: Vector3 = right.normalized() * input_dir.x + forward.normalized() * -input_dir.y
	if dir.length_squared() > EPS:
		return dir.normalized()
	return Vector3.ZERO

#endregion


#region Look

func _apply_look() -> void:
	var dx: float = _mouse_delta.x * mouse_sensitivity
	var dy: float = _mouse_delta.y * mouse_sensitivity

	_yaw -= deg_to_rad(dx)

	var pitch_sign: float = 1.0 if invert_mouse_y else -1.0
	_pitch += deg_to_rad(dy) * pitch_sign
	_pitch = clampf(_pitch, deg_to_rad(min_pitch_degrees), deg_to_rad(max_pitch_degrees))

	rotation.y = _yaw
	head.rotation.x = _pitch

	_mouse_delta = Vector2.ZERO

#endregion


#region Vertical

func _apply_vertical(delta: float) -> void:
	if is_on_floor() and Input.is_action_just_pressed(input_jump):
		velocity.y = jump_velocity
		jumped.emit()
		return

	if not is_on_floor():
		_last_fall_speed = velocity.y
		velocity.y -= _compute_gravity() * delta


func _compute_gravity() -> float:
	var g: float = _gravity

	if velocity.y > 0.0:
		g *= gravity_up_multiplier
	else:
		g *= gravity_down_multiplier

	if enable_variable_jump_height and velocity.y > 0.0 and Input.is_action_just_released(input_jump):
		g *= jump_cut_multiplier

	return g

#endregion


#region Horizontal

func _apply_horizontal(delta: float) -> void:
	var desired_dir: Vector3 = _desired_direction_world()
	var max_speed: float = _current_max_speed()
	var target_xz: Vector3 = desired_dir * max_speed

	if not motion_smoothing:
		velocity.x = target_xz.x
		velocity.z = target_xz.z
		return

	var current_xz: Vector3 = Vector3(velocity.x, 0.0, velocity.z)

	if remove_opposing_velocity_on_ground and is_on_floor():
		current_xz = _remove_opposing_vel_on_ground(current_xz, desired_dir)

	var rate: float = _get_rate_from_curve(current_xz, target_xz, max_speed)

	current_xz = current_xz.move_toward(target_xz, rate * delta)

	velocity.x = current_xz.x
	velocity.z = current_xz.z

	moved.emit(current_xz.length())


func _remove_opposing_vel_on_ground(current_xz: Vector3, desired_dir: Vector3) -> Vector3:
	if desired_dir.length_squared() <= EPS or current_xz.length_squared() <= EPS or not is_on_floor():
		return current_xz

	var desired_n: Vector3 = desired_dir.normalized()
	var along: float = current_xz.dot(desired_n)

	# If curent velocity is moving opposite player input, remove just that opposing component.
	if along < 0.0:
		current_xz -= desired_n * along
	return current_xz


func _get_rate_from_curve(current_xz: Vector3, target_xz: Vector3, max_speed: float) -> float:
	var has_input: bool = target_xz.length_squared() > EPS

	var base_rate: float
	if is_on_floor():
		base_rate = ground_accel if has_input else ground_decel
	else:
		base_rate = (air_accel if has_input else air_decel) * air_control

	var speed_ratio: float = clampf(
		current_xz.length() / maxf(max_speed, 1e-4),
		0.0, 1.0
	)

	var curve: Curve = accel_curve if has_input else decel_curve
	var mult: float = 1.0
	if is_instance_valid(curve):
		mult = clampf(curve.sample(speed_ratio), curve_multiplier_min, curve_multiplier_max)

	var rate: float = base_rate * mult

	# If there is input and we're not aligned, boost the acceleration rate
	if has_input and current_xz.length_squared() > EPS:
		var cur_dir: Vector3 = current_xz.normalized() # Current velocity direction
		var tgt_dir: Vector3 = target_xz.normalized() # Current input direction
		var dot: float = cur_dir.dot(tgt_dir) # 1 = same dir, 0 = perpendicular
		if dot < steering_boost_start_dot:
			rate *= steering_boost # Apply steering boost if input wants to go in a slightly different direction

	return rate

#endregion


#region Post-move Logic and Extras

func _post_move_events() -> void:
	if is_on_floor() and not _was_on_floor:
		landed.emit(_last_fall_speed)

	if _is_sprinting != _prev_sprinting:
		sprint_state_changed.emit(_is_sprinting)
		_prev_sprinting = _is_sprinting

	if _is_crouching != _prev_crouching:
		crouch_state_changed.emit(_is_crouching)
		_prev_crouching = _is_crouching

	_was_on_floor = is_on_floor()


func _apply_extras(delta: float) -> void:
	_update_steps(delta)
	
	if enable_headbob:
		_apply_headbob(delta)

	if enable_fov_kick:
		var target_fov: float = fov_sprint if _is_sprinting else fov_walk
		camera.fov = lerpf(camera.fov, target_fov, fov_lerp_speed * delta)


func _apply_headbob(delta: float) -> void:
	var speed_xz: float = Vector3(velocity.x, 0.0, velocity.z).length()

	if is_on_floor() and speed_xz > headbob_min_speed:
		# How close we are to max speed. Clamped to avoid unreasonable values
		var speed_ratio: float = clampf(
			inverse_lerp(0.0, walk_speed * sprint_multiplier, speed_xz), 
			0.0, 1.0
		)
		_headbob_phase += headbob_frequency * speed_ratio * delta
		var bob: float = sin(_headbob_phase) * headbob_amplitude
		head.position = _head_base_local_pos + Vector3(0.0, bob, 0.0)
	else:
		# Reset and smoothly move back to the base position
		_headbob_phase = 0.0
		head.position = head.position.lerp(_head_base_local_pos, 10.0 * delta)


func _update_steps(delta: float) -> void:
	if not is_on_floor():
		return
	
	var speed_xz: float = Vector3(velocity.x, 0.0, velocity.z).length()
	if speed_xz < steps_min_speed:
		return
	
	_step_phase += (speed_xz * delta) / step_length
	
	while _step_phase >= 1.0:
		_step_phase -= 1.0
		step_landed.emit(_step_foot)
		_step_foot = 1 - _step_foot
		
#endregion
