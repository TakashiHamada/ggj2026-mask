extends Area2D

@export var speed: float = 200.0
@export var lifetime: float = 3.0

var direction: Vector2 = Vector2.ZERO

func _ready() -> void:
	await get_tree().create_timer(lifetime).timeout
	queue_free()

func _physics_process(delta: float) -> void:
	position += direction * speed * delta

func set_direction(dir: Vector2) -> void:
	direction = dir.normalized()

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		if body.has_method("die"):
			body.die()
		queue_free()
