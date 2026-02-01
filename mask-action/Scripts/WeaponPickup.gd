extends Area2D

# Player.WeaponType と同じ値を使用
enum WeaponType { NONE, HAMMER, BOOMERANG }

@export var weapon_type: WeaponType = WeaponType.HAMMER

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player") and body.has_method("obtain_weapon"):
		body.obtain_weapon(weapon_type)
		queue_free()
