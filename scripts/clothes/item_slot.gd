extends TextureButton
## ItemSlot · 背包格子（单个衣物项）
##
## 显示衣服的 b 图预览图标。点击格子即装备/脱下（由 Wardrobe 连接 pressed 信号处理），
## 已穿戴项显示「穿戴中」角标。

var _data: ClothesData

## 由外部（Wardrobe）注入衣物数据并设置外观
func setup(item_data: ClothesData) -> void:
	_data = item_data
	if _data != null and _data.icon != null:
		texture_normal = _data.icon
		tooltip_text = "%s\n价格: %d | 灵感: %d" % [
			_data.display_name if _data.display_name else _data.id,
			_data.price,
			_data.inspiration_value
		]
		update_worn_status()


## 实时更新「穿戴中」标签（装备/脱下后由 Wardrobe 调用）
func update_worn_status() -> void:
	var badge := get_node_or_null("WornBadge")
	if GameManager.is_worn(_data.id):
		if badge == null:
			_add_worn_badge()
	else:
		if badge != null:
			badge.queue_free()


## 在格子右上角叠加「穿戴中」角标
func _add_worn_badge() -> void:
	var worn := Label.new()
	worn.name = "WornBadge"
	worn.text = "穿戴中"
	worn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	worn.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	worn.add_theme_font_size_override("font_size", 11)
	worn.add_theme_color_override("font_color", UITheme.TEXT_GOLD)
	worn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	worn.position = Vector2(-2, 2)
	add_child(worn)
