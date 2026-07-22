class_name ProductData
extends ItemData
## ProductData · 商品数据（Resource，纯数据），继承自统一的 ItemData。
##
## 由产品目录 / 电话 / 仓库 / 摆放系统消费。通用字段（id/名称/图标/价格/分类/
## 分解配方/世界贴图/摆放场景）已由 ItemData 提供，这里只保留商品特有字段。
## 在编辑器检查器填：配送时长、基础缩放。
##
## 摆放标记：商品是否可摆放到世界，由基类 ItemData.is_placeable 控制（_init 置 true），
## 不再占用 category 槽位。物品若要可摆放，填 placeable_scene（对应继承 Placeable 的 tscn）即可。
## 仓库里摆放物统一收进「摆放」标签页，不会混进服装/材料等分类。
##
## 新增商品：再加一个 ProductData 的 .tres 资源并拖入 Main 的 product_pool，零代码改动（OCP）。
##
## 注意：.tres 头部必须写成 `[gd_resource type="Resource" script_class="ProductData" ...]`，
##       绝不能把自定义 class_name 放进 type=（否则运行时报 Cannot get class 'ProductData'）。

@export var delivery_minutes: int = 5              ## 配送时长（分钟），墙钟计时
@export var base_scale: float = 1.0               ## 摆放时的基础缩放

func _init() -> void:
	category = ItemData.Category.DECOR             ## 商品归类为「装饰/摆放物」，检查器里显示为 DECOR 而非默认的 CLOTHING
	is_placeable = true                            ## 行为标志：可摆进世界；仓库分类标签页（服装/种子/作物/材料）会跳过，统一收进「摆放」
