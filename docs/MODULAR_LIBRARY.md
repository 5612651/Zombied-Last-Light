# 共享环境模块库

使用场景：Chapter 01 六个斜俯视战斗区域。风格沿用冷绿混凝土、锈橙金属、暖色应急灯与冷色荧光灯；模块在 Godot 中以米为单位，Y 向上，地面中心作为放置轴心。

`assets/modular_library.json` 是资源清单，含每个模块的类别、GLB 路径、尺寸、局部碰撞、三角面数及源对象数量。当前 38 模块覆盖 Road、Sidewalk、Wall、Shop、Apartment、Alley、Fence、Vehicle、Lamp、Trash、Sign、Vegetation 全部十二类，总计 24,692 三角面，GLB 合计约 1.4 MB。

`assets/modular_library_source.blend` 保留各模块的可编辑独立对象，按网格排列。每个运行时模块在 `assets/models/kit/`，按材质合批。`tools/build_modular_library.py` 可通过 Blender MCP 重新生成。字体标牌已导出为网格，无需终端用户安装字体。

`tools/build_chapter_maps.py` 从同一 Blender 模块集合复制实例，保留尺寸和相同网格数据，组装六张地图；不为每张地图重新建模。地图布局 JSON 记录每次模块放置及转换后的碰撞盒，GLB 合并静态网格以减少绘制调用。各地图另有独立 `_source.blend`，方便编辑。

| 地图 | 模块放置 | 特色 |
|---|---:|---|
| chapter_street | 72 | 公寓临街立面、商铺、斑马线与巷道 |
| chapter_shop | 73 | 便利店与药房、货架通道、补给箱 |
| chapter_apartments | 75 | 住宅院落、花坛、树木与围栏 |
| chapter_garage | 77 | 车位、立柱、厢式车辆与室内荧光照明，无雨 |
| chapter_fuel | 65 | 镂空剖视雨棚、商铺和运行时可爆炸加油机 |
| chapter_evac | 72 | 单停机坪、检查站、围栏和撤离标识 |

可交互汽车、油桶、电箱、加油机、垃圾桶和路障也复用模块 GLB，碰撞与玩法由运行时对象负责。玻璃使用运行时透明材质，以避免把不透明导入面板作为可碎玻璃。

交付约束：北部出口保持可达；近镜头边缘使用矮墙剖视；室内外天气独立配置；动态交互物不合入静态地图，破坏后可移除碰撞并更新导航。后续交接为关卡设计、Godot 实现和性能验收。
