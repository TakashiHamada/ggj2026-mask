extends RefCounted
class_name PlayerConfig

const MOVE_SPEED: float = 150.0
const MOVE_SPEED_WITH_MASK: float = 80.0  # マスク装着時の移動速度
const JUMP_VELOCITY: float = -350.0
const GAS_DAMAGE_PER_SECOND: float = .1  # 毒ガスで1秒あたりに受けるダメージ

# 攻撃範囲
const ATTACK_RANGE_X: float = 48.0  # 攻撃の横幅
const ATTACK_RANGE_Y: float = 32.0  # 攻撃の縦幅
const ATTACK_OFFSET_X: float = 14.0  # 前方へのオフセット
