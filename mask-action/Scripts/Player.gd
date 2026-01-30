extends CharacterBody2D

@export var speed: float = 200.0
@export var jump_velocity: float = -350.0

var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

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
	else:
		velocity.x = move_toward(velocity.x, 0, speed)

	move_and_slide()
