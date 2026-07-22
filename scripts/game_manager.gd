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

# ─── 统一库存（inventory，跨场景唯一真相源） ───
const INVENTORY_SAVE_PATH := "user://inventory.cfg"
var inventory: Dictionary = {}       # id -> count(int)
var _item_registry: Dictionary = {}  # id -> ItemData（运行时注册，非存档；按 id 解析元数据）
var _clothing_seeded: bool = false   # 首次运行是否已播种初始衣橱（防止售出后又被刷回来）
var _farm_seeded: bool = false        # 首次运行是否已播种起始种子+花盆（阶段 2.3）
var _workshop_seeded: bool = false     # 首次运行是否已发放初始工坊材料（阶段 2.4）

# ─── 穿搭（equipped，与所有权分离；换装屏当前穿在身上的衣服） ───
## equipped: slot(int) -> item_id(String)。所有权在 inventory[CLOTHING]，穿搭独立于此。
## 展架库存 = 拥有总数 - 穿戴数（穿在身上的不计入可售）。
const EQUIPPED_SAVE_PATH := "user://equipped.cfg"
const OLD_WARDROBE_PATH := "user://wardrobe.cfg"   # 旧衣橱穿搭存档（slot -> resource_path），一次性迁移用
var equipped: Dictionary = {}        # slot(int) -> item_id(String)

# ─── 灵感累计 & 蓝图解锁（阶段 0.8） ───
const INSPIRATION_TOTAL_SAVE_PATH := "user://inspiration_total.cfg"
const BLUEPRINTS_SAVE_PATH := "user://blueprints.cfg"
const BLUEPRINTS_DIR := "res://data/blueprints/"
var inspiration_total_earned: int = 0     # 累计获得灵感（单调递增，蓝图阈值用）
var _blueprint_registry: Dictionary = {}  # id -> BlueprintData（启动时加载，非存档）
var unlocked_blueprints: Dictionary = {}  # id -> true（已解锁；含存档恢复 + 阈值达成）

# ─── 农场槽（种植玩法，阶段 0.9） ───
## 每槽状态机：空 → 有盆(place_pot) → 已种(plant) → 成熟(harvest)
## 槽结构 Dictionary：{pot_id, seed_id, planted_unix, done}
##   pot_id：     摆放物(花盆) id，空=无盆
##   seed_id：     已种种子 id，空=未种
##   planted_unix：种下时的墙钟时间戳（秒）；未种=0
##   done：        预留标志（当前恒为 false，成熟判断以 compute_stage 实时算为准）
## 墙钟计时：关游戏再开按真实流逝时间续算（挂机友好），无需常驻进程。
const FARM_SLOTS := 6                  # 种植屏功能槽数量（阶段 2.3 暂定 6，商店扩容后续再定）
const FARM_SAVE_PATH := "user://farm.cfg"
var farm_slots: Array = []             # 长度 FARM_SLOTS 的槽数组（元素为上述 Dictionary）

# ─── 服装展架（阶段 4：家园增强） ───
## clothing_rack: 长度 RACK_SLOTS 的数组，元素为 item_id(String) 或 ""（空槽）。
## 仅作「在售列表」，不消耗库存；售出时扣 inventory，槽按库存自动补充/清空。
const RACK_SLOTS := 6                  # 展架槽数量（阶段 4 暂定 6，与计划一致）
const RACK_SAVE_PATH := "user://rack.cfg"
var clothing_rack: Array = []          # 长度 RACK_SLOTS 的槽数组（元素为 item_id 或 ""）

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
var _activity_interrupts: int = 0   ## 本次番茄钟的打断次数（进程内，不持久化；离线补发不记打断）

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
	_load_equipped()    # 穿搭：还原 equipped（含旧 wardrobe.cfg 一次性迁移）
	_load_inspiration_total()  # 灵感累计：还原单调计数器
	_load_blueprints()          # 蓝图：加载定义 + 恢复解锁 + 初始解锁 pass
	_load_farm()                # 农场：还原槽状态（墙钟，离线照常续算）
	_load_rack()                # 服装展架：还原上架状态（阶段 4）


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
		# 负值（花费）不计入累计获得：inspiration_total_earned 只增不减
		inspiration += amount
		return
	inspiration += amount
	inspiration_total_earned += amount
	_save_inspiration_total()
	_evaluate_blueprint_unlocks(true)


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
	_activity_interrupts = 0   ## 新会话开始，打断计数归零
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
	_activity_interrupts = 0
	_delete_activity_save()
	activity_cancelled.emit()


func is_activity_running() -> bool:
	return _activity_running


## 记录一次打断（番茄钟进行中做了非灵感活动的分心行为）。仅在进行中累加，emit 供 UI 提示。
func register_interrupt() -> void:
	if not _activity_running:
		return
	_activity_interrupts += 1
	activity_interrupted.emit(_activity_interrupts)


func get_activity_interrupts() -> int:
	return _activity_interrupts


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
	var base := _compute_activity_reward(_activity_per_minute, minutes)
	## 打断衰减：每次打断 -20%，保底 50%（即最少拿一半灵感）
	var factor := maxf(0.5, 1.0 - float(_activity_interrupts) * 0.2)
	var reward := int(ceil(float(base) * factor - 0.0001))
	_activity_running = false
	_delete_activity_save()
	add_inspiration(reward)
	activity_finished.emit({"inspiration": reward, "activity_name": _activity_name, "base": base, "interrupts": _activity_interrupts})
	_activity_interrupts = 0


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
## 返回是否成功（物品已注册 + 有配方 + 持有≥1 才执行）。add/remove 各自会发 inventory_changed。
func decompose(item_id: String) -> bool:
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
## 成功时 add_item/remove_item 各自发 inventory_changed（工坊 UI 即时刷新）。
func craft(blueprint_id: String) -> bool:
	var bp: BlueprintData = get_blueprint(blueprint_id)
	if bp == null:
		return false
	if not unlocked_blueprints.has(blueprint_id):
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


func _save_inventory() -> void:
	var cfg := ConfigFile.new()
	for id in inventory.keys():
		cfg.set_value("items", id, inventory[id])
	cfg.set_value("meta", "clothing_seeded", _clothing_seeded)
	cfg.set_value("meta", "farm_seeded", _farm_seeded)
	cfg.set_value("meta", "workshop_seeded", _workshop_seeded)
	cfg.save(INVENTORY_SAVE_PATH)


func _load_inventory() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(INVENTORY_SAVE_PATH) == OK:
		for id in cfg.get_section_keys("items"):
			var cnt: int = int(cfg.get_value("items", id, 0))
			if cnt > 0:
				inventory[str(id)] = cnt
	_clothing_seeded = bool(cfg.get_value("meta", "clothing_seeded", false))
	_farm_seeded = bool(cfg.get_value("meta", "farm_seeded", false))
	_workshop_seeded = bool(cfg.get_value("meta", "workshop_seeded", false))
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


## 一次性播种：首次运行把设计池中的服装各发 1 件作为初始衣橱。
## 带 _clothing_seeded flag 持久化，避免玩家售出/分解服装后下次启动又被刷回来。
## main._ready 在注册服装池后调用一次即可。
func seed_starter_clothing(pool: Array) -> void:
	if _clothing_seeded:
		return
	for c in pool:
		if c != null and not c.id.is_empty() and not inventory.has(c.id):
			inventory[c.id] = 1
	_clothing_seeded = true
	_save_inventory()
	inventory_changed.emit()


## 一次性播种：首次运行给起始种子（每款各 2 粒）+ 花盆若干，让种植屏开箱即用。
## 带 _farm_seeded flag 持久化，避免玩家用掉后又被刷回来。
## seed_ids 来自 main 的种子池；pot_id 为花盆物品 id（与 product_pot.tres 对齐）。
func seed_starter_farm(seed_ids: Array, pot_id: String, pot_count: int) -> void:
	if _farm_seeded:
		return
	for sid in seed_ids:
		if not sid.is_empty() and not inventory.has(sid):
			inventory[sid] = 2
	if not pot_id.is_empty() and not inventory.has(pot_id):
		inventory[pot_id] = pot_count
	_farm_seeded = true
	_save_inventory()
	inventory_changed.emit()


## 一次性发放工坊起始材料（红染料、纤维、可分解作物）。
## 改为自愈逻辑：不依赖 flag，每次启动检查库存是否达到目标数量，不足就补。
## 这样即使存档状态不一致（之前运行过有 bug 的版本）也能自愈。
func seed_starter_workshop(materials: Dictionary) -> void:
	var changed := false
	for iid in materials:
		var target: int = int(materials[iid])
		if iid.is_empty() or target <= 0:
			continue
		var have: int = int(inventory.get(iid, 0))
		if have < target:
			inventory[iid] = target    # 补到目标数量（不覆盖已有的更多）
			changed = true
	if changed:
		_save_inventory()
		inventory_changed.emit()


# ═══════════════════ 穿搭（equipped，slot -> item_id；与所有权分离） ═══════════════════

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
	var cfg := ConfigFile.new()
	for slot in equipped.keys():
		cfg.set_value("equipped", str(slot), equipped[slot])
	cfg.save(EQUIPPED_SAVE_PATH)


func _load_equipped() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(EQUIPPED_SAVE_PATH) == OK:
		for slot_str in cfg.get_section_keys("equipped"):
			var vid: String = str(cfg.get_value("equipped", slot_str, ""))
			if not vid.is_empty():
				equipped[int(slot_str)] = vid
		return
	# 无新存档 → 尝试从旧 wardrobe.cfg（slot -> resource_path）一次性迁移，保住当前穿搭
	_migrate_old_wardrobe()


## 一次性迁移：旧 wardrobe.cfg 存的是 slot -> ClothesData 资源路径；
## 载入资源取其 id，转成新格式 equipped[slot] = item_id 并存档。
func _migrate_old_wardrobe() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(OLD_WARDROBE_PATH) != OK:
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

# ═══════════════════ 灵感累计 & 蓝图解锁（阶段 0.8） ═══════════════════
## inspiration_total_earned：累计"获得"的灵感（单调递增），作蓝图解锁阈值；
## 与可花费的 inspiration 分离——花掉灵感不会让已解锁蓝图回锁。任何正向灵感来源
## （灵感活动结算 / 订单奖励等）都累加，负值（花费）不计（见 add_inspiration）。

func _save_inspiration_total() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("inspiration", "total_earned", inspiration_total_earned)
	cfg.save(INSPIRATION_TOTAL_SAVE_PATH)


func _load_inspiration_total() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(INSPIRATION_TOTAL_SAVE_PATH) == OK:
		inspiration_total_earned = int(cfg.get_value("inspiration", "total_earned", 0))


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
	# 恢复已解锁存档（阈值日后提高也不会回锁）
	var cfg := ConfigFile.new()
	if cfg.load(BLUEPRINTS_SAVE_PATH) == OK:
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
	cfg.save(BLUEPRINTS_SAVE_PATH)


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


# ═══════════════════ 农场槽（种植玩法，阶段 0.9） ═══════════════════
## 纯数据层 + 墙钟计时。UI（种植屏 2.3）只调这些方法，不碰内部字段。
## 状态机：空 → place_pot → plant → (compute_stage 进入成熟) → harvest / clear_slot。

func _make_empty_slot() -> Dictionary:
	return {"pot_id": "", "seed_id": "", "planted_unix": 0, "done": false}


## 在指定槽放入一个花盆（从 inventory 取 1 个可摆放的盆，pot_id 指向 is_placeable 物品）。仅空槽（无盆）可放。返回是否成功。
func place_pot(slot: int, pot_id: String) -> bool:
	if slot < 0 or slot >= farm_slots.size():
		return false
	var s: Dictionary = farm_slots[slot]
	if not s.get("pot_id", "").is_empty():
		return false                       # 槽里已有盆
	if not has_item(pot_id):
		return false                       # 库存没有该花盆
	remove_item(pot_id, 1)                # 花盆进入槽内（离开库存）
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
	var sd: SeedData = get_item(seed_id)
	if sd == null or not (sd is SeedData):
		return false                       # 未注册或不是种子
	if not has_item(seed_id):
		return false                       # 库存没有该种子
	remove_item(seed_id, 1)
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
	var sd: SeedData = get_item(seed_id)
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
	var sd: SeedData = get_item(seed_id)
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
	var sd: SeedData = get_item(s.get("seed_id", ""))
	if sd == null or not (sd is SeedData) or sd.crop_output == null:
		return false
	add_item(sd.crop_output.id, 1)     # 作物按 category=CROP 进库存（inventory 仍用 id key；关系本身已是直接引用）
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
	add_item(s.get("pot_id", ""), 1)     # 花盆退回库存
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


# ═══════════════════ 服装展架（阶段 4：家园增强） ═══════════════════
## 展架 = 在售列表（不消耗库存）。售出时扣 inventory，槽按库存自动补充/清空。

## 上架：把某槽设为某 item_id（同槽自动替换）。不校验库存——上架只是「展示意愿」，
## 真正可售数量由 get_rack_stock（拥有 − 穿戴）实时算；售出扣的是 inventory。
func display_clothing(slot: int, item_id: String) -> void:
	if slot < 0 or slot >= RACK_SLOTS:
		return
	if item_id.is_empty():
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


## 展架某服装当前可售库存 = 拥有总数 − 穿戴数（穿在身上的不计入可售）
func get_rack_stock(item_id: String) -> int:
	if item_id.is_empty():
		return 0
	return get_count(item_id) - get_worn_count(item_id)


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
	var data: ItemData = get_item(id)
	var price: int = data.price if data != null else 0
	add_gold(price)
	remove_item(id, 1)
	if get_rack_stock(id) <= 0:
		clothing_rack[slot] = ""   # 售罄清空
	_save_rack()
	rack_changed.emit()
	return price


## 返回可上架服装 [{id, data, available}]，available = 拥有 − 穿戴 > 0
func get_displayable_clothing() -> Array:
	# 上架约束（需求）：展架仅接受衣物（CLOTHING）。种子/作物/材料/摆放物
	# 不属于衣物，get_by_category(CLOTHING) 按 category 过滤（且默认跳过 is_placeable）
	# 后本就不会进入此列表，故展架天然只显示衣物，无法上架其他类别。
	var out: Array = []
	for entry in get_by_category(ItemData.Category.CLOTHING):
		var id: String = entry["data"].id
		var avail := get_count(id) - get_worn_count(id)
		if avail > 0:
			out.append({"id": id, "data": entry["data"], "available": avail})
	return out


func _save_rack() -> void:
	var cfg := ConfigFile.new()
	for i in range(clothing_rack.size()):
		cfg.set_value("rack", "slot_%d" % i, clothing_rack[i])
	cfg.save(RACK_SAVE_PATH)


func _load_rack() -> void:
	clothing_rack = []
	var cfg := ConfigFile.new()
	if cfg.load(RACK_SAVE_PATH) == OK:
		for i in range(RACK_SLOTS):
			clothing_rack.append(str(cfg.get_value("rack", "slot_%d" % i, "")))
	while clothing_rack.size() < RACK_SLOTS:
		clothing_rack.append("")
	clothing_rack = clothing_rack.slice(0, RACK_SLOTS)


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
