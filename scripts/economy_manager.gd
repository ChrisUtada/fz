extends Node
class_name EconomyManager

## 经济管理子模块：金币 / 灵感 / 累计获得灵感（蓝图阈值用）/ 买卖与订单奖励发放。
## 作为 GameManager 的门面子管理器，所有外部代码仍通过 GameManager.xxx 访问（委托转发）。

signal currency_changed(new_gold: int, new_inspiration: int)

const INSPIRATION_TOTAL_SAVE_PATH := "user://inspiration_total.cfg"

var owner_mgr = null  ## GameManager 反向引用（蓝图解锁评估）

var initial_gold: int = 0
var initial_inspiration: int = 0

var gold: int:
	set(v):
		gold = v
		currency_changed.emit(gold, inspiration)

var inspiration: int:
	set(v):
		inspiration = v
		currency_changed.emit(gold, inspiration)

var inspiration_total_earned: int = 0  ## 累计"获得"的灵感（单调递增），作蓝图解锁阈值


func load_all() -> void:
	gold = initial_gold
	inspiration = initial_inspiration
	_load_inspiration_total()


func add_gold(amount: int) -> void:
	if amount < 0:
		push_warning("add_gold 收到负值 %d，请用 subtract_gold" % amount)
	gold += amount


func subtract_gold(amount: int) -> void:
	add_gold(-amount)


func add_inspiration(amount: int) -> void:
	if amount < 0:
		push_warning("add_inspiration 收到负值 %d，请用 subtract_inspiration" % amount)
		# 负值（花费）不计入累计获得：inspiration_total_earned 只增不减
		inspiration += amount
		return
	inspiration += amount
	inspiration_total_earned += amount
	_save_inspiration_total()
	if owner_mgr != null and owner_mgr.has_method("_evaluate_blueprint_unlocks"):
		owner_mgr._evaluate_blueprint_unlocks(true)


func subtract_inspiration(amount: int) -> void:
	add_inspiration(-amount)


## 订单完成时发放奖励（金币 + 灵感），灵感走累计路径（触发蓝图解锁评估）。
func complete_order(base_reward: Dictionary) -> void:
	var reward_gold: int = base_reward.get("gold", 0)
	var reward_insp: int = base_reward.get("inspiration", 0)
	add_gold(reward_gold)
	add_inspiration(reward_insp)


func _save_inspiration_total() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("inspiration", "total_earned", inspiration_total_earned)
	Utils.write_save_version(cfg)
	if cfg.save(INSPIRATION_TOTAL_SAVE_PATH) != OK:
		push_warning("EconomyManager: 灵感累计存档写入失败 %s" % INSPIRATION_TOTAL_SAVE_PATH)


func _load_inspiration_total() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(INSPIRATION_TOTAL_SAVE_PATH) == OK:
		# 旧档迁移入口：v0（无版本戳）格式与 v1 一致，暂无需转换（见 Utils.SAVE_VERSION）
		if Utils.is_legacy_save(cfg):
			pass
		inspiration_total_earned = int(cfg.get_value("inspiration", "total_earned", 0))
