extends Control
## EquipTarget · 人物装备区（接收拖放的目标区域）
##
## 覆盖在 zz 人物底图上方，验证拖入数据类型，
## 合法则委托给 Wardrobe 编排器执行装备逻辑。

signal clothes_dropped(data: ClothesData)


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("type") == "clothes"


func _drop_data(at_position: Vector2, data: Variant) -> void:
	if data is Dictionary and data.has("data") and data["data"] is ClothesData:
		clothes_dropped.emit(data["data"])
