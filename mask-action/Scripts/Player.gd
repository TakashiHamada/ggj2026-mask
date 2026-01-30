extends CharacterBody2D

var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
var spawn_position: Vector2
var has_gas_mask: bool = false
var is_dying: bool = false

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var gas_mask: Node2D = $GasMask

func _ready() -> void:
	spawn_position = global_position

func _process(_delta: float) -> void:
	has_gas_mask = Input.is_action_pressed("gas_mask")
	gas_mask.visible = has_gas_mask

func die() -> void:
	if has_gas_mask or is_dying:
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
	else:
		velocity.x = move_toward(velocity.x, 0, PlayerConfig.MOVE_SPEED)

	move_and_slide()
