# 文文Tome

文文Tome 是一个本地优先的跨平台电子书阅读器，当前主打 Windows 与 Android。

## 当前能力
- 导入 EPUB、PDF、MOBI、AZW3、TXT、CBZ、CBR
- 导入时可选择“另存到 App”或“直接引用源文件”
- 阅读器支持 EPUB 正文提取、TXT 正文显示、PDF 阅读、漫画压缩包阅读
- 网文模块支持搜书、网页搜索、URL 识别入库、书源导入导出、网页登录与 Cookie 管理
- 移动端内置大书源包，首次进入网文页即可直接使用搜书链路
- Windows 端已收敛为书架、同步、书源文件管理与更新日志查看
- 本地翻译模型下载、检测、启动与停止
- 本地 TTS 管理：内置中文声线、可下载扩展声线、Android 伴生引擎接入
- 启动链支持非阻塞预热、安全模式与后台恢复

## 当前版本
- 版本：`2.3.0+21`
- 日期：`2026-03-09`
- 代号：`聚焦与书源`

## 打包命令
- Android：`powershell -ExecutionPolicy Bypass -File scripts/build_android.ps1`
- Windows：`powershell -ExecutionPolicy Bypass -File scripts/build_win.ps1`
- Windows 安装包：`ISCC setup.iss`

## 目录说明
- `lib/`：业务代码
- `test/`：回归测试
- `assets/local_tts/`：随包 TTS 资源（仓库仅保留可直接随包的基础模型，超大扩展模型走下载）
- `tools/`：本地打包与运行时工具
- `releases/`：已生成版本产物
