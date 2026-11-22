extends CharacterBody3D
## Arcade skier. On snow: carve, tuck, brake, charge a pop.
## In the air: spin, flip, roll, grab. Land near a rotation or it's a crash.

enum State { WAIT, RIDE, CRASH, DONE }

const GRAVITY := 30.0
const MAX_SPEED := 42.0
const HEADING_LIMIT := 1.05

var state: State = State.WAIT
var slope_hint := Vector3.UP
var spawn_pos := Vector3.ZERO
var course_start := Vector3.ZERO
var course_axis := Vector3.FORWARD
var course_len := 1.0

var heading := 0.0
var speed := 0.0
var charge := 0.0
var airborne := false
var air_time := 0.0
var stick_lock := 0.0
var spawn_grace := 0.5
var suppress_jump := 0.0
var takeoff_boost := 0.0
var chill := false
var lip_time := 0.0
var off_axis := false
var back_flip := false

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

var points := 0
var saved_best := 0
var allow_save := true
var combo := 0
var line_mult := 1.0
var trick_history: Array[String] = []
var banner := ""
var banner_ttl := 0.0
var live_trick := ""
var crash_reason := ""
var crash_spin := 0.0
var lean := 0.0
var cam_forward := Vector3(0, 0, 1)
var cam_right := Vector3(1, 0, 0)
var speed_mps := 0.0
var progress := 0.0
var last_normal := Vector3.UP

var grinding := false
var rail_lock := 0.0
var rail_pending := false
var pend_a := Vector3.ZERO
var pend_b := Vector3.ZERO
var grind_a := Vector3.ZERO
var grind_dir := Vector3.FORWARD
var grind_len := 1.0
var grind_dist := 0.0
var rail_score_acc := 0.0
var grind_spin := 0.0
var grind_halves := 0

var buttering := false
var butter_yaw := 0.0
var butter_cd := 0.0

var _space_was := false
var visual: Node3D
var spray: GPUParticles3D


func _ready() -> void:
	floor_max_angle = deg_to_rad(62.0)
	floor_snap_length = 0.22
	floor_stop_on_slope = false
	collision_layer = 1
	collision_mask = 1
	_build_body()
	_build_rider()
	_build_spray()


func begin() -> void:
	state = State.RIDE
	spawn_grace = 0.45
	speed = 16.0
	heading = 0.0
	airborne = false
	grinding = false
	charge = 0.0
	var down := _downhill(slope_hint)
	velocity = down * speed
	cam_forward = down
	last_normal = slope_hint


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
	charge = 0.0
	heading = 0.0
	grinding = false
	rail_pending = false
	buttering = false
	butter_yaw = 0.0
	butter_cd = 0.0
	global_position = spawn_pos
	_clear_air_rotation()
	begin()


func finish() -> void:
	if state != State.RIDE:
		return
	state = State.DONE
	_write_best()


func crash(reason: String) -> void:
	if state != State.RIDE:
		return
	state = State.CRASH
	crash_reason = reason
	crash_spin = 0.0
	combo = 0
	line_mult = 1.0
	grinding = false
	rail_pending = false
	buttering = false
	banner = reason
	banner_ttl = 3.0
	speed = minf(speed, 4.0)
	_write_best()


func try_rail(a: Vector3, b: Vector3) -> void:
	if grinding or rail_lock > 0.0 or state != State.RIDE or not airborne:
		return
	if velocity.dot(slope_hint) > 10.0:
		return
	rail_pending = true
	pend_a = a
	pend_b = b


func _physics_process(delta: float) -> void:
	_decay_timers(delta)
	if state == State.WAIT:
		global_position = spawn_pos
		velocity = Vector3.ZERO
		_update_facing(delta)
		return
	if state == State.CRASH:
		velocity += Vector3.DOWN * GRAVITY * delta
		velocity.x = move_toward(velocity.x, 0.0, 14.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 14.0 * delta)
		move_and_slide()
		_update_facing(delta)
		_refresh_numbers()
		return
	if grinding:
		_grind_physics(delta)
		_refresh_numbers()
		_update_facing(delta)
		return

	var grounded := (not airborne) and is_on_floor() and stick_lock <= 0.0
	if grounded:
		if state == State.DONE:
			_coast_physics(delta)
		else:
			_ground_physics(delta)
	else:
		if not airborne and state == State.RIDE:
			_launch_from_lip()
		airborne = true
		air_time += delta
		_air_physics(delta)

	move_and_slide()
	if state == State.RIDE:
		_hit_hazards()

	if rail_pending and state == State.RIDE:
		rail_pending = false
		_start_grind(pend_a, pend_b)
		_refresh_numbers()
		_update_facing(delta)
		return

	var touched := is_on_floor() and stick_lock <= 0.0
	if airborne and touched:
		airborne = false
		var hung := air_time
		air_time = 0.0
		if hung > 0.22 and state != State.CRASH:
			_resolve_landing()
		else:
			_clear_air_rotation()
	elif not touched and not airborne and state == State.RIDE and spawn_grace <= 0.0:
		_launch_from_lip()
		airborne = true

	_bounds()
	_refresh_numbers()
	_update_facing(delta)
	if spray:
		spray.emitting = (not airborne) and (not grinding) and speed > 10.0 and state == State.RIDE
	var blob := visual.get_node_or_null("Shadow")
	if blob:
		blob.visible = (not airborne) and (not grinding) and state != State.CRASH


func _ground_physics(delta: float) -> void:
	var floor_n := get_floor_normal()
	if floor_n.length_squared() < 0.01:
		floor_n = slope_hint
	last_normal = floor_n
	var axes := _axes()
	var down: Vector3 = axes[0]
	var right: Vector3 = axes[1]
	var carve := _carve_axis()
	if not buttering:
		var rate := 1.45 + clampf(speed, 0.0, 32.0) * 0.03
		heading = clampf(heading + carve * rate * delta, -HEADING_LIMIT, HEADING_LIMIT)
	var wish := _heading_dir(down, right)
	var along := clampf(down.dot(wish), -1.0, 1.0)
	var slope_sin := sqrt(maxf(1.0 - slope_hint.y * slope_hint.y, 0.0))
	var pull := 36.0 * slope_sin
	var tuck := _tuck_held()
	var brake := Input.is_physical_key_pressed(KEY_S)
	var drag := 0.0105
	if tuck:
		drag = 0.004
	if brake:
		drag = 0.06
	speed += pull * along * delta
	speed -= drag * speed * speed * delta
	speed -= absf(carve) * 2.2 * delta
	var face_down := _downhill(floor_n)
	var oppose := -face_down.dot(wish)
	if oppose > 0.25:
		speed -= 9.0 * oppose * delta
	speed = clampf(speed, 0.0, MAX_SPEED)
	velocity = wish * speed - floor_n * 3.0

	if suppress_jump <= 0.0:
		var space := Input.is_physical_key_pressed(KEY_SPACE)
		if space:
			charge = minf(charge + delta / 0.4, 1.0)
		elif _space_was and charge > 0.08:
			_jump(floor_n)
		_space_was = space
	_butter(delta, carve)
	live_trick = ""


func _coast_physics(delta: float) -> void:
	var floor_n := get_floor_normal()
	last_normal = floor_n
	var down := _downhill(slope_hint)
	speed = move_toward(speed, 0.0, 14.0 * delta)
	velocity = down * speed - floor_n * 3.0


func _air_physics(delta: float) -> void:
	velocity.y -= GRAVITY * delta
	var spin_in := _spin_axis()
	var pitch_in := 0.0
	if _tuck_held():
		pitch_in -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		pitch_in += 1.0
	var roll_in := _roll_axis()
	var scale := (0.5 if chill else 1.0) * (1.0 + takeoff_boost * 0.95)
	var target := 8.4 * scale
	var push := 52.0 * scale
	var damp := 26.0
	spin_v = move_toward(spin_v, spin_in * target, (push if absf(spin_in) > 0.0 else damp) * delta)
	pitch_v = move_toward(pitch_v, pitch_in * target * 0.92, (push if absf(pitch_in) > 0.0 else damp) * delta)
	roll_v = move_toward(roll_v, roll_in * target, (push if absf(roll_in) > 0.0 else damp) * delta)
	visual_yaw += spin_v * delta
	visual_pitch += pitch_v * delta
	visual_roll += roll_v * delta
	spin_accum += absf(spin_v) * delta
	flip_accum += absf(pitch_v) * delta
	roll_accum += absf(roll_v) * delta
	lip_time += delta
	if lip_time < 0.25 and absf(spin_in) > 0.0 and absf(pitch_in) > 0.0:
		off_axis = true
		back_flip = pitch_in > 0.0
	if Input.is_physical_key_pressed(KEY_Q) or Input.is_physical_key_pressed(KEY_SHIFT):
		grab_name = "Mute"
		grab_time += delta
	elif Input.is_physical_key_pressed(KEY_E):
		grab_name = "Indy"
		grab_time += delta
	var axes := _axes()
	var right: Vector3 = axes[1]
	velocity += right * spin_in * 3.5 * delta
	live_trick = _preview_name()


func _grind_physics(delta: float) -> void:
	var spin_in := _spin_axis()
	grind_spin += spin_in * 3.4 * delta
	var halves := 0
	if absf(grind_spin) > 2.2:
		halves = int(round(absf(grind_spin) / PI))
	if halves > grind_halves:
		grind_halves = halves
	rail_score_acc += 220.0 * delta
	speed = clampf(speed, 11.0, 26.0)
	grind_dist += speed * delta
	var space := Input.is_physical_key_pressed(KEY_SPACE)
	var pop := space and not _space_was
	_space_was = space
	if pop or grind_dist >= grind_len - 0.15:
		_leave_rail(pop)
		return
	global_position = grind_a + grind_dir * grind_dist + slope_hint * 0.08
	live_trick = "Rail"


func _jump(n: Vector3) -> void:
	var boost := charge
	velocity += n * (7.5 + boost * 12.0)
	charge = 0.0
	stick_lock = 0.18
	airborne = true
	_arm_air()
	takeoff_boost = boost


func _launch_from_lip() -> void:
	var boost := 0.0
	if charge > 0.12:
		boost = charge
		velocity += last_normal * (8.5 * charge)
		charge = 0.0
	_arm_air()
	takeoff_boost = boost


func _arm_air() -> void:
	visual_pitch = 0.0
	visual_roll = 0.0
	visual_yaw = 0.0
	spin_v = 0.0
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
	chill = Input.is_physical_key_pressed(KEY_DOWN)
	live_trick = ""


func _resolve_landing() -> void:
	_match_speed_to_velocity()
	if state == State.CRASH:
		return
	_score_air(false)
	_clear_air_rotation()


func _score_air(forgiving: bool) -> bool:
	var halves := _halves(spin_accum)
	var flips := _full_turns(flip_accum)
	var rolls := _full_turns(roll_accum)
	var named := halves > 0 or flips > 0 or rolls > 0 or grab_time >= 0.25
	if not named:
		if air_time > 0.45:
			_add_score(int(air_time * 45.0), "Air", false)
		return false
	if not _aligned(forgiving):
		crash("Missed the landing")
		return true
	var spins_f := float(halves) * 0.5
	var base := 0
	if halves == 1:
		base += 160
	elif halves >= 2:
		base += int(280.0 * spins_f * spins_f)
	if flips > 0:
		base += 380 * flips * flips
	if rolls > 0 and halves >= 2:
		base = int(float(base) * 1.2)
	elif rolls > 0:
		base += 300 * rolls
	if halves >= 2 and flips > 0:
		base = int(float(base) * (1.4 if off_axis else 1.12))
	if grab_time >= 0.85:
		base = int(float(base) * 1.45)
	elif grab_time >= 0.25:
		base = int(float(base) * 1.22)
	base += int(maxf(air_time - 0.3, 0.0) * 55.0)
	var clean := _aligned_strict()
	if clean:
		base = int(float(base) * 1.15) + 200
	else:
		base = int(float(base) * 0.55)
	_add_score(base, _trick_name(halves, flips, rolls), not clean)
	return false


func _start_grind(a: Vector3, b: Vector3) -> void:
	if grinding or state != State.RIDE:
		return
	var seg := b - a
	var len := seg.length()
	if len < 1.0:
		return
	var dir := seg / len
	if velocity.dot(dir) < 0.0:
		dir = -dir
		var swap := a
		a = b
		b = swap
	if air_time > 0.22:
		if _score_air(true):
			return
	airborne = false
	air_time = 0.0
	grinding = true
	grind_a = a
	grind_dir = dir
	grind_len = len
	grind_dist = clampf((global_position - a).dot(dir), 0.0, len)
	rail_score_acc = 0.0
	grind_spin = 0.0
	grind_halves = 0
	_clear_air_rotation()
	_match_speed_to_velocity()
	speed = clampf(maxf(speed, 12.0), 12.0, 26.0)


func _leave_rail(pop: bool) -> void:
	var pts := int(rail_score_acc) + grind_halves * 260
	grinding = false
	rail_lock = 0.45
	stick_lock = 0.12
	airborne = true
	velocity = grind_dir * maxf(speed, 12.0) + slope_hint * (9.0 if pop else 3.2)
	_arm_air()
	takeoff_boost = 0.45 if pop else 0.0
	if pts > 60:
		_add_score(pts, "Rail", false)


func _butter(delta: float, carve: float) -> void:
	var held := Input.is_physical_key_pressed(KEY_B)
	if held and not buttering and butter_cd <= 0.0 and speed > 7.0:
		buttering = true
		butter_yaw = 0.0
	if not buttering:
		return
	butter_yaw += carve * 5.2 * delta
	speed = maxf(speed - 6.0 * delta, 0.0)
	if not held or absf(butter_yaw) >= TAU:
		var spun := absf(butter_yaw)
		buttering = false
		butter_cd = 0.5
		butter_yaw = 0.0
		if spun >= 5.2:
			_add_score(460, "Butter 360", false)
		elif spun >= 2.15:
			_add_score(190, "Butter 180", false)


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


func score_gate() -> void:
	_add_score(150, "Gate", false)


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


func _aligned(forgiving: bool) -> bool:
	var lim := 0.85 if forgiving else 0.62
	return _yaw_error() < lim and _pitch_error() < lim and _roll_error() < lim


func _aligned_strict() -> bool:
	return _yaw_error() < 0.28 and _pitch_error() < 0.3 and _roll_error() < 0.3


func _yaw_error() -> float:
	# Feet-forward or switch both count.
	return _period_error(visual_yaw, PI)


func _pitch_error() -> float:
	return _period_error(visual_pitch, TAU)


func _roll_error() -> float:
	return _period_error(visual_roll, TAU)


func _period_error(angle: float, period: float) -> float:
	var wrapped := fposmod(angle, period)
	return minf(wrapped, period - wrapped)


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
	if halves >= 2 and flips > 0 and off_axis:
		var kind := "Cork" if back_flip else "Bio"
		bits.append("%s %d" % [kind, halves * 180])
	else:
		if halves > 0:
			bits.append(str(halves * 180))
		if flips > 0:
			var word := "Backflip" if back_flip else "Frontflip"
			if flips == 1:
				bits.append(word)
			else:
				bits.append("%s x%d" % [word, flips])
	if rolls > 0 and halves >= 2:
		bits.append("Flat")
	elif rolls > 0:
		bits.append("Sideflip" if rolls == 1 else "Sideflip x%d" % rolls)
	if grab_time >= 0.2 and grab_name != "":
		bits.append(grab_name)
	if bits.is_empty():
		return "Air"
	return " ".join(bits)


func _preview_name() -> String:
	if spin_accum < 0.45 and flip_accum < 0.45 and roll_accum < 0.45 and grab_name == "":
		return ""
	return _trick_name(_halves(spin_accum), _full_turns(flip_accum), _full_turns(roll_accum))


func _match_speed_to_velocity() -> void:
	var n := last_normal
	if is_on_floor():
		var fn := get_floor_normal()
		if fn.length_squared() > 0.1:
			n = fn
	var tangential := velocity - n * velocity.dot(n)
	speed = clampf(tangential.length(), 0.0, MAX_SPEED)
	if state == State.CRASH:
		speed = minf(speed, 3.0)
		return
	if speed < 7.0 and state == State.RIDE:
		speed = 7.0
	var axes := _axes()
	var down: Vector3 = axes[0]
	var right: Vector3 = axes[1]
	if tangential.length() > 1.0:
		var flat := tangential.normalized()
		heading = clampf(atan2(right.dot(flat), down.dot(flat)), -HEADING_LIMIT, HEADING_LIMIT)


func _clear_air_rotation() -> void:
	visual_yaw = 0.0
	visual_pitch = 0.0
	visual_roll = 0.0
	spin_v = 0.0
	pitch_v = 0.0
	roll_v = 0.0
	spin_accum = 0.0
	flip_accum = 0.0
	roll_accum = 0.0
	grab_name = ""
	grab_time = 0.0


func _hit_hazards() -> void:
	if spawn_grace > 0.0:
		return
	for i in get_slide_collision_count():
		var hit := get_slide_collision(i)
		if hit.get_normal().dot(Vector3.UP) > 0.5:
			continue
		var other := hit.get_collider()
		if other != null and other.is_in_group("hazard"):
			crash("Hit a tree")
			return
		speed *= 0.9


func _bounds() -> void:
	if state != State.RIDE or spawn_grace > 0.0:
		return
	if absf(global_position.x) > 38.0 or global_position.y < -190.0:
		crash("Left the piste")


func _update_facing(delta: float) -> void:
	var axes := _axes()
	var down: Vector3 = axes[0]
	var right: Vector3 = axes[1]
	var fwd := _heading_dir(down, right)
	cam_forward = fwd
	cam_right = right
	var mesh_n := slope_hint
	if state != State.CRASH and is_on_floor() and not airborne and not grinding:
		var fn := get_floor_normal()
		if fn.dot(Vector3.UP) > 0.3:
			mesh_n = fn
	var mesh_fwd := fwd - mesh_n * fwd.dot(mesh_n)
	if mesh_fwd.length_squared() < 0.0001:
		mesh_fwd = fwd
	mesh_fwd = mesh_fwd.normalized()
	var mesh_right := mesh_n.cross(mesh_fwd).normalized()
	var travel := Basis(mesh_right, mesh_n, -mesh_fwd)
	if state == State.CRASH:
		var t := clampf(crash_spin, 0.0, 1.0)
		visual.basis = travel * Basis.from_euler(Vector3(0.7 * t, 0.2 * t, 1.15 * t))
		return
	if airborne or grinding:
		lean = lerpf(lean, 0.0, 1.0 - exp(-6.0 * delta))
		visual.basis = travel * Basis.from_euler(Vector3(visual_pitch, visual_yaw, visual_roll))
		return
	var carve := _carve_axis()
	var target := -carve * clampf(speed / 28.0, 0.0, 1.0) * 0.58
	lean = lerpf(lean, target, 1.0 - exp(-9.0 * delta))
	var tuck_pitch := 0.28 if _tuck_held() else 0.05
	visual.basis = travel * Basis.from_euler(Vector3(tuck_pitch, 0.0, lean))
	if buttering:
		visual.basis = visual.basis * Basis.from_euler(Vector3(0.4, butter_yaw, 0.0))


func _refresh_numbers() -> void:
	speed_mps = velocity.length() if (airborne or grinding) else speed
	if course_len > 1.0:
		progress = clampf((global_position - course_start).dot(course_axis) / course_len, 0.0, 1.0)


func _decay_timers(delta: float) -> void:
	banner_ttl = maxf(banner_ttl - delta, 0.0)
	butter_cd = maxf(butter_cd - delta, 0.0)
	stick_lock = maxf(stick_lock - delta, 0.0)
	spawn_grace = maxf(spawn_grace - delta, 0.0)
	rail_lock = maxf(rail_lock - delta, 0.0)
	suppress_jump = maxf(suppress_jump - delta, 0.0)
	if state == State.CRASH:
		crash_spin += delta


func _write_best() -> void:
	if not allow_save:
		return
	var cfg := ConfigFile.new()
	cfg.load("user://fall_line.cfg")
	var old := int(cfg.get_value("run", "best", 0))
	if points > old:
		cfg.set_value("run", "best", points)
		cfg.save("user://fall_line.cfg")
	saved_best = maxi(points, old)


func _axes() -> Array:
	var n := slope_hint.normalized()
	var down := _downhill(n)
	var right := n.cross(down).normalized()
	return [down, right, n]


func _heading_dir(down: Vector3, right: Vector3) -> Vector3:
	var wish := down * cos(heading) + right * sin(heading)
	var n := slope_hint.normalized()
	wish = wish - n * wish.dot(n)
	if wish.length_squared() < 0.0001:
		return down
	return wish.normalized()


func _downhill(n: Vector3) -> Vector3:
	var d := Vector3.DOWN - n * Vector3.DOWN.dot(n)
	if d.length_squared() < 0.0004:
		return Vector3(0, -0.24, 0.97)
	return d.normalized()


func _carve_axis() -> float:
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


func _tuck_held() -> bool:
	return Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)


func _build_body() -> void:
	var shape := CapsuleShape3D.new()
	shape.height = 1.65
	shape.radius = 0.32
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = Vector3(0, 0.84, 0)
	add_child(col)


func _build_rider() -> void:
	visual = Node3D.new()
	visual.name = "Visual"
	visual.scale = Vector3(1.2, 1.2, 1.2)
	add_child(visual)
	var blob := MeshInstance3D.new()
	blob.name = "Shadow"
	var quad := QuadMesh.new()
	quad.size = Vector2(0.85, 1.35)
	blob.mesh = quad
	blob.rotation.x = -PI * 0.5
	blob.position = Vector3(0, 0.04, 0.05)
	var shade := StandardMaterial3D.new()
	shade.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shade.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shade.albedo_color = Color(0.15, 0.2, 0.28, 0.28)
	shade.cull_mode = BaseMaterial3D.CULL_DISABLED
	blob.material_override = shade
	visual.add_child(blob)
	_box(visual, Vector3(0.11, 0.035, 1.55), Vector3(-0.16, 0.05, 0.05), Color(0.12, 0.12, 0.13))
	_box(visual, Vector3(0.11, 0.035, 1.55), Vector3(0.16, 0.05, 0.05), Color(0.12, 0.12, 0.13))
	_box(visual, Vector3(0.11, 0.02, 0.45), Vector3(-0.16, 0.07, -0.55), Color(0.86, 0.24, 0.18))
	_box(visual, Vector3(0.11, 0.02, 0.45), Vector3(0.16, 0.07, -0.55), Color(0.86, 0.24, 0.18))
	_box(visual, Vector3(0.28, 0.22, 0.34), Vector3(0, 0.28, 0.05), Color(0.16, 0.2, 0.28))
	_box(visual, Vector3(0.42, 0.48, 0.28), Vector3(0, 0.78, 0.02), Color(0.84, 0.22, 0.16))
	_box(visual, Vector3(0.16, 0.38, 0.16), Vector3(-0.28, 0.72, 0.0), Color(0.84, 0.22, 0.16))
	_box(visual, Vector3(0.16, 0.38, 0.16), Vector3(0.28, 0.72, 0.0), Color(0.84, 0.22, 0.16))
	_box(visual, Vector3(0.22, 0.2, 0.22), Vector3(0, 1.18, 0.0), Color(0.90, 0.76, 0.64))
	_box(visual, Vector3(0.24, 0.1, 0.16), Vector3(0, 1.2, -0.08), Color(0.08, 0.1, 0.14))
	_pole(visual, -0.34)
	_pole(visual, 0.34)


func _pole(parent: Node3D, x: float) -> void:
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.015
	cyl.bottom_radius = 0.015
	cyl.height = 1.15
	mesh.mesh = cyl
	mesh.position = Vector3(x, 0.7, 0.05)
	mesh.rotation_degrees = Vector3(18, 0, 0)
	mesh.material_override = _mat(Color(0.25, 0.27, 0.3), 0.4)
	parent.add_child(mesh)


func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = pos
	mesh.material_override = _mat(color, 0.55)
	parent.add_child(mesh)


func _build_spray() -> void:
	spray = GPUParticles3D.new()
	spray.name = "Spray"
	spray.amount = 48
	spray.lifetime = 0.45
	spray.position = Vector3(0, 0.15, 0.7)
	spray.emitting = false
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 0.6, 1)
	mat.spread = 28.0
	mat.initial_velocity_min = 1.5
	mat.initial_velocity_max = 4.5
	mat.gravity = Vector3(0, -6, 0)
	mat.scale_min = 0.04
	mat.scale_max = 0.12
	mat.color = Color(0.95, 0.97, 1.0, 0.85)
	spray.process_material = mat
	var quad := QuadMesh.new()
	quad.size = Vector2(0.18, 0.18)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.albedo_color = Color(1, 1, 1, 0.75)
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = sm
	spray.draw_pass_1 = quad
	add_child(spray)


func _mat(color: Color, rough: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = rough
	return mat
