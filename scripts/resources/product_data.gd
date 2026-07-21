class_name ProductData
extends ItemData
## ProductData · 商品数据（Resource，纯数据），继承自统一的 ItemData。
##
## 由产品目录 / 电话 / 仓库 / 摆放系统消费。通用字段（id/名称/图标/价格/分类/
## 分解配方/世界贴图/摆放场景）已由 ItemData 提供，这里只保留商品特有字段。
## 在编辑器检查器填：配送时长、基础缩放；分类固定为 PLACEABLE。
##
## 新增商品：再加一个 ProductData 的 .tres 资源并拖入 Main 的 product_pool，零代码改动（OCP）。
## 物品若要可摆放到游戏世界，填 placeable_scene（对应继承 Placeable 的 tscn）即可。
##
## 注意：.tres 头部必须写成 `[gd_resource type="Resource" script_class="ProductData" ...]`，
##       绝不能把自定义 class_name 放进 type=（否则运行时报 Cannot get class 'ProductData'）。

@export var delivery_minutes: int = 5              ## 配送时长（分钟），墙钟计时
@export var base_scale: float = 1.0               ## 摆放时的基础缩放

func _init() -> void:
	category = ItemData.Category.PLACEABLE
