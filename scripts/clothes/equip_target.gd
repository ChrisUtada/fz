extends Control
## EquipTarget · 人物装备区（点击脱下区）
##
## 覆盖在 zz 人物底图上方，处理"轻点已装备部位 → 请求脱下"：
## 左键按下后未拖拽即松开，向外发信号，由 Wardrobe 按绘制层级命中检测脱下。
## （装备动作已改为背包格子单击触发，见 Wardrobe._on_slot_clicked，不再经拖放。）

signal clothes_unequip_requested(global_pos: Vector2)


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if event.pressed:
		return
	clothes_unequip_requested.emit(get_global_mouse_position())
