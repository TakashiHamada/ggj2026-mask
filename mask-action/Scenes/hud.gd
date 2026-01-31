extends CanvasLayer

@onready var health_bar: ProgressBar = $HealthBar
@onready var stage_clear_label: Label = $StageClearLabel
@onready var coin_label: Label = $CoinLabel

func _ready() -> void:
	# プレイヤーを探してシグナルを接続
	var player = get_tree().get_first_node_in_group("player")
	if player:
		player.health_changed.connect(_on_player_health_changed)
		player.coins_changed.connect(_on_coins_changed)
		player.stage_cleared.connect(_on_stage_cleared)

	if stage_clear_label:
		stage_clear_label.visible = false

func _on_player_health_changed(current_hp: float, max_hp: float) -> void:
	health_bar.max_value = max_hp
	health_bar.value = current_hp

func _on_coins_changed(current_coins: int, total_coins: int) -> void:
	if coin_label:
		coin_label.text = "%d/%d" % [current_coins, total_coins]

func _on_stage_cleared() -> void:
	if stage_clear_label:
		stage_clear_label.visible = true
