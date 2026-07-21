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

# ─── 电话购物 / 仓库 信号 ───
signal orders_changed            ## 进行中订单列表变化（下单 / 到货移出）
signal order_arrived(id: String, name: String)  ## 某订单配送完成（进入待收）
signal arrived_changed          ## 待收列表变化（影响电话「已到货」提示）
signal warehouse_changed        ## 库存变化（入库，向后兼容；新代码建议用 inventory_changed）
signal inventory_changed         ## 统一库存变化（仓库角标 / 网格监听）

# ─── 统一库存（inventory，跨场景唯一真相源） ───
const INVENTORY_SAVE_PATH := "user://inventory.cfg"
var inventory: Dictionary = {}       # id -> count(int)
var _item_registry: Dictionary = {}  # id -> ItemData（运行时注册，非存档；按 id 解析元数据）

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

# ─── 灵感活动计时（墙钟 + 存档，支持离线收益） ───
const ACTIVITY_SAVE_PATH := "user://inspiration_active.json"

var _activity_running: bool = false
var _activity_name: String = ""
var _activity_per_minute: float = 0.0
var _activity_start_unix: int = 0
var _activity_duration_sec: float = 0.0

# ─── 电话订单（墙钟 + 存档，支持离线到货） ───
const ORDER_SAVE_PATH := "user://phone_orders.json"
const WAREHOUSE_PATH := "user://warehouse.cfg"

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
	gold = initial_gold
	inspiration = initial_inspiration
	_load_activity()    # 灵感：已过期补发 / 未过期后台继续
	_load_orders()      # 订单：离线期间到货的进待收，未到的后台继续
	_load_inventory()   # 库存：还原统一 inventory（含旧仓库迁移）


func _process(_delta: float) -> void:
	if _activity_running:
		var elapsed := Time.get_unix_time_from_system() - _activity_start_unix
		if elapsed >= _activity_duration_sec:
			_finish_activity()
	_tick_orders()


# ═══════════════════ 货币 ═══════════════════

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
	var reward_gold: int = base_reward.get("gold", 0)
	var reward_insp: int = base_reward.get("inspiration", 0)
	add_gold(reward_gold)
	add_inspiration(reward_insp)


# ═══════════════════ 灵感活动计时 ═══════════════════

## 开始一个活动（墙钟计时，立即存档）。minutes 为设定时长（分钟）。
func start_activity(data: ActivityData, minutes: int) -> void:
	if minutes < 1:
		minutes = 1
	_activity_running = true
	_activity_name = data.activity_name
	_activity_per_minute = data.inspiration_per_minute
	_activity_start_unix = int(Time.get_unix_time_from_system())
	_activity_duration_sec = float(minutes) * 60.0
	_save_activity()
	activity_started.emit()


## 放弃当前进行中的活动（清状态 + 删存档，不发奖）
func cancel_activity() -> void:
	if not _activity_running:
		return
	_activity_running = false
	_delete_activity_save()
	activity_cancelled.emit()


func is_activity_running() -> bool:
	return _activity_running


func get_active_activity_name() -> String:
	return _activity_name


func get_remaining_sec() -> float:
	if not _activity_running:
		return 0.0
	var elapsed := Time.get_unix_time_from_system() - _activity_start_unix
	return maxf(0.0, _activity_duration_sec - elapsed)


func get_pending_reward() -> int:
	if not _activity_running:
		return 0
	var minutes := int(ceil(_activity_duration_sec / 60.0))
	return _compute_activity_reward(_activity_per_minute, minutes)


func _finish_activity() -> void:
	var minutes := int(ceil(_activity_duration_sec / 60.0))
	var reward := _compute_activity_reward(_activity_per_minute, minutes)
	_activity_running = false
	_delete_activity_save()
	add_inspiration(reward)
	activity_finished.emit({"inspiration": reward, "activity_name": _activity_name})


func _compute_activity_reward(per_minute: float, minutes: int) -> int:
	if minutes < 1:
		minutes = 1
	var raw := float(minutes) * per_minute
	return int(ceil(raw - 0.0001))


func _save_activity() -> void:
	var payload := {
		"name": _activity_name,
		"per_minute": _activity_per_minute,
		"start_unix": _activity_start_unix,
		"duration_sec": _activity_duration_sec
	}
	var f := FileAccess.open(ACTIVITY_SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(payload))
		f.close()


func _load_activity() -> void:
	if not FileAccess.file_exists(ACTIVITY_SAVE_PATH):
		return
	var f := FileAccess.open(ACTIVITY_SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if parsed == null or not parsed is Dictionary:
		_delete_activity_save()
		return
	_activity_name = parsed.get("name", "")
	_activity_per_minute = float(parsed.get("per_minute", 0.0))
	_activity_start_unix = int(parsed.get("start_unix", 0))
	_activity_duration_sec = float(parsed.get("duration_sec", 0.0))
	var elapsed := Time.get_unix_time_from_system() - _activity_start_unix
	if elapsed >= _activity_duration_sec:
		_finish_activity()
	else:
		_activity_running = true


func _delete_activity_save() -> void:
	var dir := DirAccess.open("user://")
	if dir != null:
		dir.remove("inspiration_active.json")


# ═══════════════════ 电话订单（多订单并行 + 墙钟 + 存档） ═══════════════════

## 下单：校验金币 → 扣款 → 记录进行中订单（墙钟时间戳）→ 立即存档。返回是否成功。
func start_order(product: ProductData) -> bool:
	if product == null:
		return false
	if gold < product.price:
		return false
	subtract_gold(product.price)
	var order := {
		"id": product.id,
		"name": product.display_name,
		"start_unix": int(Time.get_unix_time_from_system()),
		"duration_sec": float(product.delivery_minutes) * 60.0
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


## 确认收货：把全部待收货物解锁进仓库、清空待收、存档。
func confirm_receipt() -> void:
	if _arrived.is_empty():
		return
	for a in _arrived:
		_unlock_internal(a["id"])
	_arrived.clear()
	_save_orders()
	arrived_changed.emit()
	warehouse_changed.emit()


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
func register_item(data: ItemData) -> void:
	if data != null and not data.id.is_empty():
		_item_registry[data.id] = data


func get_item(id: String) -> ItemData:
	return _item_registry.get(id, null)


func add_item(id: String, n: int = 1) -> void:
	if id.is_empty() or n <= 0:
		return
	inventory[id] = inventory.get(id, 0) + n
	_save_inventory()
	inventory_changed.emit()


func remove_item(id: String, n: int = 1) -> void:
	if id.is_empty() or not inventory.has(id):
		return
	inventory[id] -= n
	if inventory[id] <= 0:
		inventory.erase(id)
	_save_inventory()
	inventory_changed.emit()


func has_item(id: String) -> bool:
	return inventory.has(id) and inventory[id] > 0


func get_count(id: String) -> int:
	return inventory.get(id, 0)


## 按分类返回 [{data, count}]（data 经注册表解析；未注册的物品跳过）
func get_by_category(cat: int) -> Array:
	var out: Array = []
	for id in inventory.keys():
		var d: ItemData = get_item(id)
		if d != null and d.category == cat:
			out.append({"data": d, "count": inventory[id]})
	return out


func get_total_count() -> int:
	var t := 0
	for id in inventory.keys():
		t += inventory[id]
	return t


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


func _save_inventory() -> void:
	var cfg := ConfigFile.new()
	for id in inventory.keys():
		cfg.set_value("items", id, inventory[id])
	cfg.save(INVENTORY_SAVE_PATH)


func _load_inventory() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(INVENTORY_SAVE_PATH) == OK:
		for id in cfg.get_section_keys("items"):
			var cnt: int = int(cfg.get_value("items", id, 0))
			if cnt > 0:
				inventory[str(id)] = cnt
	if inventory.is_empty():
		_migrate_warehouse_to_inventory()


## 一次性迁移：旧 warehouse.cfg（id 集合）搬到统一 inventory（count=1）
func _migrate_warehouse_to_inventory() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(WAREHOUSE_PATH) != OK:
		return
	for id in cfg.get_section_keys("owned"):
		var sid := str(id)
		if not inventory.has(sid):
			inventory[sid] = 1
	_save_inventory()


# ─── 订单存档（user://，持久化结算所需最小信息） ───

func _save_orders() -> void:
	var payload := {"orders": _orders, "arrived": _arrived}
	var f := FileAccess.open(ORDER_SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(payload))
		f.close()


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
