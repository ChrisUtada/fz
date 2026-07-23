extends Control
## Phone · 桌面电话摆件（精简版）
##
## 桌面常驻物件（挂在 Main 的 Panel 下）。职责缩为两项：
##   - 显示「已到货 N 件 · 单击查看」提醒（有到货时）
##   - 「单击」左键 = 打开订单中心（emit phone_pressed，由 Main 编排）
##   进行中订单的进度条/倒计时已移入订单中心弹窗（phone_panel）。
##
## 计时与订单数据由 GameManager 持有（墙钟 + 存档，离线到货），本摆件只负责显示。
## 实现 contains_point 供 Main 的拖窗口守卫使用（点击电话不拖窗口）。
## 交互：在电话上「按下并拖动」= 移动位置（松手存档）；「单击」左键 = 打开订单中心。
##       鼠标过滤由 _input + contains_point 自判命中，与顾客/宠物一致，不依赖子节点
##       mouse_filter。

signal phone_pressed()

const SAVE_PATH := "user://phone_pos.cfg"

@onready var _arrived_label: Label = $ArrivedLabel

## 拖动状态
var _pressed := false              ## 鼠标左键此刻是否在电话矩形内按住
var _dragging := false             ## 已越过阈值、正在拖动中
var _drag_offset := Vector2.ZERO      ## 按下点与电话原点的偏移，拖动中保持
var _press_mouse := Vector2.ZERO      ## 按下时鼠标全局坐标，用于判定拖动阈值

func _ready() -> void:
	_arrived_label.visible = false
	_load_position()
	GameManager.arrived_changed.connect(_on_arrived_changed)
	_refresh()   # 初始（含跨会话已到货）显示


func _exit_tree() -> void:
	# 断开信号，避免节点重建时重复连接
	if GameManager.arrived_changed.is_connected(_on_arrived_changed):
		GameManager.arrived_changed.disconnect(_on_arrived_changed)


## 待收列表变化（到货 / 领取）时刷新提醒，替代每帧轮询。
func _on_arrived_changed() -> void:
	_refresh()


## 用 _input + contains_point 自判命中（与顾客/宠物一致）：
## 不能用 _unhandled_input——父级 Panel(ColorRect) 全屏 mouse_filter=STOP，
## 会在 GUI 阶段抢先消费点击，事件根本到不了 _unhandled_input。
## _input 在 GUI 阶段之前触发，不受 mouse_filter 影响；命中后 set_input_as_handled
## 阻止事件继续传播（Main._input 因此不会把这次点击误当成窗口拖拽）。
##
## 状态机：
##   press(命中)  → _pressed=true；release 时若未拖动(纯点击)则打开 UI
##   motion(_pressed) → 用「鼠标位移」越过阈值即置 _dragging，随后跟随鼠标移动位置
##   release      → 若 _dragging 则存档；清空 _pressed/_dragging
## 关键陷阱：阈值判定必须基于「鼠标位移」，不能用 global_position（电话自身位置）——
## 电话只在 _dragging==true 时才移动，若阈值用电话位移判定会陷入「要动才标记动」的
## 死锁，永远动不了。同理，set_input_as_handled 只在确实命中电话时调用，否则会吞掉
## 全局 release 事件导致其它弹窗按钮（需 press+release）全部点不动。
func _input(ev: InputEvent) -> void:
	# 覆盖层弹窗打开时不抢占点击（同 customer.gd，避免吃掉弹窗按钮的点击）。
	# 关键：必须先清空拖动态再 return——否则「单击打开订单中心」那次的 release 会被本守卫
	# 吞掉，_pressed 残留为 true；关闭弹窗后鼠标一动即触发「幽灵拖动」，电话跳到指针处。
	if GameManager.is_modal_open():
		_pressed = false
		_dragging = false
		return
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			if contains_point(get_global_mouse_position()):
				var m := get_global_mouse_position()
				_pressed = true
				_dragging = false
				_press_mouse = m
				_drag_offset = global_position - m
				# 命中电话即接管事件，避免穿透到窗口拖拽；
				# 真正「打开」推迟到 release 判定（纯点击=开，拖动=移动）。
				get_viewport().set_input_as_handled()
		else:
			# 松开：仅当这次确实是一次电话按下（_pressed）时才处理+消费事件，
			# 否则不要 set_input_as_handled——否则会吞掉弹窗按钮所需的 release。
			if _pressed:
				if _dragging:
					_save_position()
				else:
					# 纯单击（位移未越过拖动阈值）= 打开订单中心
					phone_pressed.emit()
				_pressed = false
				_dragging = false
				get_viewport().set_input_as_handled()
	elif ev is InputEventMouseMotion and _pressed:
		# 阈值判定用鼠标位移（_press_mouse），不能用电话自身 global_position——
		# 后者只在已拖动时才变化，会形成死锁。
		if Utils.exceeds_drag_threshold(get_global_mouse_position(), _press_mouse):
			_dragging = true
		if _dragging:
			global_position = get_global_mouse_position() + _drag_offset
		get_viewport().set_input_as_handled()


## 供 Main 拖窗口守卫：点击是否落在电话矩形内
func contains_point(global_pos: Vector2) -> bool:
	return get_global_rect().has_point(global_pos)


## 读取存档位置（user://phone_pos.cfg）；无存档则保留 .tscn 默认位置
func _load_position() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	var x: float = cfg.get_value("phone", "x", NAN)
	var y: float = cfg.get_value("phone", "y", NAN)
	if is_nan(x) or is_nan(y):
		return
	global_position = Vector2(x, y)


## 保存当前位置到 user://phone_pos.cfg（Godot 全局坐标不随系统窗口拖动变化，稳定）
func _save_position() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("phone", "x", global_position.x)
	cfg.set_value("phone", "y", global_position.y)
	if cfg.save(SAVE_PATH) != OK:
		push_warning("Phone: 位置存档写入失败 %s" % SAVE_PATH)


## 仅刷新「已到货」提醒；进度条/倒计时已移入订单中心弹窗。
## 现在由 arrived_changed 信号驱动（见 _on_arrived_changed），不再每帧轮询。
func _refresh() -> void:
	var count := GameManager.get_arrived().size()
	if count > 0:
		_arrived_label.visible = true
		_arrived_label.text = "已到货 %d 件 · 单击查看" % count
	else:
		_arrived_label.visible = false
