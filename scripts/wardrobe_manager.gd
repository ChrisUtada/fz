extends Node
class_name WardrobeManager
## WardrobeManager · 穿搭管理（equipped，slot -> item_id；与所有权分离）
##
## 从 GameManager 迁出的「穿搭」真相源。穿搭独立于统一 inventory 的所有权，
## 仅记录当前穿在身上的服装（slot -> item_id），不消耗库存。
## 写操作（equip/unequip）即时存档并广播 equipped_changed。
##
## 设计：门面式子管理器。GameManager 持有本实例并委托转发对外 API，
## 仅保留 signal re-emit 与只读属性兼容（wardrobe.gd / rack_panel.gd 直读 equipped 字典）。

signal equipped_changed   ## 穿搭变化（换装屏 / 展架「拥有-穿戴」监听）

const EQUIPPED_SAVE_PATH := "user://equipped.cfg"
const OLD_WARDROBE_PATH := "user://wardrobe.cfg"   # 旧衣橱穿搭存档（slot -> resource_path），一次性迁移用

## equipped: slot(int) -> item_id(String)。所有权在 inventory[CLOTHING]，穿搭独立于此。
## 展架库存 = 拥有总数 - 穿戴数（穿在身上的不计入可售）。
var equipped: Dictionary = {}        # slot(int) -> item_id(String)


## 当前穿搭快照（slot -> item_id），供换装屏还原遍历（避免直读 equipped 内部字典）。
func get_equipped_dict() -> Dictionary:
	return equipped

## 预留跨域引用（当前穿搭不依赖其他管理器，将来若需反查库存可启用）
var owner_mgr = null


## 载入穿搭存档（含旧档一次性迁移）。由 GameManager._ready 显式调用，不自动 _ready 加载。
func load_all() -> void:
	_load_equipped()


## 穿上：把某槽位设为某 item_id（同槽自动替换）。所有权不变（仍在 inventory）。
func equip(slot: int, item_id: String) -> void:
	if item_id.is_empty():
		return
	equipped[slot] = item_id
	_save_equipped()
	equipped_changed.emit()


## 脱下指定槽位。
func unequip(slot: int) -> void:
	if equipped.has(slot):
		equipped.erase(slot)
		_save_equipped()
		equipped_changed.emit()


func get_equipped(slot: int) -> String:
	return equipped.get(slot, "")


## 某 item_id 当前被穿在几个槽位（通常 0 或 1）。展架库存 = 拥有总数 - 穿戴数。
func get_worn_count(item_id: String) -> int:
	var n := 0
	for s in equipped.keys():
		if equipped[s] == item_id:
			n += 1
	return n


func is_worn(item_id: String) -> bool:
	return get_worn_count(item_id) > 0


func _save_equipped() -> void:
	if equipped.is_empty():
		# 没有任何穿搭 → 删除可能残留的空存档，避免下次加载时读到“无段的文件”报错
		var dir := DirAccess.open("user://")
		if dir != null:
			dir.remove(EQUIPPED_SAVE_PATH)
		return
	var cfg := ConfigFile.new()
	for slot in equipped.keys():
		cfg.set_value("equipped", str(slot), equipped[slot])
	Utils.write_save_version(cfg)
	if cfg.save(EQUIPPED_SAVE_PATH) != OK:
		push_warning("WardrobeManager: 穿搭存档写入失败 %s" % EQUIPPED_SAVE_PATH)


func _load_equipped() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(EQUIPPED_SAVE_PATH) == OK and cfg.has_section("equipped"):
		# 旧档迁移入口：v0（无版本戳）格式与 v1 一致，暂无需转换（见 Utils.SAVE_VERSION）
		if Utils.is_legacy_save(cfg):
			pass
		for slot_str in cfg.get_section_keys("equipped"):
			var vid: String = str(cfg.get_value("equipped", slot_str, ""))
			if not vid.is_empty():
				equipped[int(slot_str)] = vid
		return
	# 无新存档（或文件为空无 equipped 段）→ 尝试从旧 wardrobe.cfg（slot -> resource_path）一次性迁移
	_migrate_old_wardrobe()


## 一次性迁移：旧 wardrobe.cfg 存的是 slot -> ClothesData 资源路径；
## 载入资源取其 id，转成新格式 equipped[slot] = item_id 并存档。
func _migrate_old_wardrobe() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(OLD_WARDROBE_PATH) != OK:
		return
	if not cfg.has_section("equipped"):
		return
	for slot_str in cfg.get_section_keys("equipped"):
		var path: String = str(cfg.get_value("equipped", slot_str, ""))
		if path.is_empty() or not ResourceLoader.exists(path):
			continue
		var data = load(path)
		if data != null and not data.id.is_empty():
			equipped[int(slot_str)] = data.id
	if not equipped.is_empty():
		_save_equipped()
