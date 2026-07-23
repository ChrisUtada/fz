class_name FarmManager
extends Node
# FarmManager · 种植槽（阶段 0.9 / 2.3）子管理器
## 从 GameManager 迁出的农场槽逻辑：纯数据层 + 墙钟计时。
## 状态机：空 → place_pot → plant → (compute_stage 进入成熟) → harvest / clear_slot。
## 跨域访问经 owner_mgr（库存 InventoryManager）：get_item / has_item / remove_item / add_item。

signal farm_changed                ## 农场槽状态变化（种植屏 2.3 刷新监听）

const FARM_SLOTS := 6                  # 种植屏功能槽数量（阶段 2.3 暂定 6，商店扩容后续再定）
const FARM_SAVE_PATH := "user://farm.cfg"

var owner_mgr = null                  # GameManager（门面），用于跨域访问库存

## 每槽状态机：空 → 有盆(place_pot) → 已种(plant) → 成熟(harvest)
## 槽结构 Dictionary：{pot_id, seed_id, planted_unix, done}
var farm_slots: Array = []             # 长度 FARM_SLOTS 的槽数组（元素为上述 Dictionary）


## 由 GameManager._ready 在库存就绪后调用（农场加载不依赖 orders/blueprints）。
func load_all() -> void:
	_load_farm()


func _make_empty_slot() -> Dictionary:
	return {"pot_id": "", "seed_id": "", "planted_unix": 0, "done": false}


## 在指定槽放入一个花盆（从 inventory 取 1 个可摆放的盆，pot_id 指向 is_placeable 物品）。仅空槽（无盆）可放。返回是否成功。
func place_pot(slot: int, pot_id: String) -> bool:
	if slot < 0 or slot >= farm_slots.size():
		return false
	var s: Dictionary = farm_slots[slot]
	if not s.get("pot_id", "").is_empty():
		return false                       # 槽里已有盆
	if owner_mgr == null or not owner_mgr.has_item(pot_id):
		return false                       # 库存没有该花盆
	owner_mgr.remove_item(pot_id, 1)      # 花盆进入槽内（离开库存）
	s["pot_id"] = pot_id
	_save_farm()
	farm_changed.emit()
	return true


## 在已有花盆的槽内种入种子（从 inventory[SEED] 取 1 个）。返回是否成功。
## 与 place_pot 分离：贴合阶段 2.3「先放盆、再放种子」两步 UI 流程。
func plant(slot: int, seed_id: String) -> bool:
	if slot < 0 or slot >= farm_slots.size():
		return false
	var s: Dictionary = farm_slots[slot]
	if s.get("pot_id", "").is_empty():
		return false                       # 没有盆不能种
	if not s.get("seed_id", "").is_empty():
		return false                       # 已种，先 harvest/clear 再种
	var sd: SeedData = owner_mgr.get_item(seed_id) if owner_mgr != null else null
	if sd == null or not (sd is SeedData):
		return false                       # 未注册或不是种子
	if owner_mgr == null or not owner_mgr.has_item(seed_id):
		return false                       # 库存没有该种子
	owner_mgr.remove_item(seed_id, 1)
	s["seed_id"] = seed_id
	s["planted_unix"] = int(Time.get_unix_time_from_system())
	s["done"] = false
	_save_farm()
	farm_changed.emit()
	return true


## 当前生长阶段：0=苗 / 1=成长 / 2=成熟；空槽或槽内无种子返回 -1。
## 按 SeedData 三阶段时长 + 当前墙钟实时计算（挂机续算）。
func compute_stage(slot: int) -> int:
	if slot < 0 or slot >= farm_slots.size():
		return -1
	var s: Dictionary = farm_slots[slot]
	var seed_id: String = s.get("seed_id", "")
	if seed_id.is_empty():
		return -1
	var sd: SeedData = owner_mgr.get_item(seed_id) if owner_mgr != null else null
	if sd == null or not (sd is SeedData):
		return -1
	var grown_min := (Time.get_unix_time_from_system() - float(s.get("planted_unix", 0))) / 60.0
	return sd.stage_at(grown_min)


## 是否成熟（可采摘）。
func is_slot_mature(slot: int) -> bool:
	return compute_stage(slot) == 2


## 生长信息（供种植屏 2.3 实时刷新进度条/剩余时间）：
## {stage, stage_name, progress(0..1 全程), elapsed_sec, remaining_sec, total_sec}
## 空槽/无种子返回空字典。
func get_growth_info(slot: int) -> Dictionary:
	if slot < 0 or slot >= farm_slots.size():
		return {}
	var s: Dictionary = farm_slots[slot]
	var seed_id: String = s.get("seed_id", "")
	if seed_id.is_empty():
		return {}
	var sd: SeedData = owner_mgr.get_item(seed_id) if owner_mgr != null else null
	if sd == null or not (sd is SeedData):
		return {}
	var s_min := float(maxi(1, sd.sprout_minutes))
	var g_min := float(maxi(1, sd.growing_minutes))
	var m_min := float(maxi(1, sd.mature_minutes))
	var _t_sprout := s_min * 60.0
	var _t_grow := (s_min + g_min) * 60.0
	var t_mature := (s_min + g_min + m_min) * 60.0
	var elapsed := float(Time.get_unix_time_from_system() - float(s.get("planted_unix", 0)))
	var stage := sd.stage_at(elapsed / 60.0)
	var names := ["苗", "成长", "成熟"]
	return {
		"stage": stage,
		"stage_name": names[stage],
		"progress": clampf(elapsed / t_mature, 0.0, 1.0),
		"elapsed_sec": maxf(0.0, elapsed),
		"remaining_sec": maxf(0.0, t_mature - elapsed),
		"total_sec": t_mature
	}


## 采摘：成熟槽产出 crop_output（直接引用的 CROP 物品）进 inventory[CROP]，清空种子状态（花盆保留，可立即重种）。返回是否成功。
func harvest(slot: int) -> bool:
	if slot < 0 or slot >= farm_slots.size():
		return false
	if not is_slot_mature(slot):
		return false
	var s: Dictionary = farm_slots[slot]
	var sd: SeedData = owner_mgr.get_item(s.get("seed_id", "")) if owner_mgr != null else null
	if sd == null or not (sd is SeedData) or sd.crop_output == null:
		return false
	if owner_mgr != null:
		owner_mgr.add_item(sd.crop_output.id, 1)     # 作物按 category=CROP 进库存（关系本身已是直接引用）
	s["seed_id"] = ""
	s["planted_unix"] = 0
	s["done"] = false
	_save_farm()
	farm_changed.emit()
	return true


## 清空槽：花盆退回 inventory（作为 is_placeable 物品回收），重置种子状态（回收花盆用）。返回是否成功。
func clear_slot(slot: int) -> bool:
	if slot < 0 or slot >= farm_slots.size():
		return false
	var s: Dictionary = farm_slots[slot]
	if s.get("pot_id", "").is_empty():
		return false
	if owner_mgr != null:
		owner_mgr.add_item(s.get("pot_id", ""), 1)     # 花盆退回库存
	s["pot_id"] = ""
	s["seed_id"] = ""
	s["planted_unix"] = 0
	s["done"] = false
	_save_farm()
	farm_changed.emit()
	return true


func _save_farm() -> void:
	var cfg := ConfigFile.new()
	for i in range(farm_slots.size()):
		var s: Dictionary = farm_slots[i]
		var sec := "slot_%d" % i
		cfg.set_value(sec, "pot_id", s.get("pot_id", ""))
		cfg.set_value(sec, "seed_id", s.get("seed_id", ""))
		cfg.set_value(sec, "planted_unix", int(s.get("planted_unix", 0)))
		cfg.set_value(sec, "done", bool(s.get("done", false)))
	cfg.save(FARM_SAVE_PATH)


func _load_farm() -> void:
	farm_slots = []
	var cfg := ConfigFile.new()
	if cfg.load(FARM_SAVE_PATH) == OK:
		for i in range(FARM_SLOTS):
			var sec := "slot_%d" % i
			if not cfg.has_section(sec):
				farm_slots.append(_make_empty_slot())
				continue
			farm_slots.append({
				"pot_id": str(cfg.get_value(sec, "pot_id", "")),
				"seed_id": str(cfg.get_value(sec, "seed_id", "")),
				"planted_unix": int(cfg.get_value(sec, "planted_unix", 0)),
				"done": bool(cfg.get_value(sec, "done", false))
			})
	while farm_slots.size() < FARM_SLOTS:
		farm_slots.append(_make_empty_slot())
	farm_slots = farm_slots.slice(0, FARM_SLOTS)
