class_name Placeable
extends Node2D
## Placeable · 可摆放物品基类（数据驱动外观）
## 由 PlacementManager 实例化并注入 ProductData。
## 表现：Sprite2D 显示 data.world_texture，缺图时显示占位灰块（ColorRect）。
## 交互：左键拖动点中区域即拖动；松手后 emit moved 通知存档（本期不做轻点交互收益）。
## 每类物品一个继承本类的 .tscn（chair/desk/lamp…），外观 / 未来交互差异由数据或子场景扩展。

signal moved(placeable)                 ## 位置/缩放变化后通知 PlacementManager 存档
signal remove_requested(placeable)      ## 预留：移除交互触发（本期未接 UI）

@export var data: ProductData

var _sprite: Sprite2D
var _placeholder: ColorRect
var _dragging := false
var _drag_offset := Vector2.ZERO


func _ready() -> void:
	_build_view()
	if data != null:
		apply_data(data)


func _build_view() -> void:
	_sprite = Sprite2D.new()
	_sprite.name = "Sprite"
	_sprite.centered = true
	add_child(_sprite)

	_placeholder = ColorRect.new()
	_placeholder.name = "Placeholder"
	_placeholder.color = Color(0.6, 0.6, 0.6)
	_placeholder.size = Vector2(48, 48)
	_placeholder.position = -_placeholder.size * 0.5
	_placeholder.visible = false
	add_child(_placeholder)


## 数据驱动入口：消费 ProductData，控制外观与缩放
func apply_data(d: ProductData) -> void:
	if d == null:
		return
	data = d
	name = "Placeable_" + d.id
	scale = Vector2(d.base_scale, d.base_scale)
	if d.world_texture != null:
		_sprite.texture = d.world_texture
		_sprite.visible = true
		_placeholder.visible = false
	else:
		_sprite.visible = false
		_placeholder.visible = true


## 矩形命中测试：global_pos 是否落在本体可见矩形内（Sprite 居中于 global_position）
func contains_point(global_pos: Vector2) -> bool:
	var size: Vector2
	if _sprite.visible and _sprite.texture != null:
		size = _sprite.texture.get_size()
	else:
		size = _placeholder.size
	size = size * scale
	var rect := Rect2(global_position - size * 0.5, size)
	return rect.has_point(global_pos)


func _input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			if contains_point(get_global_mouse_position()):
				_dragging = true
				_drag_offset = global_position - get_global_mouse_position()
				get_viewport().set_input_as_handled()
		else:
			if _dragging:
				_dragging = false
				moved.emit(self)
	elif ev is InputEventMouseMotion and _dragging:
		global_position = get_global_mouse_position() + _drag_offset
