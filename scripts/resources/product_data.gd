class_name ProductData
extends Resource
## ProductData · 商品数据（Resource，纯数据）
## 由产品目录 / 电话 / 仓库消费。在编辑器的检查器中填入：名称、图标、价格、配送时长、描述。
## 新增商品只需再加一个 ProductData 的 .tres 资源并拖入 Main 的 product_pool，零代码改动（OCP）。
##
## 注意：.tres 头部必须写成 `[gd_resource type="Resource" script_class="ProductData" ...]`，
##       绝不能把自定义 class_name 放进 type=（否则运行时报 Cannot get class 'ProductData'）。

@export var id: String = ""                       ## 唯一标识（用于库存解锁判定，建议与文件名一致）
@export var display_name: String = ""             ## 展示名
@export var icon: Texture2D                       ## 商品图标（目录/仓库预览）；占位阶段可留空
@export var price: int = 50                        ## 购买价（金币）
@export var delivery_minutes: int = 5              ## 配送时长（分钟），墙钟计时
@export var description: String = ""               ## 描述（可选）
