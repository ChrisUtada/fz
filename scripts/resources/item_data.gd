class_name ItemData
extends Resource
## ItemData · 统一物品数据基类（Resource，纯数据）
##
## 所有可进入库存的物品（服装/种子/作物/材料/蓝图/制作物/摆放物）都继承它，
## 因此 GameManager.inventory 只需持有 `id -> count`，物品元数据统一从注册表按 id 解析。
##
## 新建具体物品：建一个继承 ItemData 的 .tres（如 SeedData/CropData/ProductData），
## 在检查器填字段即可，零代码改动（OCP）。
##
## 注意：.tres 头部必须写成 `[gd_resource type="Resource" script_class="XxxData" ...]`，
##       绝不能把自定义 class_name 放进 type=（否则运行时报 Cannot get class 'XxxData'）。

enum Category { CLOTHING, SEED, CROP, MATERIAL, BLUEPRINT, CRAFT, PLACEABLE }

@export var id: String = ""                       ## 唯一标识（库存 key，建议与文件名一致）
@export var display_name: String = ""             ## 展示名
@export var icon: Texture2D                       ## UI 图标（目录/仓库/展架预览）；占位阶段可留空
@export var category: Category = Category.CLOTHING  ## 物品分类（决定进仓库哪个标签页）
@export var description: String = ""              ## 描述（可选）
@export var price: int = 0                         ## 展架售出价（金币）；服装/制作物类生效，摆放物等可不售
@export var decompose_recipe: Array[Dictionary] = []  ## 分解配方：每项 {item_id:String, count:int}；空=不可分解
@export var world_texture: Texture2D              ## 摆到世界里的贴图（区别于 icon/UI 用）；缺图时摆放物显示占位灰块
@export var placeable_scene: PackedScene          ## 该物品对应的可摆放场景（继承 Placeable 的 tscn）；为空则不可摆放
