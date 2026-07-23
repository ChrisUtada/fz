extends Node
## GameManager · 全局状态管理（唯一 autoload 单例）
## 职责：
##   - 持有 gold / inspiration 货币状态
##   - 管理“灵感活动”计时与离线收益结算
##   - 管理“电话购物”订单计时与离线到货结算
##   - 管理统一的 inventory 库存（跨场景唯一真相源；物品元数据按 id 从注册表解析）
## 原则：低耦合 —— 其他节点通过 signal 订阅变化，不直接读写内部字段。
##       计时采用真实墙钟时间戳（get_unix_time_from_system）+ 存档，
##       因此关掉游戏再打开也能按真实流逝时间结算（离线收益）。

signal currency_changed(new_gold: int, new_inspiration: int)
signal activity_started
signal activity_finished(reward: Dictionary)
signal activity_cancelled
signal activity_interrupted(interrupts: int)  ## 番茄钟进行中发生一次打断（带累计次数）
signal activity_streak_changed(streak: int)  ## 连击数变化（完成 +1 / 放弃归零）

# ─── 电话购物 / 仓库 信号 ───
signal orders_changed            ## 进行中订单列表变化（下单 / 到货移出）
signal order_arrived(id: String, name: String)  ## 某订单配送完成（进入待收）
signal arrived_changed          ## 待收列表变化（影响电话「已到货」提示）
signal warehouse_changed        ## 库存变化（入库，向后兼容；新代码建议用 inventory_changed）
signal inventory_changed         ## 统一库存变化（仓库角标 / 网格监听）
signal equipped_changed          ## 穿搭变化（换装屏 / 展架「拥有-穿戴」监听）
signal blueprint_unlocked(id: String)  ## 某蓝图刚达阈值解锁（工坊 UI 实时点亮）
signal farm_changed                ## 农场槽状态变化（种植屏 2.3 刷新监听）
signal rack_changed               ## 服装展架状态变化（上架/下架/售出，阶段 4 刷新监听）

# ─── 库存子管理器（InventoryManager 门面；库存真相源已迁出，详见 inventory_manager.gd） ───
## 所有库存读写现在委托给 InventoryManager；本 autoload 仅保留对外兼容 API 与信号 re-emit。
var inventory_mgr: InventoryManager = null
var farm_mgr: FarmManager = null
## 已解锁服装集合（兼容属性）；UI 现经 get_unlocked_clothing_ids() 收口读取，转发到子管理器。
var unlocked_clothes: Dictionary:
	get:
		return inventory_mgr.unlocked_clothes if inventory_mgr != null else {}

# ─── 穿搭子管理器（WardrobeManager 门面；equipped 真相源已迁出，详见 wardrobe_manager.gd） ───
## 所有穿搭读写现在委托给 WardrobeManager；本 autoload 仅保留对外兼容 API 与信号 re-emit。
var wardrobe_mgr: WardrobeManager = null
## 当前穿搭字典（兼容属性）；UI 现经 get_equipped_dict() 收口读取，转发到子管理器。
var equipped: Dictionary:
	get:
		return wardrobe_mgr.equipped if wardrobe_mgr != null else {}

# ─── 灵感累计 & 蓝图解锁（阶段 0.8） ───
const BLUEPRINTS_SAVE_PATH := "user://blueprints.cfg"
const BLUEPRINTS_DIR := "res://data/blueprints/"
var _blueprint_registry: Dictionary = {}  # id -> BlueprintData（启动时加载，非存档）
var unlocked_blueprints: Dictionary = {}  # id -> true（已解锁；含存档恢复 + 阈值达成）

# ─── 农场槽（种植玩法，阶段 0.9）门面委托 ───
## 每槽状态机：空 → 有盆(place_pot) → 已种(plant) → 成熟(harvest)
## 槽结构 Dictionary：{pot_id, seed_id, planted_unix, done}
##   pot_id：     摆放物(花盆) id，空=无盆
##   seed_id：     已种种子 id，空=未种
##   planted_unix：种下时的墙钟时间戳（秒）；未种=0
##   done：        预留标志（当前恒为 false，成熟判断以 compute_stage 实时算为准）
## 墙钟计时：关游戏再开按真实流逝时间续算（挂机友好），无需常驻进程。
var farm_slots: Array:
	get: return farm_mgr.farm_slots if farm_mgr != null else []

# ─── 展架子管理器（RackManager 门面；clothing_rack 真相源已迁出，详见 rack_manager.gd） ───
## 所有展架读写现在委托给 RackManager；本 autoload 仅保留对外兼容 API 与信号 re-emit。
var rack_mgr: RackManager = null
## 展架数组（兼容属性）；转发到子管理器。rack_panel 现经 get_rack_count() 收口读取总数。
var clothing_rack: Array:
	get:
		return rack_mgr.clothing_rack if rack_mgr != null else []

## 已解锁/已收藏服装集合（id -> true），与 inventory 的「当前库存数量」彻底解耦。
## 设计意图：衣橱 = 永久收藏（种子/制作即解锁，永远在衣橱里），仓库 = 当前数量（受制作/售出影响）。
## 因此售卖只动 inventory.count，永不动本集合；本集合只在 seed_starter_clothing / craft 产出服装时写入。
# ─── 经济管理（委托给 EconomyManager） ───
var economy_mgr: EconomyManager = null

# ─── 活动管理（委托给 ActivityManager） ───
var activity_mgr: ActivityManager = null

var gold: int:
	get: return economy_mgr.gold if economy_mgr != null else 0

var inspiration: int:
	get: return economy_mgr.inspiration if economy_mgr != null else 0

var inspiration_total_earned: int:
	get: return economy_mgr.inspiration_total_earned if economy_mgr != null else 0

# ─── 电话订单（墙钟 + 存档，支持离线到货） ───
const ORDER_SAVE_PATH := "user://phone_orders.json"

var _orders: Array = []      # 进行中订单：[ {id, name, start_unix, duration_sec}, ... ]
var _arrived: Array = []      # 待收货物：[ {id, name}, ... ]

# ─── UI 模态标志（覆盖层弹窗是否打开） ───
## 覆盖层弹窗（产品目录/订单中心/仓库/换装/灵感）打开时置真，由 Main 每帧同步。
## 顾客/宠物/电话/摆放物在 _input 阶段据此自我屏蔽：弹窗开着时不再抢占点击，
## 否则游荡的顾客会用 set_input_as_handled 吃掉落在其身上的点击，
## 导致弹窗按钮（如「去商城」）偶发点不动。
var _modal_open: bool = false

func set_modal_open(v: bool) -> void:
	_modal_open = v

func is_modal_open() -> bool:
	return _modal_open


func _ready() -> void:
	# 经济管理子管理器
	economy_mgr = EconomyManager.new()
	add_child(economy_mgr)
	economy_mgr.owner_mgr = self
	economy_mgr.currency_changed.connect(_on_currency_changed)
	economy_mgr.load_all()
	# 库存子管理器
	inventory_mgr = InventoryManager.new()
	add_child(inventory_mgr)
	inventory_mgr.owner_mgr = self
	inventory_mgr.inventory_changed.connect(_on_inventory_changed)
	inventory_mgr.load_all()
	# 活动子管理器：load_all 内含连击还原 + 灵感活动离线补发（同时创建 GlobalInput 节点）
	activity_mgr = ActivityManager.new()
	add_child(activity_mgr)
	activity_mgr.owner_mgr = self
	activity_mgr.activity_started.connect(func(): activity_started.emit())
	activity_mgr.activity_finished.connect(func(r): activity_finished.emit(r))
	activity_mgr.activity_cancelled.connect(func(): activity_cancelled.emit())
	activity_mgr.activity_interrupted.connect(func(n): activity_interrupted.emit(n))
	activity_mgr.activity_streak_changed.connect(func(s): activity_streak_changed.emit(s))
	activity_mgr.load_all()
	# 穿搭子管理器：load_all 内含旧档一次性迁移
	wardrobe_mgr = WardrobeManager.new()
	add_child(wardrobe_mgr)
	wardrobe_mgr.owner_mgr = self
	wardrobe_mgr.equipped_changed.connect(func(): equipped_changed.emit())
	wardrobe_mgr.load_all()
	# 种植子管理器：load_all 内含农场槽存档读取（挂机续算）
	farm_mgr = FarmManager.new()
	add_child(farm_mgr)
	farm_mgr.owner_mgr = self
	farm_mgr.farm_changed.connect(func(): farm_changed.emit())
	_load_orders()
	_load_blueprints()
	farm_mgr.load_all()
	# 展架子管理器：load_all 内含历史重复槽清理
	rack_mgr = RackManager.new()
	add_child(rack_mgr)
	rack_mgr.owner_mgr = self
	rack_mgr.rack_changed.connect(func(): rack_changed.emit())
	rack_mgr.load_all()

func _process(_delta: float) -> void:
	_tick_orders()   # 订单轮询；活动计时/外出统计由 ActivityManager._process 接管

# ═══════════════════ 货币 ═══════════════════

func add_gold(amount: int) -> void:
	if economy_mgr != null:
		economy_mgr.add_gold(amount)

func subtract_gold(amount: int) -> void:
	if economy_mgr != null:
		economy_mgr.subtract_gold(amount)

func add_inspiration(amount: int) -> void:
	if economy_mgr != null:
		economy_mgr.add_inspiration(amount)

func subtract_inspiration(amount: int) -> void:
	if economy_mgr != null:
		economy_mgr.subtract_inspiration(amount)

func complete_order(base_reward: Dictionary) -> void:
	if economy_mgr != null:
		economy_mgr.complete_order(base_reward)

# ═══════════════════ 灵感活动（委托给 ActivityManager） ═══════════════════
func start_activity(data: ActivityData, minutes: int) -> bool:
	if activity_mgr != null:
		return activity_mgr.start_activity(data, minutes)
	return false

func cancel_activity() -> void:
	if activity_mgr != null:
		activity_mgr.cancel_activity()

func is_activity_running() -> bool:
	return activity_mgr.is_activity_running() if activity_mgr != null else false

func register_interrupt() -> void:
	if activity_mgr != null:
		activity_mgr.register_interrupt()

func get_activity_interrupts() -> int:
	return activity_mgr.get_activity_interrupts() if activity_mgr != null else 0

## 打断衰减系数（委托到 ActivityManager.get_reward_factor，UI 只读，避免双处维护魔法数）
func get_reward_factor() -> float:
	return activity_mgr.get_reward_factor() if activity_mgr != null else 1.0

func get_active_activity_name() -> String:
	return activity_mgr.get_active_activity_name() if activity_mgr != null else ""

func get_activity_mode() -> int:
	return activity_mgr.get_activity_mode() if activity_mgr != null else 0

func get_activity_streak() -> int:
	return activity_mgr.get_activity_streak() if activity_mgr != null else 0

func get_outing_error() -> String:
	return activity_mgr.get_outing_error() if activity_mgr != null else ""

func get_outing_counts() -> Dictionary:
	return activity_mgr.get_outing_counts() if activity_mgr != null else {"total": 0, "active": false}

func finish_outing() -> void:
	if activity_mgr != null:
		activity_mgr.finish_outing()

func get_remaining_sec() -> float:
	return activity_mgr.get_remaining_sec() if activity_mgr != null else 0.0

func get_activity_total_sec() -> float:
	return activity_mgr.get_activity_total_sec() if activity_mgr != null else 0.0

func get_pending_reward() -> int:
	return activity_mgr.get_pending_reward() if activity_mgr != null else 0



# ═══════════════════ 电话订单（多订单并行 + 墙钟 + 存档） ═══════════════════

## 下单：校验金币 → 扣款 → 记录进行中订单（墙钟时间戳）→ 立即存档。返回是否成功。
## 下单：扣金币、建订单（按配送时长墙钟计时）。接收任意 ItemData（ProductData 走商品配送时长，
## SeedData 等无 delivery_minutes 的用默认 5 分钟），到货后 confirm_receipt 按 id 入库。
func start_order(product: ItemData) -> bool:
	if product == null:
		return false
	if gold < product.price:
		return false
	subtract_gold(product.price)
	var duration_sec: float = 5.0 * 60.0          # 默认配送时长（适用于种子等无 delivery_minutes 的物品）
	if product is ProductData:
		duration_sec = float(product.delivery_minutes) * 60.0
	var order := {
		"id": product.id,
		"name": product.display_name,
		"start_unix": int(Time.get_unix_time_from_system()),
		"duration_sec": duration_sec
	}
	_orders.append(order)
	_save_orders()
	orders_changed.emit()
	return true


## 返回进行中订单快照（含实时剩余秒数与进度 0~1），供电话 UI 刷新。
func get_orders() -> Array:
	var now := Time.get_unix_time_from_system()
	var out: Array = []
	for o in _orders:
		var elapsed := now - int(o["start_unix"])
		var remaining := maxf(0.0, float(o["duration_sec"]) - elapsed)
		var progress := clampf(float(elapsed) / float(o["duration_sec"]), 0.0, 1.0)
		out.append({
			"id": o["id"],
			"name": o["name"],
			"remaining_sec": remaining,
			"progress": progress
		})
	return out


## 返回待收货物快照（已到货未领取）。返回副本，避免外部改动内部。
func get_arrived() -> Array:
	return _arrived.duplicate()


## 是否有待收货物（决定电话点击 → 打开收货清单 or 产品目录）。
func has_arrived() -> bool:
	return not _arrived.is_empty()


## 确认收货：把全部待收货物解锁进仓库、清空待收、存档。返回是否有货物被领取。
func confirm_receipt() -> bool:
	if _arrived.is_empty():
		return false
	for a in _arrived:
		_unlock_internal(a["id"])
	_arrived.clear()
	_save_orders()
	arrived_changed.emit()
	warehouse_changed.emit()
	return true


## 领取单个到货：解锁进仓库、从待收移除、存档、发信号。供订单中心逐件领取。
func confirm_receipt_one(id: String) -> void:
	var idx := -1
	for i in range(_arrived.size()):
		if _arrived[i]["id"] == id:
			idx = i
			break
	if idx < 0:
		return
	_unlock_internal(_arrived[idx]["id"])
	_arrived.remove_at(idx)
	_save_orders()
	arrived_changed.emit()
	warehouse_changed.emit()


func _tick_orders() -> void:
	if _orders.is_empty():
		return
	var now := Time.get_unix_time_from_system()
	var arrived_something := false
	# 倒序遍历，便于安全移除
	for i in range(_orders.size() - 1, -1, -1):
		var o: Dictionary = _orders[i]
		var elapsed := now - int(o["start_unix"])
		if elapsed >= float(o["duration_sec"]):
			_orders.remove_at(i)
			_arrived.append({"id": o["id"], "name": o["name"]})
			arrived_something = true
			order_arrived.emit(o["id"], o["name"])
	if arrived_something:
		_save_orders()
		orders_changed.emit()
		arrived_changed.emit()


# ═══════════════════ 统一库存（inventory，跨场景唯一真相源） ═══════════════════
## inventory: id -> count(int)。物品元数据(data) 由 _item_registry 在运行时按 id 解析，
## 这样避免 autoload(GameManager) 在 main 注册物品前就需要实例数据，载入顺序更稳。

## 运行时注册物品元数据（main 在 _ready 把 product_pool 等注册进来）
## 委托给 InventoryManager.register_item（物品注册表已迁出）
func register_item(data: ItemData) -> void:
	if inventory_mgr != null:
		inventory_mgr.register_item(data)


## 运行时注册蓝图定义（main 在 _ready 把 blueprint_pool 注册进来；导出构建中 DirAccess 扫描不可靠，静态池兜底）
func register_blueprint(data: BlueprintData) -> void:
	if data != null and not data.id.is_empty():
		_blueprint_registry[data.id] = data


func get_item(id: String) -> ItemData:
	return inventory_mgr.get_item(id) if inventory_mgr != null else null

func add_item(id: String, n: int = 1) -> void:
	if inventory_mgr != null:
		inventory_mgr.add_item(id, n)

func remove_item(id: String, n: int = 1) -> void:
	if inventory_mgr != null:
		inventory_mgr.remove_item(id, n)

## 批量写盘门面转发：begin_batch … commit_batch 之间经 InventoryManager 的一切
## add/remove 只标记脏，commit 时统一落盘 + 广播一次（供未来多步批量操作复用）。
func begin_batch() -> void:
	if inventory_mgr != null:
		inventory_mgr.begin_batch()

func commit_batch() -> void:
	if inventory_mgr != null:
		inventory_mgr.commit_batch()

func has_item(id: String) -> bool:
	return inventory_mgr.has_item(id) if inventory_mgr != null else false

func get_count(id: String) -> int:
	return inventory_mgr.get_count(id) if inventory_mgr != null else 0


## 已解锁/已收藏服装 id 列表（门面转发 InventoryManager，供衣橱面板遍历）。
func get_unlocked_clothing_ids() -> Array:
	return inventory_mgr.get_unlocked_clothing_ids() if inventory_mgr != null else []

func get_by_category(cat: int, include_placeable := false) -> Array:
	return inventory_mgr.get_by_category(cat, include_placeable) if inventory_mgr != null else []

func get_placeables() -> Array:
	return inventory_mgr.get_placeables() if inventory_mgr != null else []

func get_garden_pots() -> Array:
	return inventory_mgr.get_garden_pots() if inventory_mgr != null else []

func get_total_count() -> int:
	return inventory_mgr.get_total_count() if inventory_mgr != null else 0

func decompose(item_id: String) -> bool:
	return inventory_mgr.decompose(item_id) if inventory_mgr != null else false

func craft(blueprint_id: String) -> bool:
	return inventory_mgr.craft(blueprint_id) if inventory_mgr != null else false

func get_decomposables() -> Array:
	return inventory_mgr.get_decomposables() if inventory_mgr != null else []

func unlock_product(id: String) -> void:
	if inventory_mgr != null:
		inventory_mgr.unlock_product(id)

func has_product(id: String) -> bool:
	return inventory_mgr.has_product(id) if inventory_mgr != null else false

func get_owned_ids() -> Array:
	return inventory_mgr.get_owned_ids() if inventory_mgr != null else []

func _unlock_internal(id: String) -> void:
	if inventory_mgr != null:
		inventory_mgr._unlock_internal(id)

## 委托给 InventoryManager（旧存档自愈：注册表就绪后从服装库存推导已解锁集合）
func _ensure_unlocked_clothes() -> void:
	if inventory_mgr != null:
		inventory_mgr._ensure_unlocked_clothes()

## InventoryManager 库存变化 → 在 GameManager 上 re-emit，保持对外 API 兼容
func _on_inventory_changed() -> void:
	inventory_changed.emit()

func _on_currency_changed(new_gold: int, new_insp: int) -> void:
	currency_changed.emit(new_gold, new_insp)



## 一次性播种：首次运行把设计池中的服装各发 1 件作为初始衣橱。
## 带 _clothing_seeded flag 持久化，避免玩家售出/分解服装后下次启动又被刷回来。
## main._ready 在注册服装池后调用一次即可。
func seed_starter_clothing(pool: Array) -> void:
	if inventory_mgr == null or inventory_mgr.clothing_seeded:
		return
	for c in pool:
		if c != null and not c.id.is_empty():
			inventory_mgr.unlocked_clothes[c.id] = true   # 初始衣橱即解锁（个人收藏，永不售、永不进展架；不占 inventory 库存）
	inventory_mgr.clothing_seeded = true
	inventory_mgr.save_inventory()           # 内含 _save_unlocked_clothes
	inventory_changed.emit()


## 一次性播种：首次运行给起始种子（每款各 2 粒）+ 花盆若干，让种植屏开箱即用。
## 带 _farm_seeded flag 持久化，避免玩家用掉后又被刷回来。
## seed_ids 来自 main 的种子池；pot_id 为花盆物品 id（与 product_pot.tres 对齐）。
func seed_starter_farm(seed_ids: Array, pot_id: String, pot_count: int) -> void:
	if inventory_mgr == null or inventory_mgr.farm_seeded:
		return
	for sid in seed_ids:
		if not sid.is_empty() and not inventory_mgr.inventory.has(sid):
			inventory_mgr.inventory[sid] = 2
	if not pot_id.is_empty() and not inventory_mgr.inventory.has(pot_id):
		inventory_mgr.inventory[pot_id] = pot_count
	inventory_mgr.farm_seeded = true
	inventory_mgr.save_inventory()
	inventory_changed.emit()


## 一次性发放工坊起始材料（红染料、纤维、可分解作物）。
## 改为自愈逻辑：不依赖 flag，每次启动检查库存是否达到目标数量，不足就补。
## 这样即使存档状态不一致（之前运行过有 bug 的版本）也能自愈。
func seed_starter_workshop(materials: Dictionary) -> void:
	if inventory_mgr == null:
		return
	var changed := false
	for iid in materials:
		var target: int = int(materials[iid])
		if iid.is_empty() or target <= 0:
			continue
		var have: int = int(inventory_mgr.inventory.get(iid, 0))
		if have < target:
			inventory_mgr.inventory[iid] = target    # 补到目标数量（不覆盖已有的更多）
			changed = true
	if changed:
		inventory_mgr.save_inventory()
		inventory_changed.emit()


# ═════════════════════ 穿搭（equipped，slot -> item_id；与所有权分离） ═════════════════════
## 以下方法为 WardrobeManager 的委托转发；内部状态与存档见 wardrobe_manager.gd。

## 穿上：把某槽位设为某 item_id（同槽自动替换）。所有权不变（仍在 inventory）。
func equip(slot: int, item_id: String) -> void:
	if wardrobe_mgr != null:
		wardrobe_mgr.equip(slot, item_id)

## 脱下指定槽位。
func unequip(slot: int) -> void:
	if wardrobe_mgr != null:
		wardrobe_mgr.unequip(slot)

func get_equipped(slot: int) -> String:
	return wardrobe_mgr.get_equipped(slot) if wardrobe_mgr != null else ""

## 某 item_id 当前被穿在几个槽位（通常 0 或 1）。展架库存 = 拥有总数 - 穿戴数。
func get_worn_count(item_id: String) -> int:
	return wardrobe_mgr.get_worn_count(item_id) if wardrobe_mgr != null else 0

func is_worn(item_id: String) -> bool:
	return wardrobe_mgr.is_worn(item_id) if wardrobe_mgr != null else false


## 当前穿搭快照（门面转发 WardrobeManager，供换装屏还原遍历）。
func get_equipped_dict() -> Dictionary:
	return wardrobe_mgr.get_equipped_dict() if wardrobe_mgr != null else {}

# ═════════════════════ 灵感累计 & 蓝图解锁（阶段 0.8） ═══════════════════
## 灵感累计（inspiration_total_earned）已迁至 EconomyManager；蓝图解锁逻辑如下。


## 启动时把 res://data/blueprints/ 下全部 BlueprintData 载入注册表，并恢复已解锁状态；
## 随后静默解锁已达阈值的蓝图（emit=false：避免启动刷一堆"新解锁"通知）。
func _load_blueprints() -> void:
	_blueprint_registry.clear()
	var dir := DirAccess.open(BLUEPRINTS_DIR)
	if dir != null:
		for fname in dir.get_files():
			if not (fname.ends_with(".tres") or fname.ends_with(".res")):
				continue
			var bp = load(BLUEPRINTS_DIR + fname)
			if bp is BlueprintData and not bp.id.is_empty():
				_blueprint_registry[bp.id] = bp
	else:
		push_warning("蓝图目录扫描失败（导出构建常见），将依赖 Main 的静态 blueprint_pool 兜底")
	# 恢复已解锁存档（阈值日后提高也不会回锁）
	var cfg := ConfigFile.new()
	if cfg.load(BLUEPRINTS_SAVE_PATH) == OK and cfg.has_section("unlocked"):
		# 旧档迁移入口：v0（无版本戳）格式与 v1 一致，暂无需转换（见 Utils.SAVE_VERSION）
		if Utils.is_legacy_save(cfg):
			pass
		for id in cfg.get_section_keys("unlocked"):
			var uid: String = str(id)
			if _blueprint_registry.has(uid):
				unlocked_blueprints[uid] = true
	_evaluate_blueprint_unlocks(false)


## 评估并解锁达阈值的蓝图。emit=true 时对"新"解锁发 blueprint_unlocked（游戏中）；
## 启动初始 pass 传 false。已解锁的永远不会被回收（阈值提高也不回锁）。
func _evaluate_blueprint_unlocks(emit: bool) -> void:
	var changed := false
	for id in _blueprint_registry.keys():
		if unlocked_blueprints.has(id):
			continue
		var bp: BlueprintData = _blueprint_registry[id]
		if inspiration_total_earned >= bp.unlock_inspiration:
			unlocked_blueprints[id] = true
			changed = true
			if emit:
				blueprint_unlocked.emit(id)
	if changed:
		_save_blueprints()


func _save_blueprints() -> void:
	var cfg := ConfigFile.new()
	for id in unlocked_blueprints.keys():
		cfg.set_value("unlocked", id, true)
	Utils.write_save_version(cfg)
	if cfg.save(BLUEPRINTS_SAVE_PATH) != OK:
		push_warning("GameManager: 蓝图存档写入失败 %s" % BLUEPRINTS_SAVE_PATH)


## 取某蓝图定义（未加载/不存在返回 null）。
func get_blueprint(id: String) -> BlueprintData:
	return _blueprint_registry.get(id, null)


## 返回全部蓝图（按 unlock_inspiration 升序；供工坊列表）。
func get_all_blueprints() -> Array:
	var arr: Array = _blueprint_registry.values()
	arr.sort_custom(func(a, b): return a.unlock_inspiration < b.unlock_inspiration)
	return arr


func is_blueprint_unlocked(id: String) -> bool:
	return unlocked_blueprints.has(id)


# ─── 农场槽（种植玩法，阶段 0.9）门面委托：逻辑已迁出至 FarmManager（见 farm_manager.gd） ───
## 以下方法仅为对外兼容 API，全部委托 FarmManager；农场槽真相源在子管理器。
func place_pot(slot: int, pot_id: String) -> bool:
	return farm_mgr.place_pot(slot, pot_id) if farm_mgr != null else false

func plant(slot: int, seed_id: String) -> bool:
	return farm_mgr.plant(slot, seed_id) if farm_mgr != null else false

func compute_stage(slot: int) -> int:
	return farm_mgr.compute_stage(slot) if farm_mgr != null else -1

func is_slot_mature(slot: int) -> bool:
	return farm_mgr.is_slot_mature(slot) if farm_mgr != null else false

func get_growth_info(slot: int) -> Dictionary:
	return farm_mgr.get_growth_info(slot) if farm_mgr != null else {}

func harvest(slot: int) -> bool:
	return farm_mgr.harvest(slot) if farm_mgr != null else false

func clear_slot(slot: int) -> bool:
	return farm_mgr.clear_slot(slot) if farm_mgr != null else false


## 取第 i 槽状态（门面转发 FarmManager，越界返回空 Dictionary；供种植屏安全读）。
func get_slot(i: int) -> Dictionary:
	return farm_mgr.get_slot(i) if farm_mgr != null else {}


# ═══════════════════ 服装展架（阶段 4：家园增强） ═══════════════════
## 以下方法为 RackManager 的委托转发；内部状态与存档见 rack_manager.gd。

## 上架：把某槽设为某 item_id（同槽自动替换）。不校验库存——上架只是「展示意愿」。
func display_clothing(slot: int, item_id: String) -> void:
	if rack_mgr != null:
		rack_mgr.display_clothing(slot, item_id)

## 下架：清空某槽。
func undisplay(slot: int) -> void:
	if rack_mgr != null:
		rack_mgr.undisplay(slot)

## 取某槽当前在售 item_id（空槽返回 ""）
func get_rack_item(slot: int) -> String:
	return rack_mgr.get_rack_item(slot) if rack_mgr != null else ""


## 展架槽总数（门面转发 RackManager，供展架面板遍历）。
func get_rack_count() -> int:
	return rack_mgr.get_rack_count() if rack_mgr != null else 0

## 展架某服装当前可售库存 = 在售库存计数（inventory）。
func get_rack_stock(item_id: String) -> int:
	return rack_mgr.get_rack_stock(item_id) if rack_mgr != null else 0

## 返回所有「有货」展架槽位下标（get_rack_stock > 0），供顾客随机选购
func get_rack_slots_with_stock() -> Array:
	return rack_mgr.get_rack_slots_with_stock() if rack_mgr != null else []

## 顾客从某槽购买 1 件：加金币(售价) + 扣库存。返回实际获得金币（槽空/无货返回 -1）。
func sell_from_rack(slot: int) -> int:
	return rack_mgr.sell_from_rack(slot) if rack_mgr != null else -1

## 返回可上架服装 [{id, data, available}]。
func get_displayable_clothing() -> Array:
	return rack_mgr.get_displayable_clothing() if rack_mgr != null else []

# ─── 订单存档（user://，持久化结算所需最小信息） ───

func _save_orders() -> void:
	var payload := {"save_version": Utils.SAVE_VERSION, "orders": _orders, "arrived": _arrived}
	var f := FileAccess.open(ORDER_SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(payload))
		f.close()
	else:
		push_warning("GameManager: 订单存档写入失败 %s" % ORDER_SAVE_PATH)


func _load_orders() -> void:
	if not FileAccess.file_exists(ORDER_SAVE_PATH):
		return
	var f := FileAccess.open(ORDER_SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if parsed == null or not parsed is Dictionary:
		_delete_orders_save()
		return
	# 旧档迁移入口：v0（无 save_version 键）格式与 v1 一致，暂无需转换（见 Utils.SAVE_VERSION）
	if int(parsed.get("save_version", 0)) < Utils.SAVE_VERSION:
		pass
	var orders_arr: Array = parsed.get("orders", [])
	var arrived_arr: Array = parsed.get("arrived", [])
	var now := Time.get_unix_time_from_system()
	for o in orders_arr:
		if not o is Dictionary:
			continue
		var elapsed := now - int(o.get("start_unix", 0))
		if elapsed >= float(o.get("duration_sec", 0)):
			# 离线期间已到货 → 进待收（待用户确认收货入库）
			_arrived.append({"id": o.get("id", ""), "name": o.get("name", "")})
		else:
			# 仍在进行 → 后台继续
			_orders.append(o)
	for a in arrived_arr:
		if a is Dictionary:
			_arrived.append({"id": a.get("id", ""), "name": a.get("name", "")})
	# 规整存档：已到的从进行中移走
	_save_orders()


func _delete_orders_save() -> void:
	var dir := DirAccess.open("user://")
	if dir != null:
		dir.remove("phone_orders.json")
