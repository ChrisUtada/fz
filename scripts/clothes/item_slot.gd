extends TextureButton
## ItemSlot · 背包格子（单个衣物项）
##
## 显示衣服的 b 图预览图标，支持拖出（Godot 内置 Control 拖放系统）。
## 拖出数据包含 ClothesData 引用，由 EquipTarget 接收并装备。

var _data: ClothesData

## 由外部（Wardrobe）注入衣物数据并设置外观
func setup(item_data: ClothesData) -> void:
	_data = item_data
	if _data != null and _data.icon_texture != null:
		texture_normal = _data.icon_texture
		tooltip_text = "%s\n价格: %d | 灵感: %d" % [
			_data.display_name if _data.display_name else _data.id,
			_data.price,
			_data.inspiration_value
		]


## Godot 拖放系统：拖拽开始时返回数据（由父节点 Control 拖放管线调用）
func _get_drag_data(at_position: Vector2) -> Variant:
	if _data == null:
		return null

	# 创建拖拽预览（半透明放大版图标）
	var preview := TextureRect.new()
	preview.texture = _data.icon_texture
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.custom_minimum_size = Vector2(64, 64)
	preview.modulate.a = 0.7
	set_drag_preview(preview)

	return {
		"type": "clothes",
		"data": _data
	}
