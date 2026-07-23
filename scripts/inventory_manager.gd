## InventoryManager —— game_manager.gd 上帝单例中拆出的库存子管理器（门面样板）
##
## 职责边界（SRP）：物品注册表、统一库存（inventory: id->count）、分解、制作、
## 物品解锁集合（unlocked_clothes）、起始内容播种 flag（clothing/farm/workshop_seeded）。
##
## 设计：本类由 GameManager（autoload）在 _ready 中实例化并 add_child，GameManager 对外
## 仍暴露等价的 GameManager.add_item / get_count / craft ... 等方法（委托转发），因此全代码库
## 现有的 GameManager.xxx 调用点无需改动。GameManager 仅通过信号 re-emit 把库存变化广播出去。
##
## 与蓝图系统的耦合（craft 需要蓝图是否已解锁 / 取蓝图定义）：通过 owner_mgr 反向引用
## GameManager 查询，避免把蓝图注册表也搬进来（蓝图仍属灵感/活动领域）。
extends Node
class_name InventoryManager

signal inventory_changed         ## 统一库存变化（仓库角标 / 网格监听）

const INVENTORY_SAVE_PATH := "user://inventory.cfg"
const WAREHOUSE_PATH := "user://warehouse.cfg"
const UNLOCKED_CLOTHES_SAVE_PATH := "user://unlocked_clothes.cfg"

var owner_mgr: Node = null      ## 反向引用 GameManager（craft 查蓝图用）；由 GameManager 在 add_child 后赋值

var inventory: Dictionary = {}       # id -> count(int)
var _item_registry: Dictionary = {}  # id -> ItemData（运行时注册，非存档；按 id 解析元数据）
var clothing_seeded: bool = false   # 首次运行是否已播种初始衣橱（防止售出后又被刷回来）
var farm_seeded: bool = false        # 首次运行是否已播种起始种子+花盆（阶段 2.3）
var workshop_seeded: bool = false     # 首次运行是否已发放初始工坊材料（阶段 2.4）
var unlocked_clothes: Dictionary = {}  # id(String) -> true（已解锁服装，持久化）

var _batch_depth: int = 0           ## 批量写盘嵌套深度（begin_batch / commit_batch 之间）
var _batch_dirty: bool = false      ## 批量期间库存是否发生变更（commit 时统一落盘 + 广播）

## 由 GameManager._ready 调用：还原统一 inventory（含旧仓库迁移）与已解锁服装集合。
func load_all() -> void:
	_load_inventory()


## 批量写盘：begin_batch … commit_batch 之间的 add/remove 只标记脏、不落盘不广播，
## commit 时统一 save_inventory() + inventory_changed.emit() 一次。
## 解决 craft / decompose「一次制作 N 材料 = N+1 次写盘 + N+1 次广播」的浪费。支持嵌套（depth 计数）。
func begin_batch() -> void:
	_batch_depth += 1


## 结束一个批量段；仅当回到最外层（depth 归零）且确有变更时，统一落盘 + 广播一次。
func commit_batch() -> void:
	_batch_depth = maxi(0, _batch_depth - 1)
	if _batch_depth == 0 and _batch_dirty:
		_batch_dirty = false
		save_inventory()
		inventory_changed.emit()


## 库存变更通知：批量期间仅置脏；非批量则立即落盘 + 广播（供 add_item / remove_item 调用）。
func _notify_inventory_changed() -> void:
	if _batch_depth > 0:
		_batch_dirty = true
	else:
		save_inventory()
		inventory_changed.emit()


func register_item(data: ItemData) -> void:
	if data != null and not data.id.is_empty():
		_item_registry[data.id] = data


func get_item(id: String) -> ItemData:
	return _item_registry.get(id, null)


func add_item(id: String, n: int = 1) -> void:
	if id.is_empty() or n <= 0:
		return
	inventory[id] = inventory.get(id, 0) + n
	_notify_inventory_changed()


func remove_item(id: String, n: int = 1) -> void:
	if id.is_empty() or not inventory.has(id):
		return
	inventory[id] -= n
	if inventory[id] <= 0:
		inventory.erase(id)
	_notify_inventory_changed()


func has_item(id: String) -> bool:
	return inventory.has(id) and inventory[id] > 0


func get_count(id: String) -> int:
	return inventory.get(id, 0)


## 按分类返回 [{data, count}]（data 经注册表解析；未注册的物品跳过）。
## include_placeable=false 时跳过 is_placeable 物品（默认），避免台灯/桌子等
## 摆进服装/材料等分类标签页（摆放物统一由 get_placeables 收口）。
func get_by_category(cat: int, include_placeable := false) -> Array:
	var out: Array = []
	for id in inventory.keys():
		var d: ItemData = get_item(id)
		if d == null or d.category != cat:
			continue
		if d.is_placeable and not include_placeable:
			continue
		out.append({"data": d, "count": inventory[id]})
	return out


## 返回所有可摆放物品 [{data, count}]（is_placeable=true；data 经注册表解析）
func get_placeables() -> Array:
	var out: Array = []
	for id in inventory.keys():
		var d: ItemData = get_item(id)
		if d != null and d.is_placeable:
			out.append({"data": d, "count": inventory[id]})
	return out


## 返回所有「可作为种植容器」的物品 [{data, count}]（garden_placement=true；data 经注册表解析）。
## 与 get_placeables 区分：后者是「可摆桌面的装饰」，本方法是「可进种植屏功能槽的盆」。
## 种植屏据此自动识别可用花盆，无需写死具体 id（支持未来多盆类型）。
func get_garden_pots() -> Array:
	var out: Array = []
	for id in inventory.keys():
		var d: ItemData = get_item(id)
		if d != null and d.garden_placement:
			out.append({"data": d, "count": inventory[id]})
	return out


func get_total_count() -> int:
	var t := 0
	for id in inventory.keys():
		t += inventory[id]
	return t


## 分解：把 1 个 item_id 按 `decompose_recipe` 产出材料进对应分类库存，原物扣 1。
## 不限 CROP——任何 `decompose_recipe` 非空且持有≥1 的物品都可分解（阶段 0.6 泛化）。
## 返回是否成功（物品已注册 + 有配方 + 持有≥1 才执行）。整个分解包在批量段内，
## 产物 add + 原物 remove 只触发一次落盘 + 一次 inventory_changed 广播。
func decompose(item_id: String) -> bool:
	begin_batch()
	var ok := _decompose_internal(item_id)
	commit_batch()
	return ok


func _decompose_internal(item_id: String) -> bool:
	var data: ItemData = get_item(item_id)
	if data == null or data.decompose_recipe.is_empty():
		return false
	if get_count(item_id) <= 0:
		return false
	for entry in data.decompose_recipe:
		if not entry is Dictionary:
			continue
		# 配方 dict 的 key 可能是 String 或 StringName（取决于 .tres 序列化形式），
		# 统一转成 String key 再读，避免 Godot 4 下 String / StringName 键查找不一致导致漏读。
		var norm := {}
		for k in entry.keys():
			norm[str(k)] = entry[k]
		var out_id: String = str(norm.get("item_id", ""))
		var out_n: int = int(norm.get("count", 0))
		if not out_id.is_empty() and out_n > 0:
			add_item(out_id, out_n)   # 产物按各自 ItemData.category 进库存（MATERIAL 等）
	remove_item(item_id, 1)
	return true


## 制作：消耗蓝图所需材料，产出 output×output_count 进库存（按 output 的 category 归类）。
## 蓝图直接持有材料/产出资源引用（不靠 id 字符串查注册表），故制作逻辑与 _item_registry 解耦。
## 前置：蓝图已注册 + 已解锁 + 材料齐。三项任一不满足即返回 false（不改动库存）。
## 扣材料 + 产出整体包在批量段内，只触发一次落盘 + 一次 inventory_changed 广播（而非 N+1 次）。
## 蓝图「是否已解锁 / 取定义」由 GameManager（owner_mgr）负责，本管理器不持有蓝图注册表。
func craft(blueprint_id: String) -> bool:
	begin_batch()
	var ok := _craft_internal(blueprint_id)
	commit_batch()
	return ok


func _craft_internal(blueprint_id: String) -> bool:
	if owner_mgr == null:
		return false
	var bp: BlueprintData = owner_mgr.get_blueprint(blueprint_id)
	if bp == null:
		return false
	if not owner_mgr.unlocked_blueprints.has(blueprint_id):
		return false
	if bp.output == null:
		return false
	# 先校验材料齐（不足则不动库存直接返回）
	for mc in bp.required_materials:
		if mc == null or mc.item == null or mc.count <= 0:
			continue
		if get_count(mc.item.id) < mc.count:
			return false
	# 扣材料
	for mc in bp.required_materials:
		if mc == null or mc.item == null or mc.count <= 0:
			continue
		remove_item(mc.item.id, mc.count)
	# 产出
	add_item(bp.output.id, bp.output_count)
	# 服装制作完成即永久解锁（衣橱收藏），不影响售卖/库存数量逻辑；
	# commit 时的统一落盘（save_inventory 内已含 unlocked_clothes 持久化）会一并保存。
	if bp.output is ClothesData:
		unlocked_clothes[bp.output.id] = true
	return true


## 返回背包内所有"可分解"物品 [{data, count}]（decompose_recipe 非空且持有>0）。
## 供工坊「分解」子页（阶段 2.4）列出候选；纯数据层，不依赖 UI。
func get_decomposables() -> Array:
	var out: Array = []
	for id in inventory.keys():
		var d: ItemData = get_item(id)
		if d != null and not d.decompose_recipe.is_empty() and inventory[id] > 0:
			out.append({"data": d, "count": inventory[id]})
	return out


# —— 向后兼容包装（旧仓库 API 委托给 inventory；阶段 2.2 仓库屏将直接读 inventory） ——
func unlock_product(id: String) -> void:
	add_item(id, 1)


func has_product(id: String) -> bool:
	return has_item(id)


func get_owned_ids() -> Array:
	return inventory.keys()


func _unlock_internal(id: String) -> void:
	if id.is_empty():
		return
	add_item(id, 1)


func save_inventory() -> void:
	var cfg := ConfigFile.new()
	for id in inventory.keys():
		cfg.set_value("items", id, inventory[id])
	cfg.set_value("meta", "clothing_seeded", clothing_seeded)
	cfg.set_value("meta", "farm_seeded", farm_seeded)
	cfg.set_value("meta", "workshop_seeded", workshop_seeded)
	cfg.save(INVENTORY_SAVE_PATH)
	_save_unlocked_clothes()


## 持久化已解锁服装集合（独立 cfg，避免与 inventory 数量混存）
func _save_unlocked_clothes() -> void:
	var cfg := ConfigFile.new()
	for id in unlocked_clothes.keys():
		cfg.set_value("unlocked", id, true)
	cfg.save(UNLOCKED_CLOTHES_SAVE_PATH)


func _load_inventory() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(INVENTORY_SAVE_PATH) == OK:
		if cfg.has_section("items"):
			for id in cfg.get_section_keys("items"):
				var cnt: int = int(cfg.get_value("items", id, 0))
				if cnt > 0:
					inventory[str(id)] = cnt
		clothing_seeded = bool(cfg.get_value("meta", "clothing_seeded", false))
		farm_seeded = bool(cfg.get_value("meta", "farm_seeded", false))
		workshop_seeded = bool(cfg.get_value("meta", "workshop_seeded", false))
	if inventory.is_empty():
		_migrate_warehouse_to_inventory()
	_load_unlocked_clothes()


## 加载已解锁服装集合。若存档文件缺失（旧版/首次），不在此推导——
## 旧存档自愈交给 _ensure_unlocked_clothes()（注册表就绪后调用），避免注册表未就绪时推导为空。
func _load_unlocked_clothes() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(UNLOCKED_CLOTHES_SAVE_PATH) == OK and cfg.has_section("unlocked"):
		for id in cfg.get_section_keys("unlocked"):
			unlocked_clothes[str(id)] = true


## 旧存档/兜底自愈：注册表就绪后，若 unlocked_clothes 仍空，从当前服装库存推导。
## 仅一次性；之后 unlocked_clothes.cfg 持久化后即为权威，售卖不会清空它。
func _ensure_unlocked_clothes() -> void:
	if not unlocked_clothes.is_empty():
		return
	for entry in get_by_category(ItemData.Category.CLOTHING):
		unlocked_clothes[entry["data"].id] = true
	if not unlocked_clothes.is_empty():
		_save_unlocked_clothes()


## 一次性迁移：旧 warehouse.cfg（id 集合）搬到统一 inventory（count=1）
func _migrate_warehouse_to_inventory() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(WAREHOUSE_PATH) != OK:
		return
	if not cfg.has_section("owned"):
		return
	for id in cfg.get_section_keys("owned"):
		var sid := str(id)
		if not inventory.has(sid):
			inventory[sid] = 1
	save_inventory()
