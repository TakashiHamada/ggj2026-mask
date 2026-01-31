extends Area2D

var player: Node2D
var direction: int = 1
var damage: float = 1.0
var speed: float = PlayerConfig.BOOMERANG_SPEED
var max_distance: float = PlayerConfig.BOOMERANG_MAX_DISTANCE
var start_position: Vector2
var returning: bool = false

func setup(p: Node2D, dir: int, dmg: float) -> void:
	player = p
	direction = dir
	damage = dmg
	start_position = global_position

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

func _physics_process(delta: float) -> void:
	if not returning:
		# 前進
		global_position.x += direction * speed * delta
		# 最大距離に達したら戻り始める
		if abs(global_position.x - start_position.x) >= max_distance:
			returning = true
	else:
		# プレイヤーに向かって戻る
		if player and is_instance_valid(player):
			var target_pos := player.global_position + Vector2(0, -4)
			var dir_to_player := (target_pos - global_position).normalized()
			global_position += dir_to_player * speed * 1.5 * delta

			# プレイヤーに十分近づいたら消える
			if global_position.distance_to(target_pos) < 10:
				_return_to_player()
		else:
			queue_free()

func _on_body_entered(body: Node) -> void:
	if body == player:
		if returning:
			_return_to_player()
		return

	if body.has_method("take_damage"):
		body.take_damage(damage)
	elif body.has_method("die"):
		body.die()

func _on_area_entered(area: Area2D) -> void:
	# コインを取得
	if area.has_method("_on_body_entered") and player:
		# コインのスクリプトはbody_enteredでプレイヤーを渡すとコインを追加する
		if area.get("value") != null:
			player.add_coin(area.value)
			area.queue_free()

func _return_to_player() -> void:
	if player and player.has_method("on_boomerang_returned"):
		player.on_boomerang_returned()
	queue_free()
