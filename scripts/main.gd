extends Control

## 阶段 0：无边框 + 透明窗口骨架
## 功能：窗口去标题栏、背景透明、可拖拽移动、可关闭

var _dragging := false
var _drag_offset := Vector2i.ZERO


func _ready() -> void:
	var win := get_window()
	win.mode = Window.MODE_WINDOWED
	win.borderless = true        # 去标题栏
	win.transparent = true       # 背景透明（需 project.godot 中 per_pixel_transparency 开启）
	win.always_on_top = false    # 默认不置顶，避免遮挡其他工作


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_drag_offset = DisplayServer.window_get_position() - DisplayServer.mouse_get_position()
		else:
			_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		DisplayServer.window_set_position(DisplayServer.mouse_get_position() + _drag_offset)


func _on_close_pressed() -> void:
	get_tree().quit()
