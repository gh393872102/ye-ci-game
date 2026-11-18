# 权属与第三方登记

《夜祠》游戏代码、原创占位几何与数据的权利由甲方持有。本文件不擅自为游戏选择开源许可证。设计与数据来自甲方指定的 [ye-ci 方案仓库](https://github.com/gh393872102/ye-ci)，v0.2，2026-11-15。

| 名称 | 许可 / 处理方式 | 用途 |
| --- | --- | --- |
| Godot Engine 4.7.2 stable | MIT；源码工程不附带引擎。导出包附带官方许可说明及版权文件 | 2D 引擎与 GDScript 运行时 |
| 系统字体（PingFang SC / Microsoft YaHei / Noto Sans CJK SC） | 使用操作系统已安装字体；不复制、打包或再分发字体文件，各字体权利归其权利人 | 中文占位 HUD、标尺与调试文本 |

无第三方插件、无下载依赖、无网络运行要求。战场均为程序绘制的几何占位，不使用标准图作为运行时背景或发行美术。图 07、13、25 只在工程外读取作为验收参照。

P8 的 `assets/portraits/p8/` 为按本项目角色要求使用内置图像生成工具新生成的高分辨率静帧占位，仅出现在单位卡与图鉴。逐图来源、提示词和替换状态记录在该目录的 `manifest.json`、`prompts.json` 与元数据文件；未将这些画像标为最终发行美术。最终 1.0 前仍需逐图美术审核和批准，不能因通过功能验收自动转为终稿。

Godot 官方许可与第三方版权：[license](https://godotengine.org/license/)、[COPYRIGHT.txt](https://github.com/godotengine/godot/blob/4.7.2-stable/COPYRIGHT.txt)。

P9 简体中文界面随工程提供原版 Noto Sans CJK SC Regular，字体内嵌版权信息保留，授权为 SIL Open Font License 1.1。字体与授权全文在 [resources/fonts](resources/fonts/)。标题和少数题签仍使用系统宋体及回退字体。P9 祠堂环境与器物美术使用内置图像生成工具创作，用于界面。

P11 的 19 个运行时 WAV 由项目自带的 [拟音生成器](tools/p11_make_foley.py) 使用 Python 标准库合成，逐字节再生成通过。报告中的两段试听截自 Godot CoreAudio 真实混音并保留原电平。未引入外部录音、音色库或音乐采样。
