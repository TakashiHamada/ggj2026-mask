extends CharacterBody2D

@export var speed: float = 200.0
@export var jump_velocity: float = -350.0

var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
var spawn_position: Vector2
var has_gas_mask: bool = false

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var gas_mask: Node2D = $GasMask

func _ready() -> void:
	spawn_position = global_position

func _process(_delta: float) -> void:
	has_gas_mask = Input.is_action_pressed("gas_mask")
	gas_mask.visible = has_gas_mask

func die() -> void:
	if has_gas_mask:
		return
	global_position = spawn_position
	velocity = Vector2.ZERO

func _physics_process(delta: float) -> void:
	# 重力
	if not is_on_floor():
		velocity.y += gravity * delta

	# ジャンプ
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	# 左右移動
	var direction := Input.get_axis("move_left", "move_right")
	if direction != 0:
		velocity.x = direction * speed
		sprite.flip_h = direction < 0
		gas_mask.scale.x = -1 if direction < 0 else 1
	else:
		velocity.x = move_toward(velocity.x, 0, speed)

	move_and_slide()
