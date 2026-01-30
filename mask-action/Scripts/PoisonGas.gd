extends Area2D

var bodies_in_gas: Array[Node2D] = []

func _on_body_entered(body: Node2D) -> void:
	if body.has_method("die"):
		bodies_in_gas.append(body)

func _on_body_exited(body: Node2D) -> void:
	bodies_in_gas.erase(body)

func _physics_process(_delta: float) -> void:
	for body in bodies_in_gas:
		if body.has_method("die"):
			body.die()
