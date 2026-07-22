class_name MaterialCost
extends Resource
## MaterialCost · 蓝图材料项（纯数据），作为 BlueprintData.required_materials 数组的元素。
##
## 与「id 字符串 + 注册表查表」的做法对比，这里直接持有 ItemData 资源引用，
## 编辑器里是硬链接、不会拼错、改名不破，也不依赖物品是否注册进 _item_registry。
##
## 注意：.tres 头部必须写成 `[gd_resource type="Resource" script_class="MaterialCost" ...]`，
##       绝不能把自定义 class_name 放进 type=（否则运行时报 Cannot get class 'MaterialCost'）。

@export var item: ItemData                    ## 所需材料物品（直接引用资源，非 id 字符串）
@export var count: int = 1                    ## 需要的数量
