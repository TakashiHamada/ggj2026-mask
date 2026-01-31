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

# 溜め攻撃
const ATTACK_BASE_DAMAGE: float = 1.0  # 溜めなしの攻撃力
const ATTACK_MAX_DAMAGE: float = 3.0   # 最大溜めの攻撃力
const ATTACK_CHARGE_TIME: float = 0.6  # 最大溜めに必要な時間（秒）
const CHARGE_FLASH_SPEED: float = 0.1  # 溜め中の点滅速度（秒）

# ダメージ
const DAMAGE_STUN_TIME: float = 0.5  # ダメージ時の硬直時間（秒）
const INVINCIBILITY_TIME: float = 1.0  # 無敵時間（秒）※硬直時間より長くすること
const DEATH_RESPAWN_TIME: float = 1.0  # 死亡時のリスポーン時間（秒）
