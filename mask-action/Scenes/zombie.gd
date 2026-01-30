extends CharacterBody2D

@export var speed: float = 60.0
@export var gravity: float = 900.0

# --- Spit attack ---
@export var spit_range: float = 200.0
@export var spit_cooldown: float = 2.0
@export var projectile_scene: PackedScene
@export var attack_anim_name: StringName = &"attack" # or &"spit"
@export var spit_release_frame: int = 3

# --- Patrol behavior ---
@export var turn_on_ledge: bool = true

# --- Line of sight ---
@export var los_max_distance: float = 260.0
@export var los_y_offset: float = -6.0 # "eye/mouth" height relative to zombie
@export var debug_ai: bool = false

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var wall_check: RayCast2D = $WallCheck
@onready var ground_check: RayCast2D = $GroundCheck if has_node("GroundCheck") else null
@onready var sight_ray: RayCast2D = $SightRay

var dir: int = 1
var can_spit: bool = true
var is_attacking: bool = false
var player: Node2D = null

func _ready() -> void:
	_face_dir(dir)
	_find_player()
	sight_ray.enabled = true

func _physics_process(delta: float) -> void:
	# Gravity
	if not is_on_floor():
		velocity.y += gravity * delta
	else:
		velocity.y = 0.0

	# Re-acquire player if needed (e.g., spawned later)
	if player == null:
		_find_player()

	# If attacking, we only remain attacking if player stays in sight
	if is_attacking:
		if player == null or not _player_in_sight():
			# Abort attack and resume moving
			is_attacking = false
			anim.stop()
			if debug_ai:
				print("Zombie AI | Lost sight -> abort attack")
		else:
			velocity.x = 0.0
			move_and_slide()
			return

	# If no player at all, just patrol
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

	# Attack ONLY if in range AND visible
	if in_range and in_sight and can_spit:
		_start_spit_attack()
	else:
		# Not in sight -> resume moving (patrol)
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
# Line of sight
# -----------------------------
func _player_in_sight() -> bool:
	if player == null:
		return false

	# Build ray from "mouth/eyes" toward the player
	var origin := global_position + Vector2(0.0, los_y_offset)
	var to_player := player.global_position - origin

	# Too far to care
	if to_player.length() > los_max_distance:
		return false

	sight_ray.global_position = origin
	sight_ray.target_position = to_player

	# Ensure raycast updates this frame
	sight_ray.force_raycast_update()

	if not sight_ray.is_colliding():
		return false

	var hit := sight_ray.get_collider()
	# Only "in sight" if first thing hit is the player (not a wall)
	return hit == player

# -----------------------------
# Patrol movement
# -----------------------------
func _patrol() -> void:
	velocity.x = float(dir) * speed

	wall_check.force_raycast_update()
	if wall_check.is_colliding():
		_turn_around()

	if turn_on_ledge and ground_check != null:
		ground_check.force_raycast_update()
		if not ground_check.is_colliding():
			_turn_around()

# -----------------------------
# Spit attack (frame-perfect)
# -----------------------------
func _start_spit_attack() -> void:
	can_spit = false
	is_attacking = true

	# Face player
	dir = 1 if player.global_position.x > global_position.x else -1
	_face_dir(dir)

	# If anim missing, still shoot once and continue
	if anim.sprite_frames == null or not anim.sprite_frames.has_animation(attack_anim_name):
		_spawn_spit()
		is_attacking = false
		await get_tree().create_timer(spit_cooldown).timeout
		can_spit = true
		return

	# Play from start
	anim.play(attack_anim_name)
	anim.frame = 0

	# Spawn exactly on release frame, but abort if LOS is lost
	var spawned := false
	while is_attacking and not spawned and anim.animation == String(attack_anim_name):
		await anim.frame_changed

		# If player not visible anymore, abort and resume patrol
		if player == null or not _player_in_sight():
			is_attacking = false
			anim.stop()
			if debug_ai:
				print("Zombie AI | Lost sight during attack -> abort before shot")
			break

		if anim.frame == spit_release_frame:
			_spawn_spit()
			spawned = true

	# If we aborted, resume movement immediately (cooldown still applies)
	if not is_attacking:
		await get_tree().create_timer(spit_cooldown).timeout
		can_spit = true
		return

	# Wait for anim to finish (attack/spit should NOT be looping)
	await anim.animation_finished
	is_attacking = false

	await get_tree().create_timer(spit_cooldown).timeout
	can_spit = true

func _spawn_spit() -> void:
	if projectile_scene == null or player == null:
		if debug_ai and projectile_scene == null:
			print("Zombie AI | projectile_scene is NULL (assign SpitProjectile.tscn)")
		return

	var spit: Node = projectile_scene.instantiate()
	get_parent().add_child(spit)

	# Mouth offset: tune per your sprite
	var mouth_offset := Vector2(10.0 * float(dir), los_y_offset)
	spit.global_position = global_position + mouth_offset

	var aim: Vector2 = (player.global_position - spit.global_position).normalized()
	if spit.has_method("set_direction"):
		spit.call("set_direction", aim)

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
