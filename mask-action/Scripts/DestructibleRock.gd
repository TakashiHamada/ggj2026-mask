extends StaticBody2D

@export var hp: float = 3.0  # 岩の耐久値
@export var min_damage_to_break: float = 2.0  # 破壊に必要な最小ダメージ（溜め攻撃のみ）
@export var coin_count: int = 0  # 破壊時に出るコインの数

var coin_scene: PackedScene = preload("res://Scenes/coin.tscn")

func take_damage(damage: float) -> void:
	# 溜め攻撃（一定以上のダメージ）でないと壊れない
	if damage < min_damage_to_break:
		return

	hp -= damage

	# ヒットエフェクト（少し揺れる）
	var tween := create_tween()
	tween.tween_property(self, "position:x", position.x + 2, 0.05)
	tween.tween_property(self, "position:x", position.x - 2, 0.05)
	tween.tween_property(self, "position:x", position.x, 0.05)

	if hp <= 0:
		_destroy()

func _destroy() -> void:
	# コインを生成
	_spawn_coins()
	queue_free()

func _spawn_coins() -> void:
	if coin_count <= 0:
		return

	var coins_node := get_tree().current_scene.get_node_or_null("Coins")
	var parent := coins_node if coins_node else get_parent()

	for i in range(coin_count):
		var coin := coin_scene.instantiate()
		parent.add_child(coin)
		# コインを少し散らばらせる
		var offset := Vector2(randf_range(-16, 16), randf_range(-16, 0))
		coin.global_position = global_position + offset
