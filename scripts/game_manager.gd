extends Node
## GameManager · 全局货币状态管理（唯一 autoload 单例）
## 职责单一：仅持有 gold / inspiration 状态，提供增减方法，发射信号通知观察者。
## 原则：低耦合 —— 其他节点通过 signal 订阅变化，不直接读写内部字段。

signal currency_changed(new_gold: int, new_inspiration: int)

@export var initial_gold: int = 0
@export var initial_inspiration: int = 0

var gold: int:
	set(v):
		gold = v
		currency_changed.emit(gold, inspiration)

var inspiration: int:
	set(v):
		inspiration = v
		currency_changed.emit(gold, inspiration)


func _ready() -> void:
	gold = initial_gold
	inspiration = initial_inspiration


func add_gold(amount: int) -> void:
	if amount < 0:
		push_warning("add_gold 收到负值 %d，请用 subtract_gold" % amount)
	gold += amount


func subtract_gold(amount: int) -> void:
	add_gold(-amount)


func add_inspiration(amount: int) -> void:
	if amount < 0:
		push_warning("add_inspiration 收到负值 %d，请用 subtract_inspiration" % amount)
	inspiration += amount


func subtract_inspiration(amount: int) -> void:
	add_inspiration(-amount)


func complete_order(base_reward: Dictionary) -> void:
	## 通用订单完成入口。base_reward 应包含 "gold" 和 "inspiration" 键。
	var reward_gold: int = base_reward.get("gold", 0)
	var reward_insp: int = base_reward.get("inspiration", 0)
	add_gold(reward_gold)
	add_inspiration(reward_insp)
