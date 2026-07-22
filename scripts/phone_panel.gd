extends Control
## PhonePanel · 订单中心弹窗（覆盖层，双击桌面电话打开）
##
## 合并原「桌面上逐单进度条」+「收货清单」：
##   - 进行中订单：物品名 + 进度条 + 剩余 MM:SS（每帧刷新，签名变化时重建行）
##   - 已到货：每件一个「领取」按钮 → GameManager.confirm_receipt_one（逐件入库）
##   - 底部「去商城」按钮 → shop_requested 信号，由 Main 打开产品目录
##
## 数据来自 GameManager（进行中订单 / 待收快照）。已到货列表仅在 arrived_changed
## 时重建（避免每帧重建按钮导致点击态抖动）；进行中列表每帧走 sig 判定，安全刷新。

signal shop_requested()

@export var product_pool: Array[ProductData] = []

@onready var _ongoing_list: VBoxContainer = $Card/Content/OngoingSection/OngoingList
@onready var _ongoing_empty: Label = $Card/Content/OngoingSection/EmptyLabel
@onready var _arrived_list: VBoxContainer = $Card/Content/ArrivedSection/ArrivedList
@onready var _arrived_empty: Label = $Card/Content/ArrivedSection/EmptyLabel
@onready var _close_btn: Button = $Card/Content/TitleBar/CloseButton
@onready var _shop_btn: Button = $Card/Content/ShopButton

## 进行中订单签名（id 列表），变化时重建列表，否则只更新进度
var _order_sig: String = ""
var _order_rows: Dictionary = {}   # id -> {bar: ProgressBar, time: Label}


func _ready() -> void:
	var bg := $Card/Bg as ColorRect
	if bg != null:
		bg.color = UITheme.BG_PANEL
	var title := $Card/Content/TitleBar/Title as Label
	if title != null:
		title.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)
	_close_btn.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)
	_close_btn.pressed.connect(_on_close)
	_shop_btn.pressed.connect(func(): shop_requested.emit())
	GameManager.arrived_changed.connect(_on_arrived_changed)
	_refresh_ongoing()
	_refresh_arrived()


func _exit_tree() -> void:
	# 断开信号，避免重复连接（弹窗可能被多次打开）
	if GameManager.arrived_changed.is_connected(_on_arrived_changed):
		GameManager.arrived_changed.disconnect(_on_arrived_changed)


func _process(_delta: float) -> void:
	_refresh_ongoing()


## 待收列表变化（领取后）重建已到货区块
func _on_arrived_changed() -> void:
	_refresh_arrived()


# ═══════════════════ 进行中订单（进度条 + 倒计时） ═══════════════════

func _refresh_ongoing() -> void:
	var orders: Array = GameManager.get_orders()
	var sig := ""
	for o in orders:
		sig += str(o["id"]) + ","
	if sig != _order_sig:
		_rebuild_ongoing(orders)
		_order_sig = sig
	else:
		# 仅更新现有行的进度/时间，避免每帧重建闪烁
		for o in orders:
			var row = _order_rows.get(o["id"])
			if row != null:
				row["bar"].value = o["progress"] * 100.0
				row["time"].text = _format_time(o["remaining_sec"])
	_ongoing_empty.visible = orders.is_empty()
	_ongoing_list.visible = not orders.is_empty()


func _rebuild_ongoing(orders: Array) -> void:
	for child in _ongoing_list.get_children():
		child.queue_free()
	_order_rows.clear()
	for o in orders:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)

		var name_l := Label.new()
		name_l.text = o["name"]
		name_l.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var bar := ProgressBar.new()
		bar.min_value = 0.0
		bar.max_value = 100.0
		bar.value = o["progress"] * 100.0
		bar.custom_minimum_size = Vector2(80, 0)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 不截获点击

		var time_l := Label.new()
		time_l.text = _format_time(o["remaining_sec"])
		time_l.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)
		time_l.custom_minimum_size = Vector2(40, 0)

		row.add_child(name_l)
		row.add_child(bar)
		row.add_child(time_l)
		_ongoing_list.add_child(row)
		_order_rows[o["id"]] = {"bar": bar, "time": time_l}


# ═══════════════════ 已到货（逐件领取） ═══════════════════

func _refresh_arrived() -> void:
	for child in _arrived_list.get_children():
		child.queue_free()
	var arrived: Array = GameManager.get_arrived()
	_arrived_empty.visible = arrived.is_empty()
	_arrived_list.visible = not arrived.is_empty()
	if arrived.is_empty():
		return
	for a in arrived:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var p: ProductData = _find_product(a["id"])
		var icon := _make_icon(p)
		var name_l := Label.new()
		name_l.text = a["name"]
		name_l.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var claim := Button.new()
		claim.text = "领取"
		claim.add_theme_color_override("font_color", UITheme.TEXT_PRIMARY)
		claim.pressed.connect(func(): _on_claim(a["id"]))
		row.add_child(icon)
		row.add_child(name_l)
		row.add_child(claim)
		_arrived_list.add_child(row)


func _on_claim(id: String) -> void:
	# 解锁进仓库 + 从待收移除；arrived_changed 会触发 _refresh_arrived 重建列表
	GameManager.confirm_receipt_one(id)


func _find_product(id: String) -> ProductData:
	for p in product_pool:
		if p != null and p.id == id:
			return p
	return null


func _make_icon(p: ProductData) -> Control:
	if p != null and p.icon != null:
		var tex := TextureRect.new()
		tex.texture = p.icon
		tex.custom_minimum_size = Vector2(32, 32)
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		return tex
	var ph := ColorRect.new()
	ph.color = UITheme.BG_SURFACE
	ph.custom_minimum_size = Vector2(32, 32)
	return ph


func _format_time(total_sec: float) -> String:
	var s := int(ceil(total_sec))
	var m := s / 60
	var sec := s % 60
	return "%02d:%02d" % [int(m), sec]


func _on_close() -> void:
	queue_free()
