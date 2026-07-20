class_name ActivityData
extends Resource
## ActivityData · 灵感活动数据（Resource，纯数据）
## 由 InspirationPanel 消费，描述一个“灵感活动”的配置。
## 在编辑器的检查器中填入：名称、图标、默认时长、每分钟灵感值、描述。
## 新增活动只需再加一个 ActivityData 的 .tres 资源并拖入 Main 的 activity_pool，零代码改动（OCP）。

@export var activity_name: String = "阅读"          ## 活动名称
@export var icon: Texture2D                          ## 活动图标（背包/列表预览）
@export var default_duration_minutes: int = 25      ## 默认时长（分钟），计时视图初始值
@export var inspiration_per_minute: float = 0.4    ## 每分钟获得的灵感值（检查器自由填入）；总灵感 = 时长 × 此值（向上取整，最小 1）            ## 完成获得的灵感值（检查器自由填入）
@export var description: String = ""                ## 描述（可选）
