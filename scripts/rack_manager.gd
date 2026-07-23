extends Node
class_name RackManager
## RackManager · 服装展架管理（在售列表，slot -> item_id；不消耗库存，售出扣 inventory）
##
## 从 GameManager 迁出的展架真相源。展架只记录「展示意愿」，可售数量实时由
## inventory 计数（get_count）决定；售出时经 owner_mgr 扣库存并加金币。
##
## 设计：门面式子管理器。GameManager 持有本实例并委托转发对外 API，
## 仅保留 signal re-emit 与只读属性兼容（rack_panel.gd 直读 clothing_rack 数组）。

signal rack_changed   ## 服装展架状态变化（上架/下架/售出，阶段 4 刷新监听）

const RACK_SLOTS := 6                  # 展架槽数量（阶段 4 暂定 6，与计划一致）
const RACK_SAVE_PATH := "user://rack.cfg"

## clothing_rack: 长度 RACK_SLOTS 的数组，元素为 item_id(String) 或 ""（空槽）。
var clothing_rack: Array = []          # 长度 RACK_SLOTS 的槽数组（元素为 item_id 或 ""）


## 展架槽总数（供展架面板遍历，避免直读 clothing_rack 内部数组）。
func get_rack_count() -> int:
	return clothing_rack.size()

## 反向引用 GameManager（门面），用于跨域访问库存/货币（InventoryManager / EconomyManager）。
var owner_mgr = null


## 载入展架存档（含历史重复槽清理）。由 GameManager._ready 显式调用，不自动 _ready 加载。
func load_all() -> void:
	_load_rack()


## 上架：把某槽设为某 item_id（同槽自动替换）。不校验库存——上架只是「展示意愿」，
## 真正可售数量由 get_rack_stock（在售库存计数）实时算；售出扣的是 inventory。
## 同款仅可占一个槽：若 item_id 已占用其它槽位，本调用直接忽略（防止重复上架分裂库存）。
func display_clothing(slot: int, item_id: String) -> void:
	if slot < 0 or slot >= RACK_SLOTS:
		return
	if item_id.is_empty():
		return
	for i in range(clothing_rack.size()):
		if i != slot and clothing_rack[i] == item_id:
			return
	clothing_rack[slot] = item_id
	_save_rack()
	rack_changed.emit()


## 下架：清空某槽。
func undisplay(slot: int) -> void:
	if slot < 0 or slot >= RACK_SLOTS:
		return
	clothing_rack[slot] = ""
	_save_rack()
	rack_changed.emit()


## 取某槽当前在售 item_id（空槽返回 ""）
func get_rack_item(slot: int) -> String:
	if slot < 0 or slot >= RACK_SLOTS:
		return ""
	return clothing_rack[slot]


## 展架某服装当前可售库存 = 在售库存计数（inventory）。
## 衣橱收藏(unlocked_clothes)与在售库存已分离：穿戴只改 equipped，不消耗 inventory，
## 故可售库存与穿戴状态无关（脱/穿都不会让它变多或变少）。
func get_rack_stock(item_id: String) -> int:
	if item_id.is_empty():
		return 0
	if owner_mgr != null:
		return owner_mgr.get_count(item_id)
	return 0


## 返回所有「有货」展架槽位下标（get_rack_stock > 0），供顾客随机选购
func get_rack_slots_with_stock() -> Array:
	var out: Array = []
	for i in range(clothing_rack.size()):
		var id: String = clothing_rack[i]
		if not id.is_empty() and get_rack_stock(id) > 0:
			out.append(i)
	return out


## 顾客从某槽购买 1 件：加金币(售价) + 扣库存；
## 售出后若仍有货（库存自动补充）则槽保留，否则清空该槽。
## 返回实际获得的金币（槽空 / 无货返回 -1）。
func sell_from_rack(slot: int) -> int:
	if slot < 0 or slot >= clothing_rack.size():
		return -1
	var id: String = clothing_rack[slot]
	if id.is_empty():
		return -1
	if get_rack_stock(id) <= 0:
		# 已被其他顾客买光 / 被换装穿走：清空槽，顾客离开
		clothing_rack[slot] = ""
		_save_rack()
		rack_changed.emit()
		return -1
	var data: ItemData = owner_mgr.get_item(id) if owner_mgr != null else null
	var price: int = data.price if data != null else 0
	if owner_mgr != null:
		owner_mgr.add_gold(price)
		owner_mgr.remove_item(id, 1)
	if get_rack_stock(id) <= 0:
		clothing_rack[slot] = ""   # 售罄清空
	_save_rack()
	rack_changed.emit()
	return price


## 返回可上架服装 [{id, data, available}]，available = 在售库存计数(>0)；
## 衣橱收藏(unlocked_clothes)与在售库存(inventory)已分离：此处只认“在售库存”，
## 与穿戴状态无关（脱/穿都不影响可上架性）。已上架的款式不再列出（每款仅可占一个槽）。
func get_displayable_clothing() -> Array:
	var out: Array = []
	var entries = owner_mgr.get_by_category(ItemData.Category.CLOTHING) if owner_mgr != null else []
	for entry in entries:
		var id: String = entry["data"].id
		if clothing_rack.has(id):   # 已占某个槽 → 不再列为可上架，防止同款多槽
			continue
		var avail: int = owner_mgr.get_count(id) if owner_mgr != null else 0
		if avail > 0:
			out.append({"id": id, "data": entry["data"], "available": avail})
	return out


func _save_rack() -> void:
	var cfg := ConfigFile.new()
	for i in range(clothing_rack.size()):
		cfg.set_value("rack", "slot_%d" % i, clothing_rack[i])
	Utils.write_save_version(cfg)
	if cfg.save(RACK_SAVE_PATH) != OK:
		push_warning("RackManager: 展架存档写入失败 %s" % RACK_SAVE_PATH)


func _load_rack() -> void:
	clothing_rack = []
	var cfg := ConfigFile.new()
	if cfg.load(RACK_SAVE_PATH) == OK:
		# 旧档迁移入口：v0（无版本戳）格式与 v1 一致，暂无需转换（见 Utils.SAVE_VERSION）
		if Utils.is_legacy_save(cfg):
			pass
		for i in range(RACK_SLOTS):
			clothing_rack.append(str(cfg.get_value("rack", "slot_%d" % i, "")))
	while clothing_rack.size() < RACK_SLOTS:
		clothing_rack.append("")
	clothing_rack = clothing_rack.slice(0, RACK_SLOTS)
	# 清理历史存档：旧逻辑允许同款占多槽，这里保留首次出现、清空其余重复槽，并落盘
	var seen: Dictionary = {}
	var dup_found := false
	for i in range(clothing_rack.size()):
		var id: String = clothing_rack[i]
		if id.is_empty():
			continue
		if seen.has(id):
			clothing_rack[i] = ""
			dup_found = true
		else:
			seen[id] = true
	if dup_found:
		_save_rack()
