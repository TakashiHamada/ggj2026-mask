extends CharacterBody2D

signal health_changed(current_hp: float, max_hp: float)
signal coins_changed(current_coins: int, total_coins: int)
signal stage_cleared

enum WeaponType { NONE, HAMMER, BOOMERANG }

var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
var spawn_position: Vector2
var has_mask: bool = false  # ガスマスクを所持しているか
var weapon_type: WeaponType = WeaponType.NONE  # 所持している武器の種類
var has_gas_mask: bool = false  # 現在ガスマスクを装着中か
var is_boomerang_thrown: bool = false  # ブーメラン投げ中
var is_dying: bool = false
var is_attacking: bool = false
var is_charging: bool = false  # 溜め中
var facing_dir: int = 1  # 1 = 右, -1 = 左
var charge_time: float = 0.0  # 溜め時間
var attack_damage: float = 1.0  # 現在の攻撃力
var is_fully_charged: bool = false  # 最大溜め状態
var is_stage_cleared: bool = false  # ステージクリア状態

var max_hp: float = 6.0
var current_hp: float = 6.0
var coins: int = 0
var total_coins: int = 0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var gas_mask: Node2D = $GasMask
@onready var hammer: Node2D = $Hammer
@onready var attack_area: Area2D = $AttackArea
@onready var attack_shape: CollisionShape2D = $AttackArea/CollisionShape2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var footstep_sfx: AudioStreamPlayer2D = $FootstepSFX
@onready var footstep_timer: Timer = $FootstepTimer
@onready var damage_sfx: AudioStreamPlayer2D = $DamageSFX

# --- Run animation ---
@export var run_anim_name: StringName = &"run"
var _idle_anim_name: StringName

# --- Dust trail ---
@export var dust_scene: PackedScene
@export var dust_interval: float = 0.08
@export var dust_back_offset_x: float = 6.0  # behind feet
@export var dust_up_offset_y: float = 2.0    # lift slightly above floor
var _dust_timer: float = 0.0

# --- Level clear transition (ADDED) ---
const LEVEL_CLEAR_SCENE := "res://Scenes/level_clear.tscn"
var _is_transitioning: bool = false
@onready var fade: ColorRect = get_tree().current_scene.get_node_or_null("Fade")

var _move_input_x: float = 0.0
var coyote_timer: float = 0.0  # 床から離れてからの経過時間
var jump_buffer: bool = false  # ジャンプ入力バッファ

var blink_tween: Tween = null
var charge_tween: Tween = null


func _ready() -> void:
	spawn_position = global_position
	attack_area.body_entered.connect(_on_attack_hit)

	# Capture whatever animation is set as "default/idle" in the editor
	_idle_anim_name = sprite.animation

	current_hp = max_hp
	health_changed.emit(current_hp, max_hp)

	# 攻撃範囲をパラメーターから設定
	var shape := attack_shape.shape as RectangleShape2D
	shape.size = Vector2(PlayerConfig.ATTACK_RANGE_X, PlayerConfig.ATTACK_RANGE_Y)

	# ステージ内のコイン数をカウント
	await get_tree().process_frame
	total_coins = get_tree().get_nodes_in_group("coins").size()

	# 岩の中のコインもカウント
	for node in get_tree().get_nodes_in_group("destructible_rocks"):
		if node.has_method("get") and node.get("coin_count") != null:
			total_coins += node.coin_count

	# ゾンビボスがドロップするコインもカウント
	for node in get_tree().get_nodes_in_group("zombie_bosses"):
		if node.has_method("get") and node.get("boss_coin_drop_count") != null:
			total_coins += node.boss_coin_drop_count

	coins_changed.emit(coins, total_coins)

	# Footsteps
	footstep_timer.one_shot = false
	footstep_timer.autostart = false
	footstep_timer.timeout.connect(_on_footstep_timer_timeout)

	# Ensure fade starts transparent if present
	if fade:
		fade.modulate.a = 0.0


func _process(delta: float) -> void:
	# ガスマスク処理（マスク所持時のみ）
	if has_mask:
		has_gas_mask = Input.is_action_pressed("gas_mask") and not is_boomerang_thrown
		gas_mask.visible = has_gas_mask
	else:
		has_gas_mask = false
		gas_mask.visible = false

	# 武器のビジュアル表示（攻撃中・溜め中）
	if weapon_type == WeaponType.HAMMER:
		hammer.visible = is_attacking or is_charging

	# 溜め時間を加算
	if is_charging:
		charge_time += delta
		# 最大溜めに達したら点滅開始
		if not is_fully_charged and charge_time >= PlayerConfig.ATTACK_CHARGE_TIME:
			is_fully_charged = true
			_start_charge_effect()

	# 攻撃入力（武器所持時・ガスマスク装着中・ブーメラン投げ中は攻撃不可）
	if weapon_type != WeaponType.NONE and not is_dying and not has_gas_mask and not is_attacking and not is_boomerang_thrown:
		if Input.is_action_just_pressed("attack") and not is_charging:
			_start_charge()
		elif Input.is_action_just_released("attack") and is_charging:
			_release_attack()


func _update_animation() -> void:
	# Don't override attack/charge/dying
	if is_dying or is_attacking or is_charging or _is_transitioning:
		return

	if _idle_anim_name == StringName():
		return

	var moving := absf(_move_input_x) > 0.01

	# In air: don't force run
	if not is_on_floor():
		if sprite.sprite_frames.has_animation(_idle_anim_name) and sprite.animation != _idle_anim_name:
			sprite.play(_idle_anim_name)
		return

	if moving:
		if sprite.sprite_frames.has_animation(run_anim_name) and sprite.animation != run_anim_name:
			sprite.play(run_anim_name)
	else:
		if sprite.sprite_frames.has_animation(_idle_anim_name) and sprite.animation != _idle_anim_name:
			sprite.play(_idle_anim_name)


# Feet spawn for RectangleShape2D 16x16
func _get_feet_spawn_global() -> Vector2:
	var half_h := 8.0
	var scale_y := collision_shape.global_scale.y
	var feet_y := collision_shape.global_position.y + (half_h * scale_y) - dust_up_offset_y
	var feet_x := collision_shape.global_position.x - (facing_dir * dust_back_offset_x)
	return Vector2(feet_x, feet_y)


func _spawn_dust() -> void:
	if dust_scene == null:
		return

	var dust := dust_scene.instantiate() as GPUParticles2D
	if dust == null:
		return

	# Add to WORLD
	get_tree().current_scene.add_child(dust)

	# Ignore parent transforms (prevents screen-edge bug)
	dust.top_level = true

	# Position at feet
	dust.global_position = _get_feet_spawn_global()

	# Emit once
	dust.one_shot = true
	dust.emitting = true

	# Cleanup
	var life := dust.lifetime
	await get_tree().create_timer(life).timeout
	if is_instance_valid(dust):
		dust.queue_free()


func obtain_mask() -> void:
	has_mask = true

func obtain_weapon(type: WeaponType) -> void:
	weapon_type = type


func die(ignore_mask: bool = false) -> void:
	if is_dying:
		return
	if has_gas_mask and not ignore_mask:
		return

	current_hp -= 1
	health_changed.emit(current_hp, max_hp)
	damage_sfx.play()

	# 溜め中・攻撃中だった場合はキャンセル
	if is_charging or is_attacking:
		is_charging = false
		is_attacking = false
		is_fully_charged = false
		attack_area.monitoring = false
		hammer.position = Vector2(0, -4)
		hammer.scale = Vector2(facing_dir, 1)
		hammer.visible = false
		_stop_charge_effect()
		sprite.play()

	if current_hp <= 0:
		# 死亡：ステージリセット
		is_dying = true
		velocity = Vector2.ZERO
		_start_invincibility()
		await get_tree().create_timer(PlayerConfig.DEATH_RESPAWN_TIME).timeout
		get_tree().reload_current_scene()
	else:
		# ダメージを受けたが生存：硬直＋無敵時間
		is_dying = true
		velocity = Vector2.ZERO
		_start_invincibility()
		await get_tree().create_timer(PlayerConfig.DAMAGE_STUN_TIME).timeout
		is_dying = false
		var remaining_invincibility := PlayerConfig.INVINCIBILITY_TIME - PlayerConfig.DAMAGE_STUN_TIME
		if remaining_invincibility > 0:
			await get_tree().create_timer(remaining_invincibility).timeout
		_end_invincibility()


func _physics_process(delta: float) -> void:
	# コヨーテタイム（床から離れた後のジャンプ猶予）
	if is_on_floor():
		coyote_timer = 0.0
	else:
		coyote_timer += delta

	# 重力
	if not is_on_floor():
		velocity.y += gravity * delta

	# Transitioning: lock control
	if _is_transitioning:
		velocity = Vector2.ZERO
		move_and_slide()
		handle_footsteps()
		return

	# 死亡中は操作不能（重力は適用）
	if is_dying:
		move_and_slide()
		handle_footsteps()
		return

	# 攻撃中・溜め中は移動不可（重力は適用）
	if is_attacking or is_charging:
		velocity.x = 0
		move_and_slide()
		handle_footsteps()
		return

	# ジャンプ（コヨーテタイム内なら空中でもジャンプ可能）
	var can_jump := is_on_floor() or coyote_timer < PlayerConfig.COYOTE_TIME
	if jump_buffer and can_jump:
		velocity.y = PlayerConfig.JUMP_VELOCITY
		coyote_timer = PlayerConfig.COYOTE_TIME
	jump_buffer = false

	# 小ジャンプ（上昇中にボタンを離すと減速）
	if Input.is_action_just_released("jump") and velocity.y < 0:
		velocity.y *= PlayerConfig.JUMP_CUT_MULTIPLIER

	# 左右移動
	var move_speed := PlayerConfig.MOVE_SPEED_WITH_MASK if has_gas_mask else PlayerConfig.MOVE_SPEED
	var direction := Input.get_axis("move_left", "move_right")
	_move_input_x = direction

	if direction != 0:
		velocity.x = direction * move_speed
		sprite.flip_h = direction < 0
		gas_mask.scale.x = -1 if direction < 0 else 1
		facing_dir = 1 if direction > 0 else -1
	else:
		velocity.x = move_toward(velocity.x, 0, move_speed)
		if absf(velocity.x) < 1.0:
			velocity.x = 0.0

	_update_animation()

	# Dust trail
	var running_on_ground := (
		is_on_floor()
		and absf(_move_input_x) > 0.01
		and not is_dying
		and not is_attacking
		and not is_charging
	)

	if running_on_ground:
		_dust_timer -= delta
		if _dust_timer <= 0.0:
			_dust_timer = dust_interval
			_spawn_dust()
	else:
		_dust_timer = 0.0

	move_and_slide()
	handle_footsteps()


# 攻撃処理
const ATTACK_START_Y: float = -12.0
const ATTACK_END_Y: float = 8.0

func _start_charge() -> void:
	is_charging = true
	charge_time = 0.0
	is_fully_charged = false
	sprite.pause()
	# ハンマーを前方上部に構える
	if weapon_type == WeaponType.HAMMER:
		hammer.scale = Vector2(2 * facing_dir, 2)
		hammer.position.x = PlayerConfig.ATTACK_OFFSET_X * facing_dir
		hammer.position.y = ATTACK_START_Y

func _start_charge_effect() -> void:
	if charge_tween:
		charge_tween.kill()
	charge_tween = create_tween().set_loops()
	charge_tween.tween_property(sprite, "modulate", Color(1.0, 0.3, 0.3), PlayerConfig.CHARGE_FLASH_SPEED)
	charge_tween.tween_property(sprite, "modulate", Color.WHITE, PlayerConfig.CHARGE_FLASH_SPEED)

func _stop_charge_effect() -> void:
	if charge_tween:
		charge_tween.kill()
		charge_tween = null
	sprite.modulate = Color.WHITE

func _release_attack() -> void:
	is_charging = false
	is_fully_charged = false
	_stop_charge_effect()

	# 溜め時間に応じてダメージを計算
	var charge_ratio := clampf(charge_time / PlayerConfig.ATTACK_CHARGE_TIME, 0.0, 1.0)
	attack_damage = lerpf(PlayerConfig.ATTACK_BASE_DAMAGE, PlayerConfig.ATTACK_MAX_DAMAGE, charge_ratio)

	if weapon_type == WeaponType.BOOMERANG:
		_release_boomerang_attack()
	else:
		_release_hammer_attack()

func _release_hammer_attack() -> void:
	is_attacking = true
	attack_area.position.x = PlayerConfig.ATTACK_OFFSET_X * facing_dir
	attack_area.monitoring = true

	# ハンマーを真下に振り下ろすアニメーション
	var tween := create_tween()
	tween.tween_property(hammer, "position:y", ATTACK_END_Y, 0.1)
	tween.tween_callback(_end_attack)

	# 攻撃判定（アニメーション中に重なっているボディをチェック）
	await get_tree().physics_frame
	for body in attack_area.get_overlapping_bodies():
		_on_attack_hit(body)

func _release_boomerang_attack() -> void:
	is_boomerang_thrown = true
	sprite.play()

	# ブーメランを生成
	var boomerang_scene := preload("res://Scenes/boomerang.tscn")
	var boomerang := boomerang_scene.instantiate()
	get_parent().add_child(boomerang)
	boomerang.global_position = global_position + Vector2(10 * facing_dir, -4)
	boomerang.setup(self, facing_dir, attack_damage)

func on_boomerang_returned() -> void:
	is_boomerang_thrown = false

func _end_attack() -> void:
	is_attacking = false
	attack_area.monitoring = false
	hammer.position = Vector2(0, -4)
	hammer.scale = Vector2(facing_dir, 1)
	sprite.play()  # アニメーション再開

func _on_attack_hit(body: Node) -> void:
	if body == self:
		return
	if body.has_method("take_damage"):
		body.take_damage(attack_damage)
	if body.is_in_group("enemy"):
		body.take_hit(1, global_position)
	elif body.has_method("die"):
		body.die()

func take_gas_damage(delta: float) -> void:
	if has_gas_mask or is_dying:
		return

	current_hp -= PlayerConfig.GAS_DAMAGE_PER_SECOND * delta
	health_changed.emit(current_hp, max_hp)

	if current_hp <= 0:
		current_hp = 0
		health_changed.emit(current_hp, max_hp)
		_die_from_gas()

func _die_from_gas() -> void:
	# 溜め中・攻撃中だった場合はキャンセル
	if is_charging or is_attacking:
		is_charging = false
		is_attacking = false
		is_fully_charged = false
		attack_area.monitoring = false
		hammer.position = Vector2(0, -4)
		hammer.scale = Vector2(facing_dir, 1)
		hammer.visible = false
		_stop_charge_effect()
		sprite.play()

	is_dying = true
	velocity = Vector2.ZERO
	_start_invincibility()
	await get_tree().create_timer(PlayerConfig.DEATH_RESPAWN_TIME).timeout
	get_tree().reload_current_scene()

# 無敵状態の開始（点滅＋敵すり抜け）
func _start_invincibility() -> void:
	# 敵との当たり判定を無効化（レイヤー8に移動）
	set_collision_layer_value(1, false)
	set_collision_layer_value(8, true)

	# 点滅開始
	if blink_tween:
		blink_tween.kill()
	blink_tween = create_tween().set_loops()
	blink_tween.tween_property(sprite, "modulate:a", 0.3, 0.08)
	blink_tween.tween_property(sprite, "modulate:a", 1.0, 0.08)

# 無敵状態の終了
func _end_invincibility() -> void:
	# 当たり判定を元に戻す
	set_collision_layer_value(8, false)
	set_collision_layer_value(1, true)

	# 点滅停止
	if blink_tween:
		blink_tween.kill()
		blink_tween = null
	sprite.modulate.a = 1.0


func add_coin(amount: int) -> void:
	coins += amount
	coins_changed.emit(coins, total_coins)
	if coins >= total_coins and total_coins > 0:
		_on_stage_clear()

func heal(amount: float) -> void:
	current_hp = minf(current_hp + amount, max_hp)
	health_changed.emit(current_hp, max_hp)


func _on_stage_clear() -> void:
	if _is_transitioning:
		return
	_is_transitioning = true

	stage_cleared.emit()
	is_stage_cleared = true
	is_dying = true  # 操作を無効化
	velocity = Vector2.ZERO

	# Fade then go to Level Clear scene
	if fade:
		var t := create_tween()
		t.tween_property(fade, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		t.tween_callback(func():
			get_tree().change_scene_to_file(LEVEL_CLEAR_SCENE)
		)
	else:
		get_tree().change_scene_to_file(LEVEL_CLEAR_SCENE)


func _input(event: InputEvent) -> void:
	# ジャンプ入力を即座にバッファリング
	if event.is_action_pressed("jump"):
		jump_buffer = true

	if not is_stage_cleared:
		return
	# スペース、N、Mキーでリスタート
	if Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("attack") or Input.is_action_just_pressed("gas_mask"):
		get_tree().reload_current_scene()


func handle_footsteps() -> void:
	# Only play when:
	# - on the floor
	# - actually moving horizontally
	# - not dying / attacking / charging
	var can_step := (
		is_on_floor()
		and absf(velocity.x) > 5.0
		and not is_dying
		and not is_attacking
		and not is_charging
		and not _is_transitioning
	)

	if can_step:
		if footstep_timer.is_stopped():
			footstep_timer.start()
	else:
		if not footstep_timer.is_stopped():
			footstep_timer.stop()

func _on_footstep_timer_timeout() -> void:
	# small pitch variation so it doesn't sound robotic
	footstep_sfx.pitch_scale = randf_range(0.95, 1.05)
	footstep_sfx.play()
