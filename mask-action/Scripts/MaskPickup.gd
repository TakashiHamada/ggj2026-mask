extends Area2D

# Player.MaskType と同じ値を使用
enum MaskType { NONE, MELEE, BOOMERANG }

@export var mask_type: MaskType = MaskType.MELEE

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player") and body.has_method("obtain_mask"):
		body.obtain_mask(mask_type)
		queue_free()
