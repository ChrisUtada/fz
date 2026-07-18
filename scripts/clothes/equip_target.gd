extends Control
## EquipTarget · 人物装备区（接收拖放的目标区域）
##
## 覆盖在 zz 人物底图上方，验证拖入数据类型，合法则委托给 Wardrobe 编排器执行装备。
## 同时处理"轻点已装备部位 → 请求脱下"：按下后未拖拽即松开的点击，向外发信号。

signal clothes_dropped(data: ClothesData)
signal clothes_unequip_requested(global_pos: Vector2)

## 刚完成一次拖放时，本次松开是拖放的收尾，不视为"点击脱下"
var _suppress_next_click := false


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("type") == "clothes"


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if data is Dictionary and data.has("data") and data["data"] is ClothesData:
		_suppress_next_click = true
		clothes_dropped.emit(data["data"])


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if event.pressed:
		# 新的按下开始，复位抑制标记（可能为一次真正的点击）
		_suppress_next_click = false
		return
	# 松开：若刚完成拖放则忽略；否则视为轻点脱下请求
	if _suppress_next_click:
		_suppress_next_click = false
		return
	clothes_unequip_requested.emit(get_global_mouse_position())
