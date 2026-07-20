class_name ProductData
extends Resource
## ProductData · 商品数据（Resource，纯数据）
## 由产品目录 / 电话 / 仓库消费。在编辑器的检查器中填入：名称、图标、价格、配送时长、描述。
## 新增商品：再加一个 ProductData 的 .tres 资源并拖入 Main 的 product_pool，零代码改动（OCP）。
## 物品若要可摆放到游戏世界，再建一个继承 Placeable 的 .tscn（如 chair.tscn）并填 placeable_scene 即可。
##
## 注意：.tres 头部必须写成 `[gd_resource type="Resource" script_class="ProductData" ...]`，
##       绝不能把自定义 class_name 放进 type=（否则运行时报 Cannot get class 'ProductData'）。

@export var id: String = ""                       ## 唯一标识（用于库存解锁判定，建议与文件名一致）
@export var display_name: String = ""             ## 展示名
@export var icon: Texture2D                       ## 商品图标（目录/仓库预览）；占位阶段可留空
@export var price: int = 50                        ## 购买价（金币）
@export var delivery_minutes: int = 5              ## 配送时长（分钟），墙钟计时
@export var description: String = ""               ## 描述（可选）
@export var world_texture: Texture2D              ## 摆到世界里的贴图（区别于 icon/UI 用）；缺图时摆放物显示占位灰块
@export var placeable_scene: PackedScene          ## 该物品对应的可摆放场景（每件一个 tscn，继承 Placeable）；为空则不可摆放
@export var base_scale: float = 1.0               ## 摆放时的基础缩放
