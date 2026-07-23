class_name ItemData
extends Resource
## ItemData · 统一物品数据基类（Resource，纯数据）
##
## 所有可进入库存的物品（服装/种子/作物/材料）都继承它，
## 因此 GameManager.inventory 只需持有 `id -> count`，物品元数据统一从注册表按 id 解析。
##
## 分类说明：
##   - category 枚举只保留「背包里需要按类筛选」的 5 类：CLOTHING/SEED/CROP/MATERIAL/DECOR。
##   - 制作物（如围巾）本身就是服装，归 CLOTHING，不再单列 CRAFT。
##   - 蓝图（Blueprint）走独立的 BlueprintData（extends Resource），不在此分类内。
##   - 世界摆放物（台灯/桌子/花盆等）用 `category = DECOR` 标明类别，并配合 `is_placeable` 标志
##     （行为上区分「能否摆进世界」）。它们仍进 inventory，但仓库分类标签页（服装/种子/作物/材料）
##     会跳过 is_placeable 物品，统一收进「摆放」标签页。
##
## 新建具体物品：建一个继承 ItemData 的 .tres（如 SeedData/ProductData），
## 在检查器填字段即可，零代码改动（OCP）。
##
## 注意：.tres 头部必须写成 `[gd_resource type="Resource" script_class="XxxData" ...]`，
##       绝不能把自定义 class_name 放进 type=（否则运行时报 Cannot get class 'XxxData'）。

enum Category { CLOTHING, SEED, CROP, MATERIAL, DECOR }

@export var id: String = ""                       ## 唯一标识（库存 key，建议与文件名一致）
@export var display_name: String = ""             ## 展示名
@export var icon: Texture2D                       ## UI 图标（目录/仓库/展架预览）；占位阶段可留空
@export var category: Category = Category.CLOTHING  ## 背包分类（CLOTHING/SEED/CROP/MATERIAL/DECOR 五类；DECOR 为摆放物，不进服装/种子/作物/材料标签页）
@export var description: String = ""              ## 描述（可选）
@export var price: int = 0                         ## 展架售出价（金币）；服装类生效，摆放物等可不售
@export var is_placeable: bool = false            ## 是否世界可摆放物（区别于背包分类；true 时仓库收进「摆放」标签页）
@export var garden_placement: bool = false        ## 可作为种植屏功能槽容器（花盆类）。与 is_placeable 正交：本标志管「能否进种植槽」，is_placeable 管「能否摆桌面装饰」
## 预加载 MaterialCost，使其在 `Array[MaterialCost]` 泛型参数里对当前文件可见。
## 仅靠另一文件的 class_name 无法在「泛型参数」中被当前作用域解析，
## 会报 "Could not find type 'MaterialCost' in the current scope"；preload 成 const 即可。
## （与 BlueprintData 处理 required_materials 同款；material_cost.gd 仅反向引用 ItemData 类型，
##   不预加载本文件，故此处预加载不构成循环依赖。）
const MaterialCost = preload("res://scripts/resources/material_cost.gd")

@export var decompose_recipe: Array[MaterialCost] = []  ## 分解配方：每项 MaterialCost（直接引用产物资源 + 数量）；空=不可分解
@export var world_texture: Texture2D              ## 摆到世界里的贴图（区别于 icon/UI 用）；缺图时摆放物显示占位灰块
@export var placeable_scene: PackedScene          ## 该物品对应的可摆放场景（继承 Placeable 的 tscn）；为空则不可摆放
