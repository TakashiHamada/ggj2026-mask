extends CharacterBody2D

var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
var spawn_position: Vector2
var has_gas_mask: bool = false
var is_dying: bool = false
var is_attacking: bool = false
var facing_dir: int = 1  # 1 = 右, -1 = 左

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var gas_mask: Node2D = $GasMask
@onready var attack_area: Area2D = $AttackArea

func _ready() -> void:
	spawn_position = global_position
	attack_area.body_entered.connect(_on_attack_hit)

func _process(_delta: float) -> void:
	has_gas_mask = Input.is_action_pressed("gas_mask")
	gas_mask.visible = has_gas_mask or is_attacking

	# 攻撃入力
	if Input.is_action_just_pressed("attack") and not is_attacking and not is_dying:
		_start_attack()

func die(ignore_mask: bool = false) -> void:
	if is_dying:
		return
	if has_gas_mask and not ignore_mask:
		return
	is_dying = true
	velocity = Vector2.ZERO
	await get_tree().create_timer(1.0).timeout
	global_position = spawn_position
	is_dying = false

func _physics_process(delta: float) -> void:
	# 重力
	if not is_on_floor():
		velocity.y += gravity * delta

	# 死亡中は操作不能（重力は適用）
	if is_dying:
		move_and_slide()
		return

	# ジャンプ
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = PlayerConfig.JUMP_VELOCITY

	# 左右移動
	var direction := Input.get_axis("move_left", "move_right")
	if direction != 0:
		velocity.x = direction * PlayerConfig.MOVE_SPEED
		sprite.flip_h = direction < 0
		gas_mask.scale.x = -1 if direction < 0 else 1
		facing_dir = 1 if direction > 0 else -1
	else:
		velocity.x = move_toward(velocity.x, 0, PlayerConfig.MOVE_SPEED)

	move_and_slide()

# 攻撃処理
const ATTACK_OFFSET_X: float = 12.0  # 前方へのオフセット
const ATTACK_START_Y: float = -12.0  # 上の開始位置
const ATTACK_END_Y: float = 8.0      # 下の終了位置

func _start_attack() -> void:
	is_attacking = true
	attack_area.scale.x = facing_dir
	attack_area.monitoring = true

	# マスクを前方上部に移動
	gas_mask.position.x = ATTACK_OFFSET_X * facing_dir
	gas_mask.position.y = ATTACK_START_Y

	# マスクを真下に振り下ろすアニメーション
	var tween := create_tween()
	tween.tween_property(gas_mask, "position:y", ATTACK_END_Y, 0.15)
	tween.tween_callback(_end_attack)

	# 攻撃判定（アニメーション中に重なっているボディをチェック）
	await get_tree().physics_frame
	for body in attack_area.get_overlapping_bodies():
		_on_attack_hit(body)

func _end_attack() -> void:
	is_attacking = false
	attack_area.monitoring = false
	gas_mask.position = Vector2(0, -4)  # 元の位置に戻す

func _on_attack_hit(body: Node) -> void:
	if body == self:
		return
	if body.has_method("take_damage"):
		body.take_damage()
	elif body.has_method("die"):
		body.die()
