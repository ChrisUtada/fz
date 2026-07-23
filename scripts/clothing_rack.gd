extends Control
## ClothingRack · 桌面服装展架摆件（阶段 4.2）
##
## 桌面常驻物件（挂在 Main 的 Panel 下）。交互沿用 phone 的「_input + contains_point」模式：
##   - 在展架上「按下并拖动」= 移动位置（松手存档）
##   - 轻点（几乎未移动）= 打开上架面板（emit rack_opened，由 Main 编排）
## 实现 contains_point 供 Main 的拖窗口守卫使用（点展架不拖窗口）。

signal rack_opened()

const SAVE_PATH := "user://rack_pos.cfg"

var _pressed := false              ## 鼠标左键此刻是否在展架矩形内按住
var _dragging := false             ## 已越过阈值、正在拖动中
var _press_mouse := Vector2.ZERO   ## 按下时鼠标全局坐标，用于判定拖动阈值
var _drag_offset := Vector2.ZERO   ## 按下点与展架原点的偏移


func _ready() -> void:
	_load_position()


## 用 _input + contains_point 自判命中（同 phone.gd）：
## 覆盖层弹窗打开时不抢占点击（先清空拖动态再 return，避免松手事件被吞导致幽灵拖动）。
func _input(ev: InputEvent) -> void:
	# 仅在家园屏可见时响应（切到其它屏时 $Panel 整体隐藏，展架不应拦截那里的点击）
	if not is_visible_in_tree():
		return
	if GameManager.is_modal_open():
		_pressed = false
		_dragging = false
		return
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			if contains_point(get_global_mouse_position()):
				_pressed = true
				_dragging = false
				_press_mouse = get_global_mouse_position()
				_drag_offset = global_position - _press_mouse
				get_viewport().set_input_as_handled()
		else:
			if _pressed:
				if not _dragging:
					rack_opened.emit()        # 轻点 → 打开上架面板
				else:
					_save_position()          # 拖动结束 → 存档
				_pressed = false
				_dragging = false
				get_viewport().set_input_as_handled()
	elif ev is InputEventMouseMotion and _pressed:
		if Utils.exceeds_drag_threshold(get_global_mouse_position(), _press_mouse):
			_dragging = true
		if _dragging:
			global_position = get_global_mouse_position() + _drag_offset
		get_viewport().set_input_as_handled()


## 供 Main 拖窗口守卫：点击是否落在展架矩形内
func contains_point(global_pos: Vector2) -> bool:
	return get_global_rect().has_point(global_pos)


func _load_position() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	var x: float = cfg.get_value("rack", "x", NAN)
	var y: float = cfg.get_value("rack", "y", NAN)
	if is_nan(x) or is_nan(y):
		return
	global_position = Vector2(x, y)


func _save_position() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("rack", "x", global_position.x)
	cfg.set_value("rack", "y", global_position.y)
	Utils.write_save_version(cfg)
	if cfg.save(SAVE_PATH) != OK:
		push_warning("ClothingRack: 位置存档写入失败 %s" % SAVE_PATH)
