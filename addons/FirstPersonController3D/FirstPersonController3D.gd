class_name FirstPersonController3D
extends CharacterBody3D
## First Person CharacterBody3D Controller
##
## Supports sprint, crouch, headbob, fov changes, and variable jump heights.
## Works pretty well on sloped surfaces - testing has not revealed any issues so far.


signal jumped
signal landed(fall_speed: float)
signal moved(speed_xz: float)
signal sprint_state_changed(is_sprinting: bool)
signal crouch_state_changed(is_crouching: bool)
## 0 is left, 1 is right
signal step_landed(foot: int)


# @export_group("Features")
## Enables sprint input and sprint speed multiplier.
@export var enable_sprint: bool = true
## Enables crouch input and crouch speed multiplier.
@export var enable_crouch: bool = true
# Enables a slight up and down motion while moving (visual only).
@export var enable_headbob: bool = true
## Enables FOV changes when sprinting (visual only).
@export var enable_fov_kick: bool = true
## Enables variable jump height by applying extra gravity when the jump input is released early.
@export var enable_variable_jump_height: bool = true


@export_group("Nodes")
## Node used as a pitch pivot and for headbob offsets.
@export var head: Node3D
## Camera used for the FOV kick. Usually a child of the head node.
@export var camera: Camera3D


@export_group("Inputs")
## Input action name for strafing left.
@export var input_move_left: StringName = &"move_left"
## Input action name for strafing right.
@export var input_move_right: StringName = &"move_right"
## Input action name for moving forward.
@export var input_move_forward: StringName = &"move_forward"
## Input action name for moving backward.
@export var input_move_backward: StringName = &"move_backward"
## Input action name for jumping.
@export var input_jump: StringName = &"jump"
## Input action name for sprinting.
@export var input_sprint: StringName = &"sprint"
## Input action name for crouching.
@export var input_crouch: StringName = &"crouch"


@export_group("Look")
## Mouse look sensitivity. Units are in degrees per pixel.
@export var mouse_sensitivity: float = 0.1
## If enabled, inverts vertical look input.
@export var invert_mouse_y: bool = false
## Minimum pitch angle (in degrees) that the player can look downward.
@export var min_pitch_degrees: float = -89.0
## Maximum pitch angle (in degrees) that the player can look upward.
@export var max_pitch_degrees: float = 89.0


@export_group("Speeds")
## Base walking speed in meters/second.
@export_range(0.1, 10.0, 0.01) var walk_speed: float = 5.0
## Multiplies walk_speed while sprinting (if enabled).
@export_range(0.0, 5.0, 0.01) var sprint_multiplier: float = 1.5
## Multiplies walk_speed while crouching (if enabled).
@export_range(0.0, 5.0, 0.01) var crouch_multiplier: float = 0.6
## Extra acceleration multiplier when steering direction is different from current velocity direction.
@export_range(1.0, 4.0, 0.01) var steering_boost: float = 1.5
## Dot threshold below which steering_boost is applied (1 -> same direction, 0 -> perpendicular).
@export_range(0.0, 1.0, 0.01) var steering_boost_start_dot: float = 0.95


@export_group("Acceleration")
## Enables smooth acceleration / deceleration (as opposed to instant movement).
@export var motion_smoothing: bool = true
## If true, removes velocity which opposes the input direction while on the ground.
## Intended to improve responsiveness.
@export var remove_opposing_velocity_on_ground: bool = false
## Horizontal acceleration rate while on the ground (m/s^2).
@export var ground_accel: float = 40.0
## Horizontal deceleration rate while on the ground (m/s^2).
@export var ground_decel: float = 30.0
## Horizontal acceleration rate while in the air (m/s^2).
## Applied before air_control scaling.
@export var air_accel: float = 12.0
## Horizontal deceleration rate while in the air (m/s^2).
## Applied before air_control scaling.
@export var air_decel: float = 7.0
## Controls how much air steering is possible by scaling in-air horizontal acceleration/deceleration rates.
@export_range(0.0, 1.0, 0.01) var air_control: float = 0.5


@export_group("Movement Curves")
## Acceleration multiplier curve. Sampled by the speed ratio (in [0, 1]) while accelerating.
@export var accel_curve: Curve
## Deceleration multiplier curve. Sampled by the speed ratio (in [0, 1]) while accelerating.
@export var decel_curve: Curve
## Minimum multiplier output allowed from the above curves.
@export_range(0.0, 3.0, 0.01) var curve_multiplier_min: float = 0.0
## Maximum multiplier output allowed from the above curves.
@export_range(0.0, 3.0, 0.01) var curve_multiplier_max: float = 2.0


@export_group("Jump")
## Initial upwards velocity which gets applied while jumping.
@export var jump_velocity: float = 5.0
## Gravity scaling while rising in the jump (lower -> floatier ascent).
@export var gravity_up_multiplier: float = 0.9
## Gravity scaling while descending in the jump (higher -> snappier descent).
@export var gravity_down_multiplier: float = 1.1
## Extra gravity multiplier which is applied when the jump input is released early.
@export var jump_cut_multiplier: float = 5.0


@export_group("Headbob")
## Maximum headbob vertical offset in meters.
@export var headbob_amplitude: float = 0.08
## Minimum horizontal speed before bob starts.
@export var headbob_min_speed: float = 0.1


@export_group("FOV Kick")
## Camera FOV while walking (degrees).
@export var fov_walk: float = 75.0
## Camera FOV while sprinting (degrees).
@export var fov_sprint: float = 82.0
## Interpolation speed towards target FOV.
@export var fov_lerp_speed: float = 8.0


@export_group("Footsteps")
## Distance per step in meters (per foot contact).
## Lower corresponds with more frequent steps.
@export_range(0.1, 3.0) var step_length: float = 1.0
## Minimum horizontal speed before steps begin registering.
@export var step_min_speed: float = 0.6


## Gravity base strength. Initially read from ProjectSettings.
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

## Relative mouse motion accumulator.
var _mouse_delta: Vector2 = Vector2.ZERO
## Transient variable for modifying the Y-axis rotation (radians) of the character
var _yaw: float
## Transient variable for modifying the X-axis rotation (radians) of the character's head (pitch)
var _pitch: float

## Whether the character is currently sprinting, based on the feature toggle and inputs
var _is_sprinting: bool = false
## Whether the character is currently crouching, based on the feature toggle and inputs
var _is_crouching: bool = false
## Whether the character was sprinting in the previous frame, used to emit sprint_state_changed on transitions.
var _was_sprinting: bool = false
## Whether the character was crouching in the previous frame, used to emit crouch_state_changed on transitions.
var _was_crouching: bool = false

## Whether the character was touching the floor in the previous frame. Used to track whether the character just landed on the ground.
var _was_on_floor: bool = true
## Vertical velocity in last frame for which the character was in-air. Used for landing effects. Emitted with the `landed` signal.
var _last_fall_speed: float = 0.0

## Where the position of the head is by default. Shouldn't change after initially setting.
var _head_base_local_pos: Vector3
## Stride phase is in [0, 1] for a full left->right->left cycle. Affects footsteps and headbob.
var _stride_phase: float = 0.0


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

	_post_move_events(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_mouse_delta += event.relative


#region State

## Updates sprint/crouch booleans based on inputs and @export-ed feature toggles.
## Also ensures that sprinting and crouching cannot happen at the same time.
func _update_states() -> void:
	_is_sprinting = enable_sprint and Input.is_action_pressed(input_sprint)
	_is_crouching = enable_crouch and Input.is_action_pressed(input_crouch)
	if _is_sprinting and _is_crouching:
		_is_sprinting = false


## Calculates the max movement speed after applying sprint/crouch modifiers.
func _current_max_speed() -> float:
	var speed := walk_speed
	if _is_sprinting:
		speed *= sprint_multiplier
	if _is_crouching:
		speed *= crouch_multiplier
	return speed

#endregion

#region Input

## Converts horizontal movement inputs into a normalized Vector3, rotated by the global_basis.
func _desired_direction_world() -> Vector3:
	var input_dir: Vector2 = Input.get_vector(
		input_move_left, input_move_right,
		input_move_forward, input_move_backward
	)

	var forward: Vector3 = -global_basis.z
	var right: Vector3 = global_basis.x
	# Flatten to XZ plane
	forward.y = 0.0
	right.y = 0.0

	var dir: Vector3 = right.normalized() * input_dir.x + forward.normalized() * -input_dir.y
	if not is_zero_approx(dir.length_squared()):
		return dir.normalized()
	return Vector3.ZERO


## Handles looking around with the mouse.
## Yaw on the body and pitch on the head (with clamping). Optional Y inversion.
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

## Handles jumping and gravity.
## Emits the jump signal when initially jumping and tracks fall speed to pass along to landing effects.
func _apply_vertical(delta: float) -> void:
	if is_on_floor() and Input.is_action_just_pressed(input_jump):
		velocity.y = jump_velocity
		jumped.emit()
		return

	if not is_on_floor():
		_last_fall_speed = velocity.y
		velocity.y -= _compute_gravity() * delta


## Calculates the effective gravity for this frame.
## Uses different multipliers based on whether movement is ascending or descending.
## Includes logic for cutting a jump off if the input is released early.
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

## Applies all horizontal movement.
## Calculates the target velocity from the desired (input) direction and max speed, then smooths towards it using curve-based acceleration.
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


## Small velocity tweak to improve responsiveness.
## If on the ground and currently moving opposite the desired direction, removes the opposing velocity component.
func _remove_opposing_vel_on_ground(current_xz: Vector3, desired_dir: Vector3) -> Vector3:
	if is_zero_approx(desired_dir.length_squared()) or is_zero_approx(current_xz.length_squared()) or not is_on_floor():
		return current_xz

	var desired_n: Vector3 = desired_dir.normalized()
	var along: float = current_xz.dot(desired_n)

	# If current velocity is moving opposite player input, remove just that opposing component.
	if along < 0.0:
		current_xz -= desired_n * along
	return current_xz


## Calculates an acceleration / deceleration rate (m/s / s) based on inputs, grounded/in air state, and (optional) movement curves.
func _get_rate_from_curve(current_xz: Vector3, target_xz: Vector3, max_speed: float) -> float:
	var has_input: bool = not is_zero_approx(target_xz.length_squared())

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
	if has_input and not is_zero_approx(current_xz.length_squared()):
		var cur_dir: Vector3 = current_xz.normalized() # Current velocity direction
		var tgt_dir: Vector3 = target_xz.normalized() # Input direction
		var dot: float = cur_dir.dot(tgt_dir) # 1 = same dir, 0 = perpendicular
		if dot < steering_boost_start_dot:
			rate *= steering_boost

	return rate

#endregion


#region Post-move Logic and Extras

## Anything that runs after movement happens.
## Emits landing/sprinting/crouching state changes, updates step phase, applies headbob, and applies the FOV "kick".
func _post_move_events(delta: float) -> void:
	if is_on_floor() and not _was_on_floor:
		landed.emit(_last_fall_speed)

	if _is_sprinting != _was_sprinting:
		sprint_state_changed.emit(_is_sprinting)
		_was_sprinting = _is_sprinting

	if _is_crouching != _was_crouching:
		crouch_state_changed.emit(_is_crouching)
		_was_crouching = _is_crouching

	_was_on_floor = is_on_floor()

	_advance_stride_phase(delta)

	if enable_headbob:
		_apply_headbob(delta)

	if enable_fov_kick and is_instance_valid(camera):
		var target_fov: float = fov_sprint if _is_sprinting else fov_walk
		camera.fov = lerpf(camera.fov, target_fov, fov_lerp_speed * delta)


## Applies a headbob (moving the head node's local y position).
## Synced to stride phase.
func _apply_headbob(delta: float) -> void:
	var speed_xz: float = Vector3(velocity.x, 0.0, velocity.z).length()

	if (
		is_on_floor()
		and speed_xz > headbob_min_speed
		and speed_xz > step_min_speed
	):
		var bob_y: float = -abs(cos(_stride_phase * TAU)) * headbob_amplitude
		head.position = _head_base_local_pos + Vector3(0.0, bob_y, 0.0)
	else:
		# Smoothly return to the base position when not stepping
		head.position = head.position.lerp(_head_base_local_pos, 10.0 * delta)


## Increases stride phase based on horizontal speed and defined step length.
## Emits step_landed at specific "marks" for left/right footsteps.
func _advance_stride_phase(delta: float) -> void:
	if not is_on_floor():
		return

	var speed_xz: float = Vector3(velocity.x, 0.0, velocity.z).length()
	if speed_xz < step_min_speed:
		return

	# step_length is distance per foot contact
	var stride_length: float = maxf(step_length * 2.0, 1e-4)

	var prev_phase: float = _stride_phase

	# Phase increases by distance traveled / stride length
	_stride_phase = fmod(_stride_phase + (speed_xz * delta) / stride_length, 1.0)

	# Footsteps happen twice per stride
	# left at 0.0, right at 0.5
	if _crossed_phase(prev_phase, _stride_phase, 0.0):
		step_landed.emit(0) # left
	if _crossed_phase(prev_phase, _stride_phase, 0.5):
		step_landed.emit(1) # right


## Returns true if phase ("now") advanced past "mark".
## Intended to trigger/signal step events in a robust way.
func _crossed_phase(prev: float, now: float, mark: float) -> bool:
	if prev <= now:
		return prev < mark and mark <= now
	# wrapped: [prev..1) U [0..now]
	return (prev < mark and mark <= 1.0) or (0.0 <= mark and mark <= now)

#endregion
