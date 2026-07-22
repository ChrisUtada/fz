extends Control
## Main · 主场景（编排层 / Orchestrator）
## 职责：组装子组件（HUD + PlayArea），编排顾客生成与订单完成的生命周期，
##       以及电话购物 / 仓库 / 灵感等副玩法入口。
## 原则：
##   - 高内聚：只做“编排”，不持有业务逻辑（货币/换装/动画等在各自节点）
##   - 低耦合：通过信号连接组件，不直接操作内部状态
##   - 组合：本节点 = 窗口管理（阶段0） + 游戏循环（阶段1） + 副玩法入口（阶段3）
##
## 输入处理说明：
##   鼠标交互的“判定与响应”归顾客/宠物自身（contains_point + _input 三态）。
##   主场景 _input 只负责：①点中关闭按钮交按钮处理 ②点中顾客/宠物则 return（节点已消费，不拖窗口）
##   ③点中电话摆件则 return（电话自身处理点击）④点中空白则拖拽窗口。
##   用 _customer_at_point / _pet_at_point / _phone_at_point（遍历子节点调 contains_point）守卫。

# ─── 阶段 0：窗口管理 ───
var _dragging := false
var _drag_offset := Vector2i.ZERO
## 窗口可拖拽区域：仅窗口顶部这条带（像素，相对窗口左上角）。
## 目的：把"移动窗口"的手势从页面内部区域隔离出来，避免与换装拖拽衣物、
## 列表滚动等内部手势冲突。想移动窗口就抓窗口顶边。
const TOP_DRAG_BAND := 30.0

# ─── 阶段 1：顾客生成配置 ───
@export var first_spawn_delay: float = 1.5          ## 首个顾客出现延迟
@export var min_spawn_interval: float = 2.0         ## 生成间隔下限
@export var max_spawn_interval: float = 4.0         ## 生成间隔上限

# ─── 阶段 2：数据驱动（Resource） ───
@export var customer_pool: Array[CustomerData] = []   ## 顾客数据资源池（.tres），拖入即用

# ─── 阶段 1 补：宠物生成配置 ───
@export var first_pet_delay: float = 3.0          ## 首只宠物出现延迟
@export var min_pet_interval: float = 5.0         ## 宠物生成间隔下限
@export var max_pet_interval: float = 10.0        ## 宠物生成间隔上限
@export var max_pets: int = 1                     ## 同时存在的宠物数量上限

# ─── 阶段 2：宠物数据（Resource） ───
@export var pet_pool: Array[PetData] = []           ## 宠物数据资源池（.tres），拖入即用

# ─── 阶段 2：衣服数据（Resource，换装场景消费） ───
@export var clothes_pool: Array[ClothesData] = []   ## 衣服数据资源池（.tres），拖入即用

# ─── 阶段 3：灵感活动数据（Resource，灵感弹窗消费） ───
@export var activity_pool: Array[ActivityData] = []   ## 灵感活动资源池（.tres），拖入即用

# ─── 阶段 3 补：产品数据（Resource，电话购物 / 仓库消费） ───
@export var product_pool: Array[ProductData] = []     ## 产品资源池（.tres），拖入即用
@export var seed_pool: Array[SeedData] = []           ## 种子资源池（.tres），拖入即用（阶段 2.3 商城售卖）

# ─── 阶段 2 补：作物/材料/制作产物（Resource，工坊与仓库解析用） ───
@export var crop_pool: Array[ItemData] = []           ## 作物资源池（.tres）；导出构建中 DirAccess 扫描可能失败，静态池兜底
@export var material_pool: Array[ItemData] = []       ## 材料资源池（.tres）
@export var craft_pool: Array[ItemData] = []          ## 制作产出物（.tres），只注册元数据、不进 starter clothing

# ─── 阶段 2.4：蓝图资源池（Resource，工坊显示用） ───
@export var blueprint_pool: Array[BlueprintData] = []  ## 蓝图资源池（.tres）；导出构建中 DirAccess 扫描可能失败，静态池兜底

# 节点引用 —— 通过 @onready 注入，不硬编码路径搜索
@onready var play_area: Node2D = $Panel/PlayArea
@onready var pet_area: Node2D = $Panel/PetArea
@onready var close_button: Button = $CloseButton
@onready var inspiration_btn: Button = $Panel/InspirationButton   ## 家园灵感悬浮入口（取代原右侧菜单）
@onready var placement_manager: PlacementManager = $PlacementManager
# ─── 阶段 1：四界面切换框架（步骤 1.3 接线） ───
@onready var screen_manager: ScreenManager = $ScreenManager   ## 屏幕互斥显隐管理器
@onready var screens_root: Control = $Screens                 ## 四个可切换屏的容器（覆盖层）
@onready var tab_bar: SignboardTabBar = $TabBar               ## 底部招牌导航栏
var _arrow_nav: ArrowNav = null                              ## 步骤 1.5：活动面板左右箭头（覆盖层，绘制在屏之上）
var _focus_bar: FocusBar = null                               ## 番茄钟常驻专注条（右下角，绘制序最高）

# 电话摆件引用（运行期实例化，见 _instance_phone）
var _phone: Control = null

# 服装展架摆件引用（运行期实例化，见 _instance_rack）
var _rack: Control = null


func _ready() -> void:
	_configure_window()
	_schedule_first_spawn()
	_schedule_first_pet()
	inspiration_btn.pressed.connect(_open_inspiration)   ## 换装/仓库已并入切屏，仅灵感保留家园悬浮入口
	_ensure_product_pool()
	for p in product_pool:
		GameManager.register_item(p)
	# 阶段 0.4：注册服装到统一库存注册表，并一次性播种初始衣橱（每款各 1 件）
	_ensure_clothes_pool()
	for c in clothes_pool:
		# 服装图标统一落到基类 icon（背包/仓库/展架通用），避免 icon_texture 与 icon 分裂
		if c != null and c.icon == null and c.icon_texture != null:
			c.icon = c.icon_texture
		GameManager.register_item(c)
	GameManager.seed_starter_clothing(clothes_pool)
	# 阶段 2.3：注册种子/作物到注册表（农场逻辑据此解析 SeedData），并一次性播种起始种子+花盆
	_ensure_seed_pool()
	for s in seed_pool:
		GameManager.register_item(s)
	# 阶段 2 补：静态注册作物/材料/制作产物（导出构建中 DirAccess 扫描不可靠，必须显式拖入/回退加载）
	_ensure_crop_pool()
	for c in crop_pool:
		if c != null:
			GameManager.register_item(c)
	_ensure_material_pool()
	for m in material_pool:
		if m != null:
			GameManager.register_item(m)
	_ensure_craft_pool()
	for c in craft_pool:
		if c != null:
			GameManager.register_item(c)
	# 阶段 2.4：静态注册蓝图（导出构建中 DirAccess 扫描不可靠，必须显式拖入/回退加载）
	_ensure_blueprint_pool()
	for bp in blueprint_pool:
		if bp != null:
			GameManager.register_blueprint(bp)
	_register_item_resources()
	# 注册表就绪后：旧存档/首启自愈已解锁服装集合（首次运行由 seed_starter_clothing 写入，此处兜底旧版存档）
	GameManager._ensure_unlocked_clothes()
	# 起始花盆 id：从产品池按 garden_placement 标志自动识别（不再写死 "pot"），找不到时兜底历史 id
	var pot_id_for_seed: String = ""
	for p in product_pool:
		if p != null and p.garden_placement:
			pot_id_for_seed = p.id
			break
	if pot_id_for_seed.is_empty():
		pot_id_for_seed = "pot"
	GameManager.seed_starter_farm(_seed_ids(), pot_id_for_seed, 2)
	# 阶段 2.4：发放工坊起始材料（红染料、纤维、可分解作物），走通 分解→材料→制作
	GameManager.seed_starter_workshop({
		"red_dye": 3,
		"fiber": 5,
		"rose": 2,
	})
	# 阶段 2.4：补足起始灵感至 20（让围巾蓝图可解锁，便于测试制作）；已达标则不补
	if GameManager.inspiration_total_earned < 20:
		GameManager.add_inspiration(20 - GameManager.inspiration_total_earned)
	_instance_phone()
	_instance_rack()
	placement_manager.init(product_pool, $Panel/PlacedItems)
	_setup_screens()
	_setup_focus_bar()


## 每帧把「是否有覆盖层弹窗打开」同步给 GameManager，供顾客/宠物/电话/摆放物
## 在 _input 阶段自我屏蔽（弹窗开着时不抢占点击，避免吃掉弹窗按钮的点击）。
func _process(_delta: float) -> void:
	GameManager.set_modal_open(
		_has_catalog() or _has_phone_panel()
		or _has_inspiration()
		or _has_warehouse()
		or _has_rack_panel()
		or _has_active_screen()
	)


# ═══════════════════ 阶段 0：窗口管理 ═══════════════════

func _configure_window() -> void:
	var win := get_window()
	win.mode = Window.MODE_WINDOWED
	win.borderless = true
	win.transparent = true
	win.always_on_top = false
	# 锁定到当前屏幕右下角（桌面常驻挂件形态）；usable_rect 已排除任务栏
	_position_to_bottom_right(win)


## 把窗口定位到当前屏幕的右下角（排除任务栏区域，避免被遮挡）
func _position_to_bottom_right(win: Window) -> void:
	var screen_idx := DisplayServer.window_get_current_screen()
	var rect := DisplayServer.screen_get_usable_rect(screen_idx)
	var pos := rect.position + rect.size - win.size
	DisplayServer.window_set_position(pos)


func _input(event: InputEvent) -> void:
	# 用 _input（最早回调，对所有节点调用，不依赖事件是否被 GUI 消费）统一处理指针
	# 空白拖拽窗口；点中顾客/关闭按钮则交给对应节点，不在此处理
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var mp := get_global_mouse_position()
			# 关闭按钮区域：交给按钮自身的 pressed 处理，不拖拽
			if _on_close_button(mp):
				return
			# 灵感悬浮入口：交给按钮 GUI 处理，不拖窗口
			if _on_inspiration_button(mp):
				return
			# 底部招牌区域：交给按钮 GUI 处理切屏（家园态点招牌也不拖窗口）
			if tab_bar != null and tab_bar.contains_button_point(mp):
				return
			# 活动面板左右箭头按钮：交给按钮 GUI 处理切屏，不拖窗口（箭头仅在四对等屏可见）
			if _arrow_nav != null and _arrow_nav.contains_button_point(mp):
				return
			# 仓库全局浮层已打开时：点击交由浮层自身处理，不拖窗口
			if _has_warehouse():
				return
			# 分页屏（工坊/种植/换装）视为常驻主视图：屏下方被遮挡的
			# 宠物/顾客/摆放物/电话/展架不应抢点击，故跳过其命中检测；
			# 屏内空白区仍允许拖拽窗口（与家园态一致）。
			if not _has_active_screen():
				# 点中宠物：宠物自身 _input 已消费（拖动/轻点红心），此处不拖窗口
				if _pet_at_point(mp) != null:
					return
				# 点中顾客：顾客自身 _input 已消费并自行处理（拖动/轻点完成），此处不拖窗口
				if _customer_at_point(mp) != null:
					return
				# 点中已摆放物品：摆放物自身 _input 已消费（拖动），此处不拖窗口
				if _placed_at_point(mp) != null:
					return
				# 点中电话摆件：交给电话自身处理点击，不拖窗口
				if _phone_at_point(mp):
					return
				# 点中服装展架摆件：交给展架自身处理点击/拖动，不拖窗口
				if _rack_at_point(mp):
					return
			# 产品目录已打开时，不响应空白拖拽（覆盖层处理自身交互）
			if _has_catalog():
				return
			# 订单中心已打开时，不响应空白拖拽
			if _has_phone_panel():
				return
			# 灵感面板已打开时，不响应空白拖拽
			if _has_inspiration():
				return
			# 窗口拖动限定在顶部拖拽带：避免与换装/列表等内部拖拽冲突。
			# mp 为全局坐标，减去窗口全局位置即得窗口内局部 y；仅顶边 TOP_DRAG_BAND 内可抓。
			var _win_pos := DisplayServer.window_get_position()
			if mp.y - _win_pos.y > TOP_DRAG_BAND:
				return
			# 空白 → 开始拖拽窗口
			_dragging = true
			_drag_offset = _win_pos - DisplayServer.mouse_get_position()
		else:
			_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		DisplayServer.window_set_position(DisplayServer.mouse_get_position() + _drag_offset)


## 点击位置是否落在关闭按钮的全局矩形内
func _on_close_button(pos: Vector2) -> bool:
	return close_button.get_global_rect().has_point(pos)


## 点击位置是否落在灵感悬浮入口按钮内（仅按钮可见时生效）
func _on_inspiration_button(pos: Vector2) -> bool:
	return inspiration_btn != null and inspiration_btn.visible \
		and inspiration_btn.get_global_rect().has_point(pos)


## 灵感面板是否已打开（作为 Main 子节点覆盖全窗口）
func _has_inspiration() -> bool:
	return has_node("InspirationPanel")


## 产品目录弹窗是否已打开
func _has_catalog() -> bool:
	return has_node("ProductCatalog")


## 订单中心弹窗是否已打开
func _has_phone_panel() -> bool:
	return has_node("PhonePanel")


## 是否有覆盖屏处于激活态（种植/换装/工坊）。家园态（home）不算，不阻断家园拖拽。
func _has_active_screen() -> bool:
	return screen_manager != null and screen_manager.current_screen != "" \
		and screen_manager.current_screen != "home"


## 遍历 PlayArea 子节点，调用各自的 contains_point 进行命中判定
func _customer_at_point(global_pos: Vector2) -> Node2D:
	for c in play_area.get_children():
		if is_instance_valid(c) and c.has_method("contains_point") and c.contains_point(global_pos):
			return c
	return null


## 遍历 PetArea 子节点，调用各自的 contains_point 进行命中判定
func _pet_at_point(global_pos: Vector2) -> Node2D:
	for p in pet_area.get_children():
		if is_instance_valid(p) and p.has_method("contains_point") and p.contains_point(global_pos):
			return p
	return null


## 电话摆件是否被点中（Phone 实现 contains_point）
func _phone_at_point(global_pos: Vector2) -> bool:
	if _phone == null or not _phone.has_method("contains_point"):
		return false
	return _phone.contains_point(global_pos)


func _on_close_pressed() -> void:
	get_tree().quit()


# ═══════════════════ 阶段 1：顾客生成与订单编排 ═════════════════

func _schedule_first_spawn() -> void:
	await get_tree().create_timer(first_spawn_delay).timeout
	_spawn_customer()


func _spawn_customer() -> void:
	var scene := preload("res://scenes/customer.tscn")
	var customer: Node2D = scene.instantiate()

	# 数据驱动：从顾客资源池随机抽一个 CustomerData，交给场景消费控制外观与奖励
	if not customer_pool.is_empty():
		var data: CustomerData = customer_pool.pick_random()
		if customer.has_method("apply_data"):
			customer.apply_data(data)

	# 随机位置偏移，避免每次完全重叠
	customer.position = Vector2(randf_range(-40.0, 40.0), randf_range(-20.0, 20.0))

	# 将顾客注入 PlayArea —— 依赖注入目标容器
	play_area.add_child(customer)

	# 阶段 4.5：把展架世界坐标交给顾客，使其走向展架购买
	if _rack != null and is_instance_valid(_rack):
		var center := _rack.get_global_rect().get_center()
		customer.set_rack_target(center)
		customer.global_position = center + Vector2(randf_range(70.0, 150.0), randf_range(10.0, 70.0))

	# 信号连接：顾客完成 → 编排器处理 → 触发下一个周期
	customer.order_completed.connect(_on_order_completed)


func _on_order_completed(reward: Dictionary) -> void:
	# 委托给 GameManager 处理货币变更（单一职责）
	GameManager.complete_order(reward)

	# 安排下一个顾客
	var interval := randf_range(min_spawn_interval, max_spawn_interval)
	await get_tree().create_timer(interval).timeout
	_spawn_customer()


# ═══════════════════ 阶段 1 补：宠物生成与编排 ═════════════════

func _schedule_first_pet() -> void:
	await get_tree().create_timer(first_pet_delay).timeout
	_spawn_pet()


func _spawn_pet() -> void:
	# 检查是否达到数量上限（包含正在淡出的）
	if pet_area.get_child_count() >= max_pets:
		# 已达上限，跳过本次生成，继续监听
		var interval := randf_range(min_pet_interval, max_pet_interval)
		await get_tree().create_timer(interval).timeout
		_spawn_pet()
		return

	var scene := preload("res://scenes/pet.tscn")
	var pet: Node2D = scene.instantiate()

	# 数据驱动：从宠物资源池随机抽一个 PetData，交给场景消费控制外观与行走参数
	if not pet_pool.is_empty():
		var data: PetData = pet_pool.pick_random()
		if pet.has_method("apply_data"):
			pet.apply_data(data)

	# 宠物从屏幕边缘随机位置进入（由 pet.gd 内部的 _pick_direction 决定方向）
	pet.position = Vector2.ZERO  # 初始位置由 pet 自身调整

	pet_area.add_child(pet)

	# 可选：连接宠物信号（如点击统计、成就等扩展点）
	# pet.pet_tapped.connect(_on_pet_tapped)

	# 安排下一只宠物
	var interval := randf_range(min_pet_interval, max_pet_interval)
	await get_tree().create_timer(interval).timeout
	_spawn_pet()


# ═══════════════════ 阶段 3：灵感面板入口 ═══════════════════

## 实例化灵感面板作为覆盖层，传入活动资源池；完成时通过信号回传 Main 编排
func _open_inspiration() -> void:
	if _has_inspiration():
		return
	# 数据驱动回退：未拖入任何 .tres 时，自动加载内置“阅读”+“外出”活动，开箱即用
	if activity_pool.is_empty():
		var pool: Array[ActivityData] = []
		var reading = load("res://data/activity_reading.tres")
		var outing = load("res://data/activity_outing.tres")
		if reading != null:
			pool.append(reading)
		if outing != null:
			pool.append(outing)
		activity_pool = pool
	var scene := preload("res://scenes/inspiration_panel.tscn")
	var panel: Control = scene.instantiate()
	panel.activity_pool = activity_pool
	add_child(panel)


# ═══════════════════ 阶段 3 补：电话购物 + 仓库 ═══════════════════

## 数据驱动回退：未拖入任何 .tres 时，自动加载内置三个产品（+ 花盆，供种植屏购买）
func _ensure_product_pool() -> void:
	if not product_pool.is_empty():
		return
	for path in ["res://data/product_chair.tres", "res://data/product_desk.tres", "res://data/product_lamp.tres", "res://data/product_pot.tres"]:
		var res = load(path)
		if res != null:
			product_pool.append(res)


## 数据驱动回退：未拖入任何 .tres 时，自动加载内置种子（供商城售卖 + 注册）
func _ensure_seed_pool() -> void:
	if not seed_pool.is_empty():
		return
	for path in ["res://data/seeds/seed_rose.tres"]:
		var res = load(path)
		if res != null:
			seed_pool.append(res)


## 数据驱动回退：未拖入任何 .tres 时，自动加载内置作物（供分解/仓库显示）
func _ensure_crop_pool() -> void:
	if not crop_pool.is_empty():
		return
	var res = load("res://data/crops/crop_rose.tres")
	if res != null:
		crop_pool.append(res)


## 数据驱动回退：未拖入任何 .tres 时，自动加载内置材料（供制作/分解/仓库显示）
func _ensure_material_pool() -> void:
	if not material_pool.is_empty():
		return
	for path in ["res://data/materials/red_dye.tres", "res://data/materials/fiber.tres"]:
		var res = load(path)
		if res != null:
			material_pool.append(res)


## 数据驱动回退：未拖入任何 .tres 时，自动加载内置制作产出物（供制作/仓库显示）
func _ensure_craft_pool() -> void:
	if not craft_pool.is_empty():
		return
	var res = load("res://data/clothes/clothes_scarf.tres")
	if res != null:
		craft_pool.append(res)


## 数据驱动回退：未拖入任何 .tres 时，自动加载内置蓝图（供工坊显示）
func _ensure_blueprint_pool() -> void:
	if not blueprint_pool.is_empty():
		return
	for path in ["res://data/blueprints/blueprint_scarf.tres", "res://data/blueprints/blueprint_hat.tres"]:
		var res = load(path)
		if res != null:
			blueprint_pool.append(res)


## 注册 data/ 下各物品目录的全部资源进统一库存注册表。
## seeds/crops：农场逻辑据此解析 SeedData（阶段 0.9/2.3）。
## materials/craft：工坊制作（2.4）的「材料输入」与「成品产出」需经注册表解析名称/分类。
func _register_item_resources() -> void:
	for dir in ["res://data/seeds/", "res://data/crops/", "res://data/materials/", "res://data/craft/", "res://data/clothes/"]:
		for path in _list_data_dir(dir):
			var d = load(path)
			if d is ItemData:
				GameManager.register_item(d)


## 返回当前种子池的 id 列表（供一次性播种）
func _seed_ids() -> Array:
	var out: Array = []
	for s in seed_pool:
		if s != null and not s.id.is_empty():
			out.append(s.id)
	return out


## 列出目录下全部 .tres 路径（用于数据驱动注册）
func _list_data_dir(dir: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null:
		push_warning("数据目录扫描失败（导出构建常见）：%s" % dir)
		return out
	d.list_dir_begin()
	var f := d.get_next()
	while not f.is_empty():
		if not d.current_is_dir() and f.ends_with(".tres"):
			out.append(dir + f)
		f = d.get_next()
	d.list_dir_end()
	return out


## 数据驱动回退：未拖入任何 .tres 时，自动加载内置五款服装（供注册/播种/换装用）
func _ensure_clothes_pool() -> void:
	if not clothes_pool.is_empty():
		return
	# 回退加载：注意围巾在 data/clothes/ 子目录，路径要带子目录前缀
	for path in [
		"res://data/clothes_hat.tres", "res://data/clothes_shirt.tres",
		"res://data/clothes_skirt.tres", "res://data/clothes_shoe.tres",
		"res://data/clothes_gt.tres", "res://data/clothes/clothes_scarf.tres",
	]:
		var res = load(path)
		if res != null:
			clothes_pool.append(res)


## 实例化桌面电话摆件，挂到 Panel 下，连接点击信号
func _instance_phone() -> void:
	var scene := preload("res://scenes/phone.tscn")
	var phone: Control = scene.instantiate()
	$Panel.add_child(phone)
	_phone = phone
	phone.phone_pressed.connect(_on_phone_pressed)


## 实例化桌面服装展架摆件（阶段 4.2），挂到 Panel 下，连接打开上架面板信号
func _instance_rack() -> void:
	var scene := preload("res://scenes/clothing_rack.tscn")
	var rack: Control = scene.instantiate()
	$Panel.add_child(rack)
	_rack = rack
	rack.rack_opened.connect(_on_rack_opened)


## 展架摆件点击 → 打开上架面板
func _on_rack_opened() -> void:
	_open_rack_panel()


## 实例化上架面板（覆盖层，轻点展架打开）
func _open_rack_panel() -> void:
	if _has_rack_panel():
		return
	GameManager.register_interrupt()   ## 番茄钟进行中打开上架面板=分心
	var scene := preload("res://scenes/rack_panel.tscn")
	var panel: Control = scene.instantiate()
	add_child(panel)
	panel.tree_exited.connect(_on_rack_exited)
	_rack_panel = panel


func _has_rack_panel() -> bool:
	return _rack_panel != null and is_instance_valid(_rack_panel)


func _on_rack_exited() -> void:
	_rack_panel = null


## 展架摆件是否被点中（ClothingRack 实现 contains_point）
func _rack_at_point(global_pos: Vector2) -> bool:
	if _rack == null or not _rack.has_method("contains_point"):
		return false
	return _rack.contains_point(global_pos)


## 电话点击：双击 → 打开订单中心（进行中订单 + 已到货 + 去商城）
func _on_phone_pressed() -> void:
	_open_phone_panel()


## 实例化订单中心弹窗（覆盖层，双击电话打开）
func _open_phone_panel() -> void:
	if _has_phone_panel():
		return
	GameManager.register_interrupt()   ## 番茄钟进行中打开订单中心=分心
	var scene := preload("res://scenes/phone_panel.tscn")
	var panel: Control = scene.instantiate()
	panel.product_pool = product_pool
	panel.shop_requested.connect(_on_phone_shop_requested)
	add_child(panel)


## 订单中心「去商城」→ 打开产品目录（订单中心留在下层，关闭目录后仍在）
func _on_phone_shop_requested() -> void:
	_open_catalog()


## 实例化产品目录弹窗（覆盖层）
func _open_catalog() -> void:
	if _has_catalog():
		return
	GameManager.register_interrupt()   ## 番茄钟进行中打开商城=分心
	var scene := preload("res://scenes/product_catalog.tscn")
	var panel: Control = scene.instantiate()
	panel.product_pool = product_pool
	panel.seed_pool = seed_pool
	add_child(panel)


## 遍历 PlacedItems 子节点，调用各自的 contains_point 进行命中判定
func _placed_at_point(global_pos: Vector2) -> Node2D:
	var container: Node2D = $Panel/PlacedItems
	if container == null:
		return null
	for c in container.get_children():
		if is_instance_valid(c) and c.has_method("contains_point") and c.contains_point(global_pos):
			return c
	return null


## 仓库「摆放」按钮回调：把该物品实例化为世界中的可摆放物体
func _on_placement_requested(data: ItemData) -> void:
	if placement_manager != null:
		placement_manager.spawn_from_product(data as ProductData)


# ═══════════════════ 阶段 1：四界面切换框架接线（步骤 1.3） ═══════════════════
## 编排职责：实例化/注册 4 个屏幕（本步为占位空屏，阶段 2 换真内容）、
## 把底部 TabBar 与 ScreenManager 互联。切屏互斥逻辑在 ScreenManager，
## 招牌点击/高亮在 TabBar，本处只做「接线」，符合低耦合 + SRP。

## 可切换屏定义：家园/种植/换装/工坊为四个对等主 tab，均注册进 ScreenManager
## （见 _setup_screens：先注册 home=$Panel，再注册本数组的 3 个屏）。
## 仓库是全局浮层（不在此注册）。此处为除 home 外的 3 个屏：种植/换装/工坊，
## 顺序与 TabBar.TABS（家园→种植→换装→工坊）对齐；home 注册在最前，故箭头循环 = [home, farm, wardrobe, workshop]。
const _SCREEN_DEFS := [
	{"id": "farm", "title": "种植屏（占位·阶段2填充）"},
	{"id": "wardrobe", "title": "换装屏"},
	{"id": "workshop", "title": "工坊屏"},
]


## 生成 4 个对等屏并注册进 ScreenManager，接通 TabBar 双向信号，初始高亮「家园」。
## 四个屏地位完全对等、互斥显隐（并列，而非“家园为底、其余覆盖”）：
##   ① 先注册 home（即 $Panel——家园专属内容：摆放物/顾客/宠物/灵感按钮/HUD 等，切屏时整体隐藏）；
##      CloseButton 单独上提至 Main 常驻（绘制序置顶，任意屏可关闭）。
##   ② 再注册种植/换装/工坊。注册顺序即箭头循环顺序 → [home, farm, wardrobe, workshop]，与 TabBar.TABS 一致。
## 仓库是全局浮层，由 _toggle_warehouse_global() 管理，不在此注册。
func _setup_screens() -> void:
	# ① 家园屏 = $Panel（家园专属内容容器），与其余三屏对等；注册即隐藏，结尾 go_home() 再显示
	screen_manager.register_screen(ScreenManager.SCREEN_HOME, $Panel)
	for def in _SCREEN_DEFS:
		var scr: Control
		match def["id"]:
			"wardrobe":
				scr = _make_wardrobe_screen()      ## 换装屏 = 复用换装场景（原右侧菜单「换装」并入）
			"farm":
				scr = _make_farm_screen()          ## 种植屏（阶段 2.3，完整玩法）
			"workshop":
				scr = _make_workshop_screen()      ## 工坊屏（阶段 2.4：制作 + 分解两子页）
		scr.name = "Screen_" + def["id"]
		screens_root.add_child(scr)
		screen_manager.register_screen(def["id"], scr)   ## 注册即隐藏
	# TabBar 点击 → 切屏/开全局浮层
	tab_bar.tab_selected.connect(_on_tab_selected)
	# 屏变化 → 回灌 TabBar 高亮（home/farm/wardrobe/workshop）
	screen_manager.screen_changed.connect(tab_bar.set_active)
	# 番茄钟拦截：进行中离开灵感活动去任一子屏记打断
	screen_manager.screen_changed.connect(_on_screen_changed)
	# 步骤 1.5：活动面板左右箭头导航（贴在屏两侧，绘制在屏之上，家园态/仓库浮层时隐藏）
	_arrow_nav = preload("res://scenes/arrow_nav.tscn").instantiate()
	add_child(_arrow_nav)                      ## 挂到 Main：绘制序在 screens_root / tab_bar 之上
	_arrow_nav.setup(screen_manager)
	# 初始进入家园态并高亮「家园」tab
	screen_manager.go_home()


## 番茄钟拦截：进行中离开灵感活动去任一子屏（种植/换装/工坊）记一次打断。
## home 为基地默认态不记；灵感面板/专注条本身不触发 screen_changed。
func _on_screen_changed(id: String) -> void:
	if id == "farm" or id == "wardrobe" or id == "workshop":
		GameManager.register_interrupt()


## 番茄钟专注条：实例化常驻右下角，连接信号。运行期不依赖场景内节点。
func _setup_focus_bar() -> void:
	_focus_bar = preload("res://scenes/focus_bar.tscn").instantiate() as FocusBar
	_focus_bar.visible = false
	_focus_bar.request_minimize.connect(_enter_focus_mode)
	_focus_bar.request_expand.connect(_exit_focus_mode)
	add_child(_focus_bar)                       ## 最后 add → 绘制序最高，盖在一切之上
	GameManager.activity_started.connect(_on_activity_started)
	GameManager.activity_finished.connect(_on_focus_activity_ended)
	GameManager.activity_cancelled.connect(_on_focus_activity_ended)
	# 若启动时已有进行中的活动（离线恢复），立即显示专注条
	if GameManager.is_activity_running():
		_on_activity_started()


## 番茄钟开始 → 显示专注条（展开态，游戏主界面照常可见）。外出不弹专注条。
func _on_activity_started() -> void:
	if GameManager.get_activity_mode() != ActivityData.Mode.POMODORO:
		return
	_focus_bar.visible = true
	_focus_bar.set_focus_collapsed(false)


## 番茄钟自然完成 / 放弃 → 隐藏专注条并恢复游戏主界面
func _on_focus_activity_ended(_p := {}) -> void:
	_focus_bar.visible = false
	_exit_focus_mode()


## 缩条态：隐藏游戏主内容，仅显专注条（玩家去做现实中的事）
func _enter_focus_mode() -> void:
	$Background.visible = false
	$Panel.visible = false
	$Screens.visible = false
	$TabBar.visible = false
	$CloseButton.visible = false
	_focus_bar.set_focus_collapsed(true)


## 展开态：恢复游戏主内容
func _exit_focus_mode() -> void:
	$Background.visible = true
	$Panel.visible = true
	$Screens.visible = true
	$TabBar.visible = true
	$CloseButton.visible = true
	_focus_bar.set_focus_collapsed(false)


## 换装屏：实例化换装场景作为常驻切屏内容。
## 隐藏其自带 CloseButton（切屏开合改由底部招牌 toggle 控制）；
## 传入衣服资源池；可见时自刷新由 wardrobe.gd 的 visibility_changed 负责。
func _make_wardrobe_screen() -> Control:
	var scene := preload("res://scenes/wardrobe.tscn")
	var w: Control = scene.instantiate()
	w.clothes_pool = clothes_pool
	var close_btn := w.get_node_or_null("CloseButton") as CanvasItem
	if close_btn != null:
		close_btn.hide()
	return w


## 种植屏（阶段 2.3）：实例化 farm_screen 场景，注入花盆 id，不足时经 shop_requested 打开商城。
func _make_farm_screen() -> Control:
	var scene := preload("res://scenes/farm_screen.tscn")
	var f: Control = scene.instantiate()
	f.shop_requested.connect(_on_phone_shop_requested)
	return f


## 工坊屏（阶段 2.4）：实例化 workshop_screen 场景，含「制作 / 分解」两子页。
## 数据全走 GameManager（blueprints / inventory / craft / decompose），屏只渲染交互。
func _make_workshop_screen() -> Control:
	var scene := preload("res://scenes/workshop_screen.tscn")
	var w: Control = scene.instantiate()
	return w


## 仓库 = 全局浮层（非切换屏）：任意屏激活时都能打开，不占用 tab 切换位。
## 实例挂到 Screens 容器内（绘制序在 TabBar 之下），故招牌栏始终可点、可再点收起。
## 其内部 × 关闭会 queue_free，tree_exited 时清空引用以便再次打开。
var _warehouse_panel: Control = null

# 上架面板（展架）引用（运行期实例化，见 _open_rack_panel）
var _rack_panel: Control = null

func _toggle_warehouse_global() -> void:
	if _has_warehouse():
		_warehouse_panel.queue_free()      ## × 按钮也会 queue_free，tree_exited 兜底清空
	else:
		_open_warehouse_global()
	# 仓库浮层打开时屏蔽左右箭头（浮层盖在屏之上，箭头无意义）；关闭即恢复
	if _arrow_nav != null:
		_arrow_nav.set_overlay_blocked(_has_warehouse())


func _open_warehouse_global() -> void:
	if _has_warehouse():
		return
	GameManager.register_interrupt()   ## 番茄钟进行中打开仓库=分心
	var scene := preload("res://scenes/warehouse_panel.tscn")
	var panel: Control = scene.instantiate()
	panel.placement_requested.connect(_on_placement_requested)
	screens_root.add_child(panel)          ## 置于 Screens 容器内 → 绘制在 TabBar 之下
	panel.tree_exited.connect(_on_warehouse_exited)
	_warehouse_panel = panel


func _has_warehouse() -> bool:
	return _warehouse_panel != null and is_instance_valid(_warehouse_panel)


func _on_warehouse_exited() -> void:
	_warehouse_panel = null
	## 仓库浮层被 × 关闭（queue_free）时同样解除箭头屏蔽
	if _arrow_nav != null:
		_arrow_nav.set_overlay_blocked(false)


## 构建一个占位屏（覆盖家园中央区、让出底部招牌栏）。阶段 2 会用真实屏替换。
func _make_placeholder_screen(title: String) -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP   ## 覆盖层拦截点击，不穿透到家园
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.offset_left = 28.0                            ## 步骤 1.5：左右留 gutter，避免被箭头遮挡
	bg.offset_right = -28.0
	bg.offset_bottom = -52.0                          ## 让出底部 52px 招牌栏
	bg.color = UITheme.BG_PANEL
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(bg)
	var label := Label.new()
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.offset_left = 28.0                         ## 与 bg 同 gutter，文字不压在箭头上
	label.offset_right = -28.0
	label.offset_bottom = -52.0
	label.text = title
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)
	root.add_child(label)
	return root


## 底部招牌点击：仓库→开/关全局浮层；其余→toggle 对应屏（再点当前屏则收起回家园）
func _on_tab_selected(id: String) -> void:
	if id == "warehouse":
		_toggle_warehouse_global()
	else:
		screen_manager.toggle_screen(id)
