extends CharacterBody2D

signal health_changed(current_hp: float, max_hp: float)
signal coins_changed(current_coins: int, total_coins: int)
signal stage_cleared

var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
var spawn_position: Vector2
var has_obtained_mask: bool = false  # マスクを取得したか
var has_gas_mask: bool = false
var is_dying: bool = false
var is_attacking: bool = false
var is_charging: bool = false  # 溜め中
var facing_dir: int = 1  # 1 = 右, -1 = 左
var charge_time: float = 0.0  # 溜め時間
var attack_damage: float = 1.0  # 現在の攻撃力
var is_fully_charged: bool = false  # 最大溜め状態
var is_stage_cleared: bool = false  # ステージクリア状態

var max_hp: float = 3.0
var current_hp: float = 3.0
var coins: int = 0
var total_coins: int = 0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var gas_mask: Node2D = $GasMask
@onready var attack_area: Area2D = $AttackArea
@onready var attack_shape: CollisionShape2D = $AttackArea/CollisionShape2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var blink_tween: Tween = null
var charge_tween: Tween = null

func _ready() -> void:
	spawn_position = global_position
	attack_area.body_entered.connect(_on_attack_hit)
	current_hp = max_hp
	health_changed.emit(current_hp, max_hp)
	# 攻撃範囲をパラメーターから設定
	var shape := attack_shape.shape as RectangleShape2D
	shape.size = Vector2(PlayerConfig.ATTACK_RANGE_X, PlayerConfig.ATTACK_RANGE_Y)
	# ステージ内のコイン数をカウント
	await get_tree().process_frame
	var coins_node := get_tree().current_scene.get_node_or_null("Coins")
	if coins_node:
		total_coins = coins_node.get_child_count()
	coins_changed.emit(coins, total_coins)

func _process(delta: float) -> void:
	# マスク未取得なら能力使用不可
	if not has_obtained_mask:
		has_gas_mask = false
		gas_mask.visible = false
		return

	has_gas_mask = Input.is_action_pressed("gas_mask")
	gas_mask.visible = has_gas_mask or is_attacking or is_charging

	# 溜め時間を加算
	if is_charging:
		charge_time += delta
		# 最大溜めに達したら点滅開始
		if not is_fully_charged and charge_time >= PlayerConfig.ATTACK_CHARGE_TIME:
			is_fully_charged = true
			_start_charge_effect()

	# 攻撃入力（マスク装着中は攻撃不可）
	if not is_dying and not has_gas_mask and not is_attacking:
		if Input.is_action_just_pressed("attack") and not is_charging:
			_start_charge()
		elif Input.is_action_just_released("attack") and is_charging:
			_release_attack()

func obtain_mask() -> void:
	has_obtained_mask = true

func die(ignore_mask: bool = false) -> void:
	if is_dying:
		return
	if has_gas_mask and not ignore_mask:
		return

	current_hp -= 1
	health_changed.emit(current_hp, max_hp)

	# 溜め中・攻撃中だった場合はキャンセル
	if is_charging or is_attacking:
		is_charging = false
		is_attacking = false
		is_fully_charged = false
		attack_area.monitoring = false
		gas_mask.position = Vector2(0, -4)
		gas_mask.scale = Vector2(facing_dir, 1)  # 元のサイズに戻す
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
		velocity = Vector2.ZERO  # その場で停止
		_start_invincibility()
		await get_tree().create_timer(PlayerConfig.DAMAGE_STUN_TIME).timeout
		is_dying = false  # 硬直解除（操作可能に）
		var remaining_invincibility := PlayerConfig.INVINCIBILITY_TIME - PlayerConfig.DAMAGE_STUN_TIME
		if remaining_invincibility > 0:
			await get_tree().create_timer(remaining_invincibility).timeout
		_end_invincibility()

func _physics_process(delta: float) -> void:
	# 重力
	if not is_on_floor():
		velocity.y += gravity * delta

	# 死亡中は操作不能（重力は適用）
	if is_dying:
		move_and_slide()
		return

	# 攻撃中・溜め中は移動不可（重力は適用）
	if is_attacking or is_charging:
		velocity.x = 0
		move_and_slide()
		return

	# ジャンプ
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = PlayerConfig.JUMP_VELOCITY

	# 左右移動
	var move_speed := PlayerConfig.MOVE_SPEED_WITH_MASK if has_gas_mask else PlayerConfig.MOVE_SPEED
	var direction := Input.get_axis("move_left", "move_right")
	if direction != 0:
		velocity.x = direction * move_speed
		sprite.flip_h = direction < 0
		gas_mask.scale.x = -1 if direction < 0 else 1
		facing_dir = 1 if direction > 0 else -1
	else:
		velocity.x = move_toward(velocity.x, 0, move_speed)

	move_and_slide()

# 攻撃処理
const ATTACK_START_Y: float = -12.0  # 上の開始位置
const ATTACK_END_Y: float = 8.0      # 下の終了位置

func _start_charge() -> void:
	is_charging = true
	charge_time = 0.0
	is_fully_charged = false
	sprite.pause()
	# マスクを前方上部に構える（攻撃用に大きく）
	gas_mask.scale = Vector2(2 * facing_dir, 2)
	gas_mask.position.x = PlayerConfig.ATTACK_OFFSET_X * facing_dir
	gas_mask.position.y = ATTACK_START_Y

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
	is_attacking = true
	is_fully_charged = false
	_stop_charge_effect()

	# 溜め時間に応じてダメージを計算
	var charge_ratio := clampf(charge_time / PlayerConfig.ATTACK_CHARGE_TIME, 0.0, 1.0)
	attack_damage = lerpf(PlayerConfig.ATTACK_BASE_DAMAGE, PlayerConfig.ATTACK_MAX_DAMAGE, charge_ratio)

	attack_area.position.x = PlayerConfig.ATTACK_OFFSET_X * facing_dir
	attack_area.monitoring = true

	# マスクを真下に振り下ろすアニメーション
	var tween := create_tween()
	tween.tween_property(gas_mask, "position:y", ATTACK_END_Y, 0.1)
	tween.tween_callback(_end_attack)

	# 攻撃判定（アニメーション中に重なっているボディをチェック）
	await get_tree().physics_frame
	for body in attack_area.get_overlapping_bodies():
		_on_attack_hit(body)

func _end_attack() -> void:
	is_attacking = false
	attack_area.monitoring = false
	gas_mask.position = Vector2(0, -4)  # 元の位置に戻す
	gas_mask.scale = Vector2(facing_dir, 1)  # 元のサイズに戻す
	sprite.play()  # アニメーション再開

func _on_attack_hit(body: Node) -> void:
	if body == self:
		return
	if body.has_method("take_damage"):
		body.take_damage(attack_damage)
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
		gas_mask.position = Vector2(0, -4)
		gas_mask.scale = Vector2(facing_dir, 1)  # 元のサイズに戻す
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

func _on_stage_clear() -> void:
	stage_cleared.emit()
	is_stage_cleared = true
	is_dying = true  # 操作を無効化
	velocity = Vector2.ZERO

func _input(event: InputEvent) -> void:
	if is_stage_cleared and event.is_pressed():
		get_tree().reload_current_scene()

