# 安装与卸载

## 1. 准备依赖

本地实测环境为 Windows PC、Cyberpunk 2077 **2.5**，搭配：

- [CET 1.38.1](https://github.com/maximegmd/CyberEngineTweaks/releases/tag/v1.38.1)
- [RED4ext 1.31.0](https://github.com/WopsS/RED4ext/releases/tag/v1.31.0)
- [Codeware 1.21.2](https://github.com/psiberx/cp2077-codeware/releases/tag/v1.21.2)
- [redscript 0.5.32](https://github.com/jac3km4/redscript/releases/tag/v0.5.32)

退出游戏，按各依赖原作者的说明安装。已经使用其他 MOD 时，先核对已有版本。其他游戏补丁的兼容性尚未验证。

本 MOD 是 CET Lua 模组，不需要放入 `archive/pc/mod`，也不需要通过 REDmod 启用。

## 2. 安装模组

从 [Release](https://github.com/longsizhuo/night-city-lottery/releases/tag/v0.2.0) 下载 **NightCityLottery-0.2.0.zip**。GitHub 自动提供的 Source code 压缩包是源码目录，不是同样的安装布局。

找到包含 `bin`、`r6`、`archive` 的游戏根目录。Steam 用户可通过“管理 → 浏览本地文件”进入。

把安装包里的 `bin` 目录复制进去，合并目录。最终应当是：

```text
Cyberpunk 2077/
└─ bin/x64/plugins/cyber_engine_tweaks/mods/
   └─ NightCityLottery/
      ├─ init.lua
      ├─ battlefield.lua
      ├─ pool.lua
      ├─ THIRD_PARTY.txt
      └─ LICENSE
```

如果出现 `mods/NightCityLottery/NightCityLottery/init.lua` 这样的重复目录，需要修正层级。

## 3. 打开面板并设置按键

首次使用 CET，先按 CET 的提示设置一个面板开关键。示例录像使用键盘左上角的波浪键；其他键位同样可以。

进入存档、等街道场景载入完成，再打开 CET。在 **Bindings** 中找到以下三项，绑定后保存：

| CET 中的项目 | 推荐按键 | 作用 |
| --- | --- | --- |
| 随机队友 / Draw companion | F6 | 抽取或重新抽取，冷却 10 秒 |
| 召回队友 / Recall companion | F7 | 脱战后召回当前随机队友 |
| 解散队友 / Dismiss companion | F8 | 解散并清理本 MOD 生成的队友及演示小队 |

快捷键是推荐设置，需要你自己绑定。也可以打开“随机队友 · Night City Lottery”面板直接点按钮。

如果中文显示为方块，检查 CET 的字体设置，选择支持中文的字体 / ChineseFull 字符集，按 CET 说明重新启动。

## 4. 第一次试用

1. 进入自由探索，离开载具、座位及剧情演出，脱离战斗。
2. 找一处开阔、平坦的地面。
3. 点击“抽取 / 重新抽取”或按已绑定的 F6，等待“队友就位”。
4. 移动一段距离，观察跟随，再参与街头遭遇。
5. 脱战后可召回；结束时用 F8 清理。

不要在启动页、读档画面或剧情对话中尝试生成队友。

## 卸载与更新

卸载前先在已载入的游戏中用 F8 清理，再正常退出游戏，移除 `mods/NightCityLottery` 文件夹即可。其他 MOD 使用的 CET、Codeware 等依赖无需随本模组删除。

更新时先退出游戏，以新版文件替换同一个 `NightCityLottery` 目录中的模组文件。队友为临时实体，读档后需要重新抽取。
