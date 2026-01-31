extends CharacterBody2D

var gravity: float = 900.0

# --- Spit attack ---
@export var spit_range: float = 200.0
@export var projectile_scene: PackedScene
@export var attack_anim_name: StringName = &"attack" # or &"spit"
@export var spit_release_frame: int = 3

# --- Patrol behavior ---
@export var turn_on_ledge: bool = true

# --- Line of sight ---
@export var los_max_distance: float = 260.0
@export var los_y_offset: float = -6.0 # eye/mouth height

# --- Ground aiming (raycast down from player) ---
@export var ground_mask: int = 1 # set to the physics layer mask of ground/walls
@export var ground_raycast_depth: float = 600.0

@export var debug_ai: bool = false

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var wall_check: RayCast2D = $WallCheck
@onready var ground_check: RayCast2D = $GroundCheck if has_node("GroundCheck") else null
@onready var sight_ray: RayCast2D = $SightRay
@onready var health_bar: ProgressBar = $HealthBar
@onready var platform: CharacterBody2D = $Platform if has_node("Platform") else null

var dir: int = 1
var can_spit: bool = true
var is_attacking: bool = false
var player: Node2D = null
var current_hp: float = ZombieConfig.MAX_HP

func _ready() -> void:
	_face_dir(dir)
	_find_player()
	sight_ray.enabled = true
	current_hp = ZombieConfig.MAX_HP
	health_bar.max_value = ZombieConfig.MAX_HP
	health_bar.value = current_hp

func _physics_process(delta: float) -> void:
	# Gravity
	if not is_on_floor():
		velocity.y += gravity * delta
	else:
		velocity.y = 0.0

	# プラットフォームの速度を同期（プレイヤーがゾンビの上に乗れるように）
	if platform:
		platform.velocity = velocity

	# Re-acquire player if it spawns later
	if player == null:
		_find_player()

	# If attacking, only keep attacking while player stays in sight
	if is_attacking:
		if player == null or not _player_in_sight():
			is_attacking = false
			anim.stop()
			if debug_ai:
				print("Zombie AI | Lost sight -> abort attack")
		else:
			velocity.x = 0.0
			move_and_slide()
			return

	# If no player, just patrol
	if player == null:
		_patrol()
		move_and_slide()
		if is_on_wall():
			_turn_around()
		_update_animation()
		return

	var distance: float = global_position.distance_to(player.global_position)
	var in_range: bool = distance <= spit_range
	var in_sight: bool = _player_in_sight()

	if debug_ai:
		print("Zombie AI | dist=", snapped(distance, 0.1),
			" in_range=", in_range, " in_sight=", in_sight,
			" can_spit=", can_spit)

	# Attack only if in range + visible
	if in_range and in_sight and can_spit:
		_start_spit_attack()
	else:
		# Not visible -> resume patrol immediately
		_patrol()

	move_and_slide()

	# Guaranteed wall turn
	if is_on_wall() and not is_attacking:
		_turn_around()

	_update_animation()

func _find_player() -> void:
	var p := get_tree().get_first_node_in_group("player")
	if p is Node2D:
		player = p as Node2D

# -----------------------------
# Line of sight (SightRay)
# -----------------------------
func _player_in_sight() -> bool:
	if player == null:
		return false

	var origin := global_position + Vector2(0.0, los_y_offset)
	var to_player := player.global_position - origin

	if to_player.length() > los_max_distance:
		return false

	sight_ray.global_position = origin
	sight_ray.target_position = to_player
	sight_ray.force_raycast_update()

	if not sight_ray.is_colliding():
		return false

	return sight_ray.get_collider() == player

# -----------------------------
# Patrol movement
# -----------------------------
func _patrol() -> void:
	velocity.x = float(dir) * ZombieConfig.MOVE_SPEED

	wall_check.force_raycast_update()
	if wall_check.is_colliding():
		_turn_around()

	if turn_on_ledge and ground_check != null:
		ground_check.force_raycast_update()
		if not ground_check.is_colliding():
			_turn_around()

# -----------------------------
# Spit attack (frame-perfect, LOS-aware)
# Works even if attack anim loops: ends when last frame is reached.
# -----------------------------
func _start_spit_attack() -> void:
	can_spit = false
	is_attacking = true

	# Face player
	dir = 1 if player.global_position.x > global_position.x else -1
	_face_dir(dir)

	# If anim missing, still shoot once and finish
	if anim.sprite_frames == null or not anim.sprite_frames.has_animation(attack_anim_name):
		_spawn_spit()
		is_attacking = false
		await get_tree().create_timer(ZombieConfig.SPIT_COOLDOWN).timeout
		can_spit = true
		return

	anim.play(attack_anim_name)
	anim.frame = 0

	var total_frames: int = anim.sprite_frames.get_frame_count(attack_anim_name)
	var last_frame: int = max(total_frames - 1, 0)

	var spawned := false
	while is_attacking and anim.animation == String(attack_anim_name):
		await anim.frame_changed

		# Abort if LOS is lost
		if player == null or not _player_in_sight():
			is_attacking = false
			if debug_ai:
				print("Zombie AI | Lost sight during attack -> abort")
			break

		# Spawn exactly on release frame
		if not spawned and anim.frame == spit_release_frame:
			_spawn_spit()
			spawned = true

		# End attack when last frame reached (prevents stuck if looping)
		if anim.frame >= last_frame:
			is_attacking = false
			break

	# Force exit attack pose
	anim.stop()

	# Cooldown
	await get_tree().create_timer(ZombieConfig.SPIT_COOLDOWN).timeout
	can_spit = true

func _spawn_spit() -> void:
	if projectile_scene == null or player == null:
		if debug_ai and projectile_scene == null:
			print("Zombie AI | projectile_scene is NULL (assign SpitProjectile.tscn)")
		return

	var spit: Node = projectile_scene.instantiate()
	get_parent().add_child(spit)

	# Spawn near mouth
	var mouth_offset := Vector2(10.0 * float(dir), los_y_offset)
	spit.global_position = global_position + mouth_offset

	# Aim at the player's ground point (not their air position)
	var target_pos := _get_player_ground_point()
	var aim: Vector2 = (target_pos - spit.global_position).normalized()

	if spit.has_method("set_direction"):
		spit.call("set_direction", aim)

# -----------------------------
# Ground aiming helpers
# -----------------------------
func _get_player_ground_point() -> Vector2:
	var p := player as CharacterBody2D
	var origin := p.global_position

	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(
		origin,
		origin + Vector2(0.0, ground_raycast_depth),
		ground_mask
	)
	query.exclude = [p]

	var result := space.intersect_ray(query)
	if result.is_empty():
		return _get_player_feet_pos(p)

	return result.position

func _get_player_feet_pos(p: CharacterBody2D) -> Vector2:
	var aim_pos := p.global_position
	var cs := p.get_node_or_null("CollisionShape2D") as CollisionShape2D

	if cs == null or cs.shape == null:
		aim_pos.y += 16.0
		return aim_pos

	var extents_y := 16.0
	if cs.shape is RectangleShape2D:
		extents_y = (cs.shape as RectangleShape2D).size.y * 0.5
	elif cs.shape is CapsuleShape2D:
		var cap := cs.shape as CapsuleShape2D
		extents_y = (cap.height * 0.5) + cap.radius
	elif cs.shape is CircleShape2D:
		extents_y = (cs.shape as CircleShape2D).radius

	aim_pos.x += cs.position.x
	aim_pos.y += extents_y + cs.position.y
	return aim_pos

# -----------------------------
# Helpers
# -----------------------------
func _turn_around() -> void:
	dir *= -1
	_face_dir(dir)

func _face_dir(new_dir: int) -> void:
	anim.flip_h = (new_dir < 0)

	wall_check.target_position.x = abs(wall_check.target_position.x) * float(new_dir)
	if ground_check != null:
		ground_check.target_position.x = abs(ground_check.target_position.x) * float(new_dir)

func _update_animation() -> void:
	if is_attacking:
		return
	if anim.sprite_frames == null:
		return

	if abs(velocity.x) > 0.1:
		if anim.sprite_frames.has_animation(&"run") and anim.animation != "run":
			anim.play("run")
	else:
		if anim.sprite_frames.has_animation(&"idle") and anim.animation != "idle":
			anim.play("idle")

func take_damage(amount: float = 1.0) -> void:
	current_hp -= amount
	health_bar.value = current_hp
	if current_hp <= 0:
		queue_free()

func _on_hit_area_body_entered(body: Node) -> void:
	if body.is_in_group("player") and body.has_method("die"):
		body.die(true)  # マスクを無視して死亡
