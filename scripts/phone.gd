extends Control
## Phone · 桌面电话摆件
##
## 桌面常驻物件（挂在 Main 的 Panel 下）。职责：
##   - 显示所有进行中订单：每条 = 物品名 + 进度条 + 剩余 MM:SS
##   - 有到货时底部高亮「已到货 N 件，点击领取」
##   - 点击 → emit phone_pressed（由 Main 编排：有到货开收货清单，否则开产品目录）
##
## 计时由 GameManager 持有（墙钟 + 存档，离线到货），本摆件只负责显示。
## 实现 contains_point 供 Main 的拖窗口守卫使用（点击电话不拖窗口）。

signal phone_pressed()

@onready var _orders_box: VBoxContainer = $OrdersBox
@onready var _arrived_label: Label = $ArrivedLabel

## 订单集合签名（id 列表），变化时重建列表，否则只更新进度
var _order_sig: String = ""
var _order_rows: Dictionary = {}   # id -> {bar: ProgressBar, time: Label}

func _ready() -> void:
	_arrived_label.visible = false


## 用 _input + contains_point 自判命中（与顾客/宠物一致）：
## 不能用 _unhandled_input——父级 Panel(ColorRect) 全屏 mouse_filter=STOP，
## 会在 GUI 阶段抢先消费点击，事件根本到不了 _unhandled_input。
## _input 在 GUI 阶段之前触发，不受 mouse_filter 影响；命中后 set_input_as_handled
## 阻止事件继续传播（Main._input 因此不会把这次点击误当成窗口拖拽）。
func _input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
		if contains_point(get_global_mouse_position()):
			phone_pressed.emit()
			get_viewport().set_input_as_handled()


## 供 Main 拖窗口守卫：点击是否落在电话矩形内
func contains_point(global_pos: Vector2) -> bool:
	return get_global_rect().has_point(global_pos)


func _process(_delta: float) -> void:
	_refresh()


func _refresh() -> void:
	var orders: Array = GameManager.get_orders()
	var sig := ""
	for o in orders:
		sig += str(o["id"]) + ","
	if sig != _order_sig:
		_rebuild_orders(orders)
		_order_sig = sig
	else:
		# 仅更新现有行的进度/时间，避免每帧重建闪烁
		for o in orders:
			var row = _order_rows.get(o["id"])
			if row != null:
				row["bar"].value = o["progress"] * 100.0
				row["time"].text = _format_time(o["remaining_sec"])

	var count := GameManager.get_arrived().size()
	if count > 0:
		_arrived_label.visible = true
		_arrived_label.text = "已到货 %d 件，点击领取" % count
	else:
		_arrived_label.visible = false


func _rebuild_orders(orders: Array) -> void:
	for child in _orders_box.get_children():
		child.queue_free()
	_order_rows.clear()
	for o in orders:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)

		var name_l := Label.new()
		name_l.text = o["name"]
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var bar := ProgressBar.new()
		bar.min_value = 0.0
		bar.max_value = 100.0
		bar.value = o["progress"] * 100.0
		bar.custom_minimum_size = Vector2(56, 0)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 不截获点击，让 _unhandled_input 处理

		var time_l := Label.new()
		time_l.text = _format_time(o["remaining_sec"])
		time_l.custom_minimum_size = Vector2(40, 0)

		row.add_child(name_l)
		row.add_child(bar)
		row.add_child(time_l)
		_orders_box.add_child(row)
		_order_rows[o["id"]] = {"bar": bar, "time": time_l}


func _format_time(total_sec: float) -> String:
	var s := int(ceil(total_sec))
	var m := s / 60
	var sec := s % 60
	return "%02d:%02d" % [int(m), sec]
