extends CharacterBody3D
## Arcade skater. Push for speed, carve, ollie, trick, land.

enum State { WAIT, RIDE, CRASH }

const GRAVITY := 22.0
const MAX_SPEED := 5.0
const PUSH_TOP := 8.5
const CRUISE := 3.6

var state: State = State.WAIT
var spawn_pos := Vector3(0, 0.3, 4)
var spawn_heading := 0.0
var heading := 0.0
var speed := 0.0
var charge := 0.0
var airborne := false
var air_time := 0.0
var stick_lock := 0.0
var spawn_grace := 0.4
var lean := 0.0
var cam_forward := Vector3(0, 0, -1)
var cam_right := Vector3(1, 0, 0)
var speed_mps := 0.0
var points := 0
var saved_best := 0
var combo := 0
var line_mult := 1.0
var trick_history: Array[String] = []
var banner := ""
var banner_ttl := 0.0
var live_trick := ""
var crash_reason := ""

var spin_v := 0.0
var pitch_v := 0.0
var roll_v := 0.0
var visual_yaw := 0.0
var visual_pitch := 0.0
var visual_roll := 0.0
var spin_accum := 0.0
var flip_accum := 0.0
var roll_accum := 0.0
var grab_name := ""
var grab_time := 0.0
var off_axis := false
var back_flip := false
var lip_time := 0.0
var takeoff_boost := 0.0
var last_normal := Vector3.UP
var pop_t := 0.0
var land_blend := 0.0
var crash_spin := 0.0

var visual: Node3D
var rider: Node3D
var board_pivot: Node3D
var board_flip := 0.0
var board_shove := 0.0
var flip_v := 0.0
var shove_v := 0.0
var visual_normal := Vector3.UP
var roll_fast := false
var anim: AnimationPlayer
var _anim_name := ""
var _space_was := false
var _jumped := false
var grinding := false
var grind_lines: Array = []
var grind_line := PackedVector3Array()
var grind_index := -1
var grind_along := 0.0
var grind_sign := 1.0
var grind_balance := 0.0
var jump_air := false
var rail_lock := 0.0
var sliding := false
var slide_lines: Array = []
var slide_line := PackedVector3Array()
var slide_index := -1
var slide_along := 0.0
var slide_sign := 1.0
var slide_lock := 0.0
var slide_travel := 0.0
var push_hold := 0.0
var ragdoll: RigidBody3D
var crash_time := 0.0
var _shift_down := false


func _ready() -> void:
	floor_max_angle = deg_to_rad(74.0)
	floor_snap_length = 0.4
	floor_stop_on_slope = false
	floor_block_on_wall = false
	floor_constant_speed = true
	safe_margin = 0.05
	collision_layer = 1
	collision_mask = 1
	_ensure_slide_action()
	_build_body()
	_build_visual()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if key.keycode == KEY_SHIFT or key.physical_keycode == KEY_SHIFT:
		_shift_down = key.pressed


func _ensure_slide_action() -> void:
	if not InputMap.has_action("slide"):
		InputMap.add_action("slide")
	var event := InputEventKey.new()
	event.keycode = KEY_SHIFT
	event.physical_keycode = KEY_SHIFT
	if not InputMap.action_has_event("slide", event):
		InputMap.action_add_event("slide", event)


func _shift_held() -> bool:
	if _shift_down:
		return true
	if InputMap.has_action("slide") and Input.is_action_pressed("slide"):
		return true
	return Input.is_key_pressed(KEY_SHIFT) or Input.is_physical_key_pressed(KEY_SHIFT)


func begin() -> void:
	_end_ragdoll()
	state = State.RIDE
	grinding = false
	grind_index = -1
	sliding = false
	slide_index = -1
	slide_lock = 0.0
	slide_travel = 0.0
	jump_air = false
	rail_lock = 0.0
	_collect_slide_lines()
	spawn_grace = 0.4
	speed = 0.0
	heading = 0.0
	airborne = false
	air_time = 0.0
	charge = 0.0
	velocity = Vector3.ZERO
	_clear_air_rotation()
	land_blend = 0.0


func reset_run() -> void:
	points = 0
	combo = 0
	line_mult = 1.0
	trick_history.clear()
	banner = ""
	banner_ttl = 0.0
	live_trick = ""
	crash_reason = ""
	crash_spin = 0.0
	crash_time = 0.0
	charge = 0.0
	heading = spawn_heading
	stick_lock = 0.0
	pop_t = 0.0
	global_position = spawn_pos
	velocity = Vector3.ZERO
	_clear_air_rotation()
	begin()


func crash(reason: String) -> void:
	if state != State.RIDE:
		return
	state = State.CRASH
	grinding = false
	sliding = false
	jump_air = false
	rail_lock = 0.0
	crash_reason = reason
	crash_spin = 0.0
	combo = 0
	line_mult = 1.0
	banner = "WASTED"
	banner_ttl = 3.0
	speed = minf(speed, 1.5)
	_write_best()
	_begin_ragdoll()


func _physics_process(delta: float) -> void:
	banner_ttl = maxf(banner_ttl - delta, 0.0)
	stick_lock = maxf(stick_lock - delta, 0.0)
	rail_lock = maxf(rail_lock - delta, 0.0)
	slide_lock = maxf(slide_lock - delta, 0.0)
	spawn_grace = maxf(spawn_grace - delta, 0.0)
	pop_t = maxf(pop_t - delta, 0.0)
	if state == State.WAIT:
		global_position = spawn_pos
		velocity = Vector3.ZERO
		_update_facing(delta)
		_update_anim()
		return
	if state == State.CRASH:
		crash_spin += delta
		crash_time += delta
		_step_ragdoll(delta)
		_update_facing(delta)
		_update_anim()
		_refresh_numbers()
		if crash_time >= 3.0:
			reset_run()
		return

	if sliding:
		_edge_slide(delta)
		_finish_ride_frame(delta)
		return
	if grinding:
		_grind_slide(delta)
		_finish_ride_frame(delta)
		return
	if state == State.RIDE and spawn_grace <= 0.0 and _try_start_slide():
		_edge_slide(delta)
		_finish_ride_frame(delta)
		return
	if state == State.RIDE and spawn_grace <= 0.0 and _try_start_grind():
		_grind_slide(delta)
		_finish_ride_frame(delta)
		return

	_jumped = false
	# Only the real floor counts. Treating "still low in the air" as ground
	# made the top of a quarter flicker between riding and launching.
	var grounded: bool = (not airborne) and is_on_floor() and stick_lock <= 0.0
	floor_snap_length = 0.28 if last_normal.y > 0.4 else 0.0
	if grounded:
		_ground_physics(delta)
	else:
		if not airborne:
			_launch_from_lip()
		airborne = true
		air_time += delta
		_air_physics(delta)

	move_and_slide()
	_release_steep_face()

	if state == State.RIDE and spawn_grace <= 0.0 and _try_start_slide():
		_finish_ride_frame(delta)
		return

	if state == State.RIDE and spawn_grace <= 0.0 and _try_start_grind():
		_finish_ride_frame(delta)
		return

	var touched := is_on_floor() and stick_lock <= 0.0
	if airborne and touched:
		airborne = false
		jump_air = false
		var hung := air_time
		air_time = 0.0
		spin_v = 0.0
		flip_v = 0.0
		shove_v = 0.0
		if hung > 0.28 and state == State.RIDE and spawn_grace <= 0.0:
			_resolve_landing(hung)
	elif not touched and not airborne and state == State.RIDE:
		_launch_from_lip()
		airborne = true

	if state == State.RIDE and spawn_grace <= 0.0:
		if global_position.y < -4.0 or global_position.x < -34.0 or global_position.x > 33.0 or global_position.z < -29.0 or global_position.z > 31.0:
			crash("Left the park")

	_finish_ride_frame(delta)


func _speed_cap() -> float:
	return lerpf(MAX_SPEED, PUSH_TOP, clampf(push_hold / 1.25, 0.0, 1.0))


func _release_steep_face() -> void:
	# The top of a quarter is a wall. Hitting it every frame is the buzz.
	# Leave it once, then stay off it long enough to not stick again.
	if state != State.RIDE or grinding or sliding or stick_lock > 0.0:
		return
	var push := Vector3.ZERO
	var steep := false
	for i in get_slide_collision_count():
		var n := get_slide_collision(i).get_normal()
		if n.y >= 0.34:
			continue
		steep = true
		var flat := Vector3(n.x, 0.0, n.z)
		if flat.length_squared() > 0.01:
			push += flat.normalized()
	if not steep:
		return
	if push.length_squared() > 0.01:
		push = push.normalized()
	var carry := maxf(speed, 4.0)
	velocity = push * (carry * 0.45) + Vector3.UP * (1.6 + carry * 0.1)
	var flat_vel := Vector3(velocity.x, 0.0, velocity.z)
	if flat_vel.length_squared() > 0.04:
		heading = atan2(-flat_vel.x, -flat_vel.z)
	speed = minf(carry, _speed_cap())
	airborne = true
	stick_lock = 0.32


func _ground_physics(delta: float) -> void:
	var n := get_floor_normal()
	if n.length_squared() < 0.01:
		n = Vector3.UP
	last_normal = n
	var steer := _steer_axis()
	var slope := 1.0 - clampf(n.y, 0.0, 1.0)
	var rate := lerpf(3.2, 1.0, clampf(speed / 9.0, 0.0, 1.0))
	if slope > 0.08:
		rate = lerpf(4.6, 2.6, clampf(speed / 11.0, 0.0, 1.0))
	heading += steer * rate * delta
	var fwd := _forward_on(n)
	var tangent := Vector3.DOWN * GRAVITY
	tangent = tangent - n * tangent.dot(n)
	var along := tangent.dot(fwd)
	var pushing := Input.is_physical_key_pressed(KEY_W)
	var braking := Input.is_physical_key_pressed(KEY_S)
	if pushing and not braking:
		push_hold = minf(push_hold + delta, 1.6)
	else:
		push_hold = maxf(push_hold - delta * 0.7, 0.0)
	var effort := clampf(push_hold / 1.25, 0.0, 1.0)
	if pushing and not braking:
		var push_cap := lerpf(CRUISE, PUSH_TOP, effort)
		var push := lerpf(5.5, 8.5, effort)
		if speed < push_cap:
			speed += push * delta
	var friction := 0.7 + speed * 0.045
	if pushing and not braking:
		friction *= lerpf(1.0, 0.2, effort)
	if slope > 0.08:
		# Flats keep their friction. On a bank, carving should hold speed.
		var downhill := maxf(along, 0.0)
		var uphill := minf(along, 0.0)
		speed += downhill * 0.8 * delta
		speed += uphill * 0.32 * delta
		speed += absf(steer) * slope * 4.0 * delta
		friction = 0.15
	else:
		speed += along * delta
	if braking:
		friction = 13.0
	var before_friction := speed
	speed -= friction * delta
	if speed < 0.0:
		# Friction stopping must not spin the rider around. Only a slope
		# that actually rolls them backward turns them to face downhill.
		if before_friction < 0.0:
			speed = -speed
			heading += PI
			fwd = _forward_on(n)
		else:
			speed = 0.0
	var cap := _speed_cap()
	if slope > 0.08:
		cap += 1.0
	speed = clampf(speed, 0.0, cap)
	velocity = fwd * speed - n * 0.35
	var space := Input.is_physical_key_pressed(KEY_SPACE)
	if space:
		charge = minf(charge + delta / 0.42, 1.0)
	elif _space_was and charge > 0.08:
		_jump(n)
	_space_was = space
	live_trick = ""


func _air_physics(delta: float) -> void:
	velocity.y -= GRAVITY * delta
	_apply_air_tricks(delta)
	_space_was = Input.is_physical_key_pressed(KEY_SPACE)
	live_trick = _skate_preview()


func _apply_air_tricks(delta: float) -> void:
	var yaw_in := _spin_axis()
	var kick := 0.0
	if Input.is_physical_key_pressed(KEY_Q) or Input.is_physical_key_pressed(KEY_LEFT):
		kick += 1.0
	if Input.is_physical_key_pressed(KEY_E) or Input.is_physical_key_pressed(KEY_RIGHT):
		kick -= 1.0
	var shove := 0.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		shove += 1.0
	spin_v = move_toward(spin_v, yaw_in * 6.2, (36.0 if absf(yaw_in) > 0.0 else 28.0) * delta)
	flip_v = move_toward(flip_v, kick * 13.5, (64.0 if absf(kick) > 0.0 else 36.0) * delta)
	shove_v = move_toward(shove_v, shove * 8.5, (48.0 if absf(shove) > 0.0 else 30.0) * delta)
	visual_yaw += spin_v * delta
	board_flip += flip_v * delta
	board_shove += shove_v * delta
	visual_pitch = 0.0
	visual_roll = 0.0


func _jump(n: Vector3) -> void:
	var boost := charge
	velocity += n * (4.0 + boost * 5.2)
	charge = 0.0
	stick_lock = 0.18
	airborne = true
	_jumped = true
	pop_t = 0.22
	_arm_air()
	jump_air = true
	takeoff_boost = boost


func _launch_from_lip() -> void:
	if _jumped:
		return
	var rising := velocity.y > 1.6
	var boost := 0.0
	if charge > 0.12 and rising:
		boost = charge
		velocity += last_normal * (2.4 * charge)
		charge = 0.0
		pop_t = 0.16
	if rising or boost > 0.0:
		stick_lock = 0.2
	_arm_air()
	takeoff_boost = boost


func _forward_on(n: Vector3) -> Vector3:
	var flat := Vector3(-sin(heading), 0.0, -cos(heading))
	var fwd := flat - n * flat.dot(n)
	if fwd.length_squared() < 0.0004:
		return flat
	return fwd.normalized()


func _resolve_landing(hung: float) -> void:
	_match_speed()
	if state == State.CRASH:
		return
	_score_air(hung)
	if state != State.CRASH:
		land_blend = 0.85
		spin_v = 0.0
		pitch_v = 0.0
		roll_v = 0.0


func _score_air(hung: float) -> void:
	if _period_error(board_flip, TAU) > 1.0 or _period_error(board_shove, PI) > 0.9:
		crash("WASTED")
		return
	var names := PackedStringArray()
	if board_flip > 4.8:
		names.append("Kickflip")
	elif board_flip < -4.8:
		names.append("Heelflip")
	if absf(board_shove) > 2.3:
		names.append("Shove-it")
	if absf(visual_yaw) > 2.3:
		names.append("180")
	if names.is_empty():
		if hung > 0.35:
			_add_score(int(hung * 40.0), "Ollie", false)
		return
	var label := " ".join(names)
	var base := 90 + names.size() * 110 + int(maxf(hung - 0.3, 0.0) * 30.0)
	_add_score(base, label, false)


func _skate_preview() -> String:
	var names := PackedStringArray()
	if board_flip > 2.0:
		names.append("Kickflip")
	elif board_flip < -2.0:
		names.append("Heelflip")
	if absf(board_shove) > 1.1:
		names.append("Shove-it")
	if absf(visual_yaw) > 1.1:
		names.append("180")
	if names.is_empty():
		return ""
	return " ".join(names)


func _match_speed() -> void:
	var n := last_normal
	if is_on_floor():
		var fn := get_floor_normal()
		if fn.length_squared() > 0.1:
			n = fn
	var tangential := velocity - n * velocity.dot(n)
	speed = clampf(tangential.length(), 0.0, _speed_cap())
	var flat := Vector3(tangential.x, 0.0, tangential.z)
	if flat.length() > 0.45:
		heading = atan2(-flat.x, -flat.z)


func _add_score(amount: int, label: String, breaks_line: bool) -> void:
	if amount <= 0 or state == State.CRASH:
		return
	var factor := _repeat_factor(label)
	var mult := 1.0 if breaks_line else line_mult
	var gained := int(round(float(amount) * factor * mult))
	if gained <= 0:
		return
	points += gained
	if breaks_line:
		combo = 0
		line_mult = 1.0
	else:
		combo += 1
		line_mult = minf(1.0 + 0.25 * float(combo), 2.5)
	trick_history.append(label)
	while trick_history.size() > 3:
		trick_history.pop_front()
	banner = "%s   +%d" % [label, gained]
	banner_ttl = 1.8


func _repeat_factor(label: String) -> float:
	var seen := 0
	for past in trick_history:
		if past == label:
			seen += 1
	if seen >= 2:
		return 0.4
	if seen == 1:
		return 0.7
	return 1.0


func _yaw_error() -> float:
	return _period_error(visual_yaw, PI)


func _pitch_error() -> float:
	return _period_error(visual_pitch, TAU)


func _roll_error() -> float:
	return _period_error(visual_roll, TAU)


func _period_error(angle: float, period: float) -> float:
	var wrapped := fposmod(angle, period)
	return minf(wrapped, period - wrapped)


func _signed_error(angle: float, period: float) -> float:
	var wrapped := fposmod(angle, period)
	if wrapped > period * 0.5:
		wrapped -= period
	return wrapped


func _ease_period(angle: float, period: float, delta: float, rate: float) -> float:
	var err := _signed_error(angle, period)
	var target := angle - err
	return lerpf(angle, target, 1.0 - exp(-rate * delta))


func _halves(accum: float) -> int:
	if accum < 2.15:
		return 0
	return int(round(accum / PI))


func _full_turns(accum: float) -> int:
	if accum < 4.3:
		return 0
	return maxi(int(round(accum / TAU)), 0)


func _trick_name(halves: int, flips: int, rolls: int) -> String:
	var bits := PackedStringArray()
	if halves > 0:
		bits.append(str(halves * 180))
	if flips > 0:
		var word := "Backflip" if back_flip else "Frontflip"
		if flips == 1:
			bits.append(word)
		else:
			bits.append("%s x%d" % [word, flips])
	if rolls > 0:
		bits.append("Roll" if rolls == 1 else "Roll x%d" % rolls)
	if grab_time >= 0.2 and grab_name != "":
		bits.append(grab_name)
	if bits.is_empty():
		return "Air"
	return " ".join(bits)


func _preview_name() -> String:
	if spin_accum < 0.45 and flip_accum < 0.45 and roll_accum < 0.45 and grab_name == "":
		return ""
	return _trick_name(_halves(spin_accum), _full_turns(flip_accum), _full_turns(roll_accum))


func _arm_air() -> void:
	visual_pitch = 0.0
	visual_roll = 0.0
	visual_yaw = 0.0
	board_flip = 0.0
	board_shove = 0.0
	spin_v = 0.0
	flip_v = 0.0
	shove_v = 0.0
	pitch_v = 0.0
	roll_v = 0.0
	spin_accum = 0.0
	flip_accum = 0.0
	roll_accum = 0.0
	grab_name = ""
	grab_time = 0.0
	off_axis = false
	back_flip = false
	lip_time = 0.0
	land_blend = 0.0
	live_trick = ""


func _clear_air_rotation() -> void:
	_arm_air()
	takeoff_boost = 0.0


func _update_facing(delta: float) -> void:
	if visual == null:
		return
	var fwd := Vector3(-sin(heading), 0.0, -cos(heading))
	var n := Vector3.UP
	if state != State.CRASH and is_on_floor() and not airborne:
		var fn := get_floor_normal()
		if fn.dot(Vector3.UP) > 0.25:
			n = fn
	var blend := 1.0 - exp(-8.0 * delta)
	visual_normal = visual_normal.lerp(n, blend)
	if visual_normal.length_squared() < 0.01:
		visual_normal = Vector3.UP
	visual_normal = visual_normal.normalized()
	n = visual_normal
	if not airborne and not grinding and not sliding and state != State.CRASH:
		board_flip = _ease_period(board_flip, TAU, delta, 10.0)
		board_shove = _ease_period(board_shove, PI, delta, 10.0)
		visual_yaw = _ease_period(visual_yaw, TAU, delta, 8.0)
	var mesh_fwd := fwd - n * fwd.dot(n)
	if mesh_fwd.length_squared() < 0.0001:
		mesh_fwd = fwd
	mesh_fwd = mesh_fwd.normalized()
	cam_forward = fwd
	var y_axis := n
	var z_axis := -mesh_fwd
	var x_axis := y_axis.cross(z_axis).normalized()
	z_axis = x_axis.cross(y_axis).normalized()
	cam_right = x_axis
	var travel := Basis(x_axis, y_axis, z_axis)
	if state == State.CRASH:
		if ragdoll == null:
			var t := clampf(crash_spin, 0.0, 1.0)
			visual.basis = travel * Basis.from_euler(Vector3(0.8 * t, visual_yaw, 1.2 * t))
		return
	if not airborne and not grinding and not sliding and land_blend > 0.0:
		visual_yaw = _ease_period(visual_yaw, TAU, delta, 7.0)
		visual_pitch = _ease_period(visual_pitch, TAU, delta, 7.0)
		visual_roll = _ease_period(visual_roll, TAU, delta, 7.0)
		land_blend = maxf(land_blend - delta, 0.0)
	var steer := _steer_axis()
	var target := 0.0
	if grinding or sliding:
		target = 0.0
	elif not airborne and state == State.RIDE:
		target = -steer * clampf(speed / 7.0, 0.0, 1.0) * 0.22
	lean = lerpf(lean, target, 1.0 - exp(-6.0 * delta))
	var style := 0.0
	if grinding or sliding:
		style = 0.0
	elif not airborne:
		style = 0.22 * charge
	elif pop_t > 0.0:
		style = -0.4 * clampf(pop_t / 0.22, 0.0, 1.0)
	var face_yaw: float = visual_yaw
	if grinding or sliding:
		face_yaw += PI * 0.5
		if grinding:
			board_flip = 0.0
			board_shove = 0.0
			visual_yaw = 0.0
			face_yaw = PI * 0.5
	visual.basis = travel * Basis.from_euler(Vector3(style, face_yaw, lean))
	if board_pivot:
		board_pivot.rotation = Vector3(0.0, board_shove, board_flip)
	if rider:
		var stand_y := 0.11
		if not airborne:
			stand_y -= 0.07 * charge
		elif pop_t > 0.0:
			stand_y += 0.05 * clampf(pop_t / 0.22, 0.0, 1.0)
		rider.position.y = stand_y


func _update_anim() -> void:
	if state == State.CRASH:
		_play("die")
		return
	if state == State.WAIT:
		_play("skate-stand")
		return
	if sliding:
		roll_fast = false
		_play("crouch")
		return
	if grinding:
		roll_fast = false
		if grab_time > 0.05:
			_play("skate-grab")
		elif absf(board_flip) > 0.35 or absf(board_shove) > 0.35 or absf(visual_yaw) > 0.35:
			_play("skate-air")
		else:
			_play("skate-stand")
		return
	if airborne:
		if grab_time > 0.05:
			_play("skate-grab")
		elif pop_t > 0.1:
			_play("jump")
		else:
			_play("skate-air")
		return
	if charge > 0.05:
		_play("crouch")
		return
	var pushing := Input.is_physical_key_pressed(KEY_W)
	if roll_fast:
		if speed < 0.45 and not pushing:
			roll_fast = false
	elif speed > 1.35 or pushing:
		roll_fast = true
	if roll_fast:
		_play("skate")
	else:
		_play("skate-stand")


func _play(anim_name: String) -> void:
	if anim == null or _anim_name == anim_name:
		return
	if not anim.has_animation(anim_name):
		return
	_anim_name = anim_name
	anim.play(anim_name)


func _refresh_numbers() -> void:
	speed_mps = velocity.length() if airborne else speed


func _write_best() -> void:
	var cfg := ConfigFile.new()
	cfg.load("user://mini_park.cfg")
	var old := int(cfg.get_value("run", "best", 0))
	if points > old:
		cfg.set_value("run", "best", points)
		cfg.save("user://mini_park.cfg")
	saved_best = maxi(points, old)


func _steer_axis() -> float:
	var v := 0.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		v += 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		v -= 1.0
	return v


func _spin_axis() -> float:
	var v := 0.0
	if Input.is_physical_key_pressed(KEY_A):
		v += 1.0
	if Input.is_physical_key_pressed(KEY_D):
		v -= 1.0
	return v


func _roll_axis() -> float:
	var v := 0.0
	if Input.is_physical_key_pressed(KEY_LEFT):
		v += 1.0
	if Input.is_physical_key_pressed(KEY_RIGHT):
		v -= 1.0
	return v


func _lock_board() -> void:
	board_flip = 0.0
	board_shove = 0.0
	visual_yaw = 0.0
	flip_v = 0.0
	shove_v = 0.0
	spin_v = 0.0


func _above_solid(point: Vector3) -> Vector3:
	var world := get_world_3d()
	if world == null:
		return point
	var from := point + Vector3.UP * 2.2
	var to := point + Vector3.DOWN * 0.35
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	query.exclude = [self]
	var hit := world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return point
	var top: float = (hit["position"] as Vector3).y
	if top > point.y + 0.12:
		point.y = top + 0.08
	return point


func _begin_ragdoll() -> void:
	if ragdoll != null:
		return
	var body := RigidBody3D.new()
	body.name = "Ragdoll"
	body.collision_layer = 1
	body.collision_mask = 1
	body.mass = 16.0
	body.gravity_scale = 1.0
	body.linear_damp = 0.45
	body.angular_damp = 1.8
	body.can_sleep = true
	body.continuous_cd = true
	var phys := PhysicsMaterial.new()
	phys.friction = 1.1
	phys.bounce = 0.0
	body.physics_material_override = phys
	var shape := CapsuleShape3D.new()
	shape.radius = 0.2
	shape.height = 0.8
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = Vector3(0.0, 0.42, 0.0)
	body.add_child(col)
	var parent := get_parent()
	if parent == null:
		return
	parent.add_child(body)
	body.global_position = global_position + Vector3.UP * 0.15
	body.linear_velocity = velocity
	body.angular_velocity = Vector3(1.5, 0.4, -1.6)
	if visual != null:
		visual.reparent(body, true)
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	ragdoll = body
	crash_time = 0.0


func _step_ragdoll(_delta: float) -> void:
	if ragdoll == null or not is_instance_valid(ragdoll):
		return
	if ragdoll.global_position.y < -0.2:
		ragdoll.global_position = Vector3(ragdoll.global_position.x, 0.4, ragdoll.global_position.z)
		var vel := ragdoll.linear_velocity
		vel.y = 0.0
		ragdoll.linear_velocity = vel
	global_position = ragdoll.global_position
	velocity = ragdoll.linear_velocity


func _end_ragdoll() -> void:
	collision_layer = 1
	collision_mask = 1
	if visual != null and is_instance_valid(visual) and visual.get_parent() != self:
		visual.reparent(self, false)
		visual.position = Vector3.ZERO
		visual.rotation = Vector3.ZERO
	if ragdoll != null and is_instance_valid(ragdoll):
		ragdoll.queue_free()
	ragdoll = null


func _build_body() -> void:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.13
	shape.height = 0.62
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = Vector3(0, 0.32, 0)
	add_child(col)


func _build_visual() -> void:
	visual = Node3D.new()
	visual.name = "Visual"
	add_child(visual)
	var board_scene := load("res://assets/kenney-mini-skate/skateboard.glb") as PackedScene
	if board_scene:
		board_pivot = Node3D.new()
		board_pivot.name = "BoardPivot"
		visual.add_child(board_pivot)
		var board := board_scene.instantiate()
		board.name = "Board"
		board.rotation.y = PI
		board_pivot.add_child(board)
	var rider_scene := load("res://assets/kenney-mini-skate/character-skate-boy.glb") as PackedScene
	if rider_scene:
		rider = rider_scene.instantiate()
		rider.name = "Rider"
		rider.rotation.y = PI
		rider.position.y = 0.11
		visual.add_child(rider)
		_setup_anim()


func _setup_anim() -> void:
	anim = _find_anim(rider)
	if anim == null:
		return
	anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	for lib_name in anim.get_animation_library_list():
		var lib := anim.get_animation_library(lib_name)
		for anim_name in lib.get_animation_list():
			if anim_name in ["skate", "skate-stand", "skate-air", "skate-grab", "crouch", "idle"]:
				lib.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR


func _finish_ride_frame(delta: float) -> void:
	_refresh_numbers()
	_update_facing(delta)
	_update_anim()


func _try_start_grind() -> bool:
	# Walking, rolling, or a lip float never snaps onto a bar. The ollie
	# has to bring the board up to the rail.
	if rail_lock > 0.0 or not airborne or not jump_air:
		return false
	var best := 0.48
	var found := false
	var best_index := -1
	var best_line := PackedVector3Array()
	var best_along := 0.0
	var best_point := Vector3.ZERO
	var best_tangent := Vector3(0, 0, -1)
	for index in range(grind_lines.size()):
		var item = grind_lines[index]
		if not (item is PackedVector3Array):
			continue
		var line: PackedVector3Array = item
		var hit: Dictionary = _closest_on_line(line, global_position)
		if hit.is_empty():
			continue
		var horiz: float = float(hit["horiz"])
		var vert: float = float(hit["vert"])
		if horiz > best or vert < -0.16 or vert > 0.6:
			continue
		# A sideways ride-on is moving toward the bar. Only ignore a rail
		# when the rider is still off to the side and not closing on it.
		if horiz > 0.24 and float(hit.get("closing", 0.0)) < 0.2:
			continue
		best = horiz
		found = true
		best_index = index
		best_line = line
		best_along = float(hit["along"])
		best_point = hit["point"]
		best_tangent = hit["tangent"]
	if not found:
		return false
	grinding = true
	grind_index = best_index
	grind_line = best_line
	grind_along = best_along
	grind_balance = 0.0
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if flat.length() < 0.35:
		flat = Vector3(-sin(heading), 0.0, -cos(heading))
	grind_sign = -1.0 if flat.dot(best_tangent) < 0.0 else 1.0
	speed = clampf(maxf(speed, flat.length()), 2.2, _speed_cap())
	airborne = false
	jump_air = false
	air_time = 0.0
	charge = 0.0
	_space_was = false
	board_flip = 0.0
	board_shove = 0.0
	visual_yaw = 0.0
	spin_v = 0.0
	flip_v = 0.0
	shove_v = 0.0
	land_blend = 0.0
	_lock_board()
	global_position = _above_solid(best_point)
	live_trick = "Grind"
	return true


func _grind_slide(delta: float) -> void:
	if grind_line.size() < 2:
		grinding = false
		live_trick = ""
		return
	var steer := _steer_axis()
	grind_balance = move_toward(grind_balance, 0.0, 0.25 * delta)
	grind_balance += steer * 0.65 * delta
	if absf(grind_balance) > 1.0:
		_leave_rail(false)
		return
	if Input.is_physical_key_pressed(KEY_W):
		speed += 4.0 * delta
	if Input.is_physical_key_pressed(KEY_S):
		speed -= 7.0 * delta
	speed = clampf(speed, 1.6, _speed_cap())
	_lock_board()
	var space := Input.is_physical_key_pressed(KEY_SPACE)
	if space:
		charge = minf(charge + delta / 0.42, 1.0)
	elif _space_was and charge > 0.0:
		_space_was = false
		_leave_rail(true)
		return
	_space_was = space
	var length := _line_length(grind_line)
	var next_along := grind_along + grind_sign * speed * delta
	if next_along < 0.0 or next_along > length:
		var leftover := -next_along if next_along < 0.0 else next_along - length
		if not _continue_at_corner(next_along > length):
			grind_along = next_along
			_leave_rail(false)
			return
		var new_length := _line_length(grind_line)
		if grind_sign > 0.0:
			grind_along = minf(leftover, new_length)
		else:
			grind_along = maxf(new_length - leftover, 0.0)
	else:
		grind_along = next_along
	var tangent := _travel_tangent()
	global_position = _above_solid(_point_at(grind_line, grind_along))
	velocity = tangent * speed
	heading = atan2(-tangent.x, -tangent.z)
	airborne = false
	live_trick = _grind_label()
	if global_position.y < -4.0 or global_position.x < -34.0 or global_position.x > 33.0 or global_position.z < -29.0 or global_position.z > 31.0:
		crash("Left the park")


func _grind_label() -> String:
	var trick := _skate_preview()
	if trick == "":
		return "Grind"
	return "Grind %s" % trick


func _continue_at_corner(forward: bool) -> bool:
	if grind_line.size() < 2:
		return false
	var length := _line_length(grind_line)
	var end_point: Vector3 = grind_line[grind_line.size() - 1] if forward else grind_line[0]
	var travel := _tangent_at(grind_line, length if forward else 0.0)
	if not forward:
		travel = -travel
	travel.y = 0.0
	if travel.length_squared() < 0.0001:
		return false
	travel = travel.normalized()
	var best := -0.2
	var found := false
	var best_index := -1
	var best_sign := 1.0
	for index in range(grind_lines.size()):
		if index == grind_index:
			continue
		var item = grind_lines[index]
		if not (item is PackedVector3Array):
			continue
		var line: PackedVector3Array = item
		if line.size() < 2:
			continue
		for end_i in range(2):
			var at_start := end_i == 0
			var pt: Vector3 = line[0] if at_start else line[line.size() - 1]
			if absf(pt.y - end_point.y) > 0.45:
				continue
			var gap := Vector2(pt.x - end_point.x, pt.z - end_point.z).length()
			if gap > 0.9:
				continue
			var away := _tangent_at(line, 0.0 if at_start else _line_length(line))
			if not at_start:
				away = -away
			away.y = 0.0
			if away.length_squared() < 0.0001:
				continue
			away = away.normalized()
			var dot := travel.dot(away)
			if dot < -0.25:
				continue
			var score := dot + (0.9 - gap)
			if score > best:
				best = score
				found = true
				best_index = index
				best_sign = 1.0 if at_start else -1.0
	if not found:
		return false
	grind_index = best_index
	grind_line = grind_lines[best_index]
	grind_sign = best_sign
	return true


func _travel_tangent() -> Vector3:
	var length := _line_length(grind_line)
	var along := clampf(grind_along, 0.0, length)
	var ahead := clampf(along + grind_sign * 0.22, 0.0, length)
	var tangent := _tangent_at(grind_line, ahead) * grind_sign
	tangent.y = 0.0
	if tangent.length_squared() < 0.0001:
		tangent = _tangent_at(grind_line, along) * grind_sign
		tangent.y = 0.0
	if tangent.length_squared() < 0.0001:
		return Vector3(-sin(heading), 0.0, -cos(heading))
	return tangent.normalized()


func _leave_rail(ollie: bool) -> void:
	var length := _line_length(grind_line)
	var along := clampf(grind_along, 0.0, length)
	var point := _point_at(grind_line, along)
	var tangent := _tangent_at(grind_line, along) * grind_sign
	tangent.y = 0.0
	if tangent.length_squared() < 0.0001:
		tangent = Vector3(-sin(heading), 0.0, -cos(heading))
	tangent = tangent.normalized()
	var side := tangent.cross(Vector3.UP)
	grinding = false
	rail_lock = 0.45
	jump_air = ollie
	stick_lock = 0.2
	airborne = true
	air_time = 0.0
	live_trick = _skate_preview()
	# Pop from the current point on the bar, not the far end of the rail.
	global_position = point + tangent * 0.18
	if ollie:
		var boost := charge
		charge = 0.0
		global_position.y += 0.05
		velocity = tangent * speed + Vector3.UP * (4.0 + boost * 5.2)
		pop_t = 0.22
	else:
		charge = 0.0
		velocity = tangent * speed + Vector3.UP * 1.35
		if absf(grind_balance) > 1.0 and side.length_squared() > 0.01:
			velocity += side.normalized() * signf(grind_balance) * 1.5
	grind_balance = 0.0


func _closest_on_line(line: PackedVector3Array, pos: Vector3) -> Dictionary:
	var result: Dictionary = {}
	if line.size() < 2:
		return result
	var best := 999.0
	var walked := 0.0
	for i in range(line.size() - 1):
		var a: Vector3 = line[i]
		var b: Vector3 = line[i + 1]
		var ab := b - a
		var seg_len := ab.length()
		if seg_len < 0.0001:
			continue
		var t := clampf((pos - a).dot(ab) / (seg_len * seg_len), 0.0, 1.0)
		var point := a.lerp(b, t)
		var horiz := Vector2(pos.x - point.x, pos.z - point.z).length()
		if horiz < best:
			best = horiz
			var tangent := ab / seg_len
			var side := Vector3(-tangent.z, 0.0, tangent.x)
			var vel_flat := Vector3(velocity.x, 0.0, velocity.z)
			var to_rail := Vector3(point.x - pos.x, 0.0, point.z - pos.z)
			var closing := 0.0
			if to_rail.length_squared() > 0.0004 and vel_flat.length_squared() > 0.04:
				closing = vel_flat.normalized().dot(to_rail.normalized())
			result = {
				"horiz": horiz,
				"vert": pos.y - point.y,
				"along": walked + seg_len * t,
				"point": point,
				"tangent": tangent,
				"side_speed": vel_flat.dot(side),
				"closing": closing,
			}
		walked += seg_len
	return result


func _line_length(line: PackedVector3Array) -> float:
	var total := 0.0
	for i in range(line.size() - 1):
		total += line[i].distance_to(line[i + 1])
	return total


func _point_at(line: PackedVector3Array, dist: float) -> Vector3:
	var left := dist
	for i in range(line.size() - 1):
		var span := line[i].distance_to(line[i + 1])
		if left <= span or i == line.size() - 2:
			var t := 0.0 if span < 0.0001 else clampf(left / span, 0.0, 1.0)
			return line[i].lerp(line[i + 1], t)
		left -= span
	return line[line.size() - 1]


func _tangent_at(line: PackedVector3Array, dist: float) -> Vector3:
	var left := dist
	for i in range(line.size() - 1):
		var ab := line[i + 1] - line[i]
		var span := ab.length()
		if left <= span or i == line.size() - 2:
			if span < 0.0001:
				return Vector3(0, 0, -1)
			return ab / span
		left -= span
	return Vector3(0, 0, -1)


func _find_anim(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_anim(child)
		if found:
			return found
	return null


func _collect_slide_lines() -> void:
	slide_lines = []
	var root := get_parent()
	if root == null:
		return
	var scan: Node = root.get_node_or_null("Pieces")
	if scan == null:
		scan = root
	for child in scan.get_children():
		if not (child is Node3D) or not child.has_meta("piece_id"):
			continue
		var body := child as Node3D
		var locals: Array = _slide_local_edges(str(body.get_meta("piece_id")))
		for item in locals:
			if not (item is PackedVector3Array):
				continue
			var local: PackedVector3Array = item
			var world := PackedVector3Array()
			for point in local:
				world.append(body.global_transform * point)
			if world.size() >= 2 and world[0].distance_to(world[world.size() - 1]) > 0.15:
				slide_lines.append(world)


func _slide_local_edges(id: String) -> Array:
	if id == "floor-concrete":
		return _box_top_edges(0.5, 0.5, 0.2)
	if id == "obstacle-box":
		return _box_top_edges(0.5, 0.5, 0.22)
	if id == "ledge":
		return _box_top_edges(0.5, 0.5, 0.3)
	if id == "obstacle-box-grind":
		return _box_top_edges(0.26, 0.5, 0.4)
	var lip := _ramp_lip_edge(id)
	if lip.size() >= 2:
		return [lip]
	return []


func _box_top_edges(hx: float, hz: float, y: float) -> Array:
	return [
		PackedVector3Array([Vector3(-hx, y, -hz), Vector3(hx, y, -hz)]),
		PackedVector3Array([Vector3(hx, y, -hz), Vector3(hx, y, hz)]),
		PackedVector3Array([Vector3(hx, y, hz), Vector3(-hx, y, hz)]),
		PackedVector3Array([Vector3(-hx, y, hz), Vector3(-hx, y, -hz)]),
	]


func _ramp_lip_edge(id: String) -> PackedVector3Array:
	var y := 0.8
	var z := -0.5
	match id:
		"quarter", "bowl-side", "bowl-corner-inner", "bowl-corner-outer":
			# Just outside the coping, so the slide is not inside the mesh.
			y = 0.94
			z = -0.72
		"half-pipe-low", "bowl-side-low", "bowl-corner-inner-low", "bowl-corner-outer-low":
			y = 0.52
			z = -0.72
		"bank", "rail-slope-smooth":
			y = 0.8
			z = -1.0
		"ramp", "ramp-rail":
			y = 0.31
			z = -0.5
		_:
			return PackedVector3Array()
	return PackedVector3Array([Vector3(-0.5, y, z), Vector3(0.5, y, z)])


func _try_start_slide() -> bool:
	# An ollie plus Shift. Rolling into an edge never starts a slide.
	if sliding or grinding or slide_lock > 0.0 or rail_lock > 0.0:
		return false
	if not airborne or not jump_air:
		return false
	if not _shift_held():
		return false
	if slide_lines.is_empty():
		_collect_slide_lines()
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if flat.length() < 1.4:
		return false
	var dir := flat.normalized()
	var best := -1.0
	var found := false
	var best_index := -1
	var best_line := PackedVector3Array()
	var best_along := 0.0
	var best_point := Vector3.ZERO
	var best_tangent := Vector3(0, 0, -1)
	for index in range(slide_lines.size()):
		var item = slide_lines[index]
		if not (item is PackedVector3Array):
			continue
		var line: PackedVector3Array = item
		var hit: Dictionary = _closest_on_line(line, global_position)
		if hit.is_empty():
			continue
		var horiz: float = float(hit["horiz"])
		var vert: float = float(hit["vert"])
		if horiz > 0.5 or vert < -0.4 or vert > 0.7:
			continue
		var tangent: Vector3 = hit["tangent"]
		var align := absf(dir.dot(tangent))
		if align < 0.78:
			continue
		var score := align - horiz * 0.8
		if score <= best:
			continue
		best = score
		found = true
		best_index = index
		best_line = line
		best_along = float(hit["along"])
		best_point = hit["point"]
		best_tangent = tangent
	if not found:
		return false
	sliding = true
	slide_index = best_index
	slide_line = best_line
	slide_along = best_along
	slide_travel = 0.0
	slide_sign = -1.0 if flat.dot(best_tangent) < 0.0 else 1.0
	speed = clampf(maxf(speed, flat.length()), 2.2, _speed_cap())
	airborne = false
	jump_air = false
	air_time = 0.0
	charge = 0.0
	_space_was = false
	global_position = best_point
	velocity = best_tangent * slide_sign * speed
	heading = atan2(-velocity.x, -velocity.z)
	live_trick = "Slide"
	return true


func _edge_slide(delta: float) -> void:
	if slide_line.size() < 2:
		_leave_slide()
		return
	if not _shift_held():
		_leave_slide()
		return
	speed = clampf(speed, 2.2, _speed_cap())
	var length := _line_length(slide_line)
	var step := slide_sign * speed * delta
	var next_along := slide_along + step
	slide_travel += absf(step)
	if next_along < 0.0 or next_along > length:
		var leftover := -next_along if next_along < 0.0 else next_along - length
		if not _continue_slide(next_along > length):
			slide_along = clampf(next_along, 0.0, length)
			_leave_slide()
			return
		var new_length := _line_length(slide_line)
		if slide_sign > 0.0:
			slide_along = minf(leftover, new_length)
		else:
			slide_along = maxf(new_length - leftover, 0.0)
	else:
		slide_along = next_along
	var tangent := _slide_tangent()
	global_position = _point_at(slide_line, slide_along)
	velocity = tangent * speed
	heading = atan2(-tangent.x, -tangent.z)
	airborne = false
	live_trick = "Slide"
	if global_position.y < -4.0 or global_position.x < -34.0 or global_position.x > 33.0 or global_position.z < -29.0 or global_position.z > 31.0:
		crash("Left the park")


func _slide_tangent() -> Vector3:
	var length := _line_length(slide_line)
	var along := clampf(slide_along, 0.0, length)
	var tangent := _tangent_at(slide_line, along) * slide_sign
	tangent.y = 0.0
	if tangent.length_squared() < 0.0001:
		return Vector3(-sin(heading), 0.0, -cos(heading))
	return tangent.normalized()


func _continue_slide(forward: bool) -> bool:
	if slide_line.size() < 2:
		return false
	var length := _line_length(slide_line)
	var end_point: Vector3 = slide_line[slide_line.size() - 1] if forward else slide_line[0]
	var travel := _tangent_at(slide_line, length if forward else 0.0)
	if not forward:
		travel = -travel
	travel.y = 0.0
	if travel.length_squared() < 0.0001:
		return false
	travel = travel.normalized()
	var best := -0.05
	var found := false
	var best_index := -1
	var best_sign := 1.0
	for index in range(slide_lines.size()):
		if index == slide_index:
			continue
		var item = slide_lines[index]
		if not (item is PackedVector3Array):
			continue
		var line: PackedVector3Array = item
		if line.size() < 2:
			continue
		for end_i in range(2):
			var at_start := end_i == 0
			var pt: Vector3 = line[0] if at_start else line[line.size() - 1]
			if absf(pt.y - end_point.y) > 0.2:
				continue
			if Vector2(pt.x - end_point.x, pt.z - end_point.z).length() > 0.35:
				continue
			var away := _tangent_at(line, 0.0 if at_start else _line_length(line))
			if not at_start:
				away = -away
			away.y = 0.0
			if away.length_squared() < 0.0001:
				continue
			away = away.normalized()
			var dot := travel.dot(away)
			if dot < -0.05:
				continue
			var score := dot
			if score > best:
				best = score
				found = true
				best_index = index
				best_sign = 1.0 if at_start else -1.0
	if not found:
		return false
	slide_index = best_index
	slide_line = slide_lines[best_index]
	slide_sign = best_sign
	return true


func _leave_slide() -> void:
	var length := _line_length(slide_line)
	var along := clampf(slide_along, 0.0, maxf(length, 0.0))
	var point := global_position
	var tangent := Vector3(-sin(heading), 0.0, -cos(heading))
	if slide_line.size() >= 2:
		point = _point_at(slide_line, along)
		tangent = _tangent_at(slide_line, along) * slide_sign
		tangent.y = 0.0
		if tangent.length_squared() > 0.0001:
			tangent = tangent.normalized()
	var traveled := slide_travel
	sliding = false
	slide_lock = 0.4
	jump_air = false
	airborne = true
	air_time = 0.05
	stick_lock = 0.16
	charge = 0.0
	global_position = point + tangent * 0.2 + Vector3.UP * 0.12
	velocity = tangent * speed + Vector3.UP * 1.15
	if traveled > 0.45 and state == State.RIDE:
		_add_score(70, "Slide", false)
		live_trick = "Slide"
	else:
		live_trick = ""
