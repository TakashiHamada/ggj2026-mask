extends CharacterBody2D

signal health_changed(current_hp: float, max_hp: float)

var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
var spawn_position: Vector2
var has_gas_mask: bool = false
var is_dying: bool = false
var is_attacking: bool = false
var is_charging: bool = false  # 溜め中
var facing_dir: int = 1  # 1 = 右, -1 = 左

var max_hp: float = 3.0
var current_hp: float = 3.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var gas_mask: Node2D = $GasMask
@onready var attack_area: Area2D = $AttackArea

func _ready() -> void:
	spawn_position = global_position
	attack_area.body_entered.connect(_on_attack_hit)
	current_hp = max_hp
	health_changed.emit(current_hp, max_hp)

func _process(_delta: float) -> void:
	has_gas_mask = Input.is_action_pressed("gas_mask")
	gas_mask.visible = has_gas_mask or is_attacking or is_charging

	# 攻撃入力（マスク装着中は攻撃不可）
	if not is_dying and not has_gas_mask and not is_attacking:
		if Input.is_action_just_pressed("attack") and not is_charging:
			_start_charge()
		elif Input.is_action_just_released("attack") and is_charging:
			_release_attack()

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
		attack_area.monitoring = false
		gas_mask.position = Vector2(0, -4)
		sprite.play()

	if current_hp <= 0:
		# 死亡：リスポーン
		is_dying = true
		velocity = Vector2.ZERO
		await get_tree().create_timer(1.0).timeout
		current_hp = max_hp
		health_changed.emit(current_hp, max_hp)
		global_position = spawn_position
		is_dying = false
	else:
		# ダメージを受けたが生存：短い無敵時間
		is_dying = true
		await get_tree().create_timer(0.5).timeout
		is_dying = false

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
const ATTACK_OFFSET_X: float = 12.0  # 前方へのオフセット
const ATTACK_START_Y: float = -12.0  # 上の開始位置
const ATTACK_END_Y: float = 8.0      # 下の終了位置

func _start_charge() -> void:
	is_charging = true
	sprite.pause()
	# マスクを前方上部に構える
	gas_mask.position.x = ATTACK_OFFSET_X * facing_dir
	gas_mask.position.y = ATTACK_START_Y

func _release_attack() -> void:
	is_charging = false
	is_attacking = true
	attack_area.scale.x = facing_dir
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
	sprite.play()  # アニメーション再開

func _on_attack_hit(body: Node) -> void:
	if body == self:
		return
	if body.has_method("take_damage"):
		body.take_damage()
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
		attack_area.monitoring = false
		gas_mask.position = Vector2(0, -4)
		sprite.play()

	is_dying = true
	velocity = Vector2.ZERO
	await get_tree().create_timer(1.0).timeout
	current_hp = max_hp
	health_changed.emit(current_hp, max_hp)
	global_position = spawn_position
	is_dying = false
