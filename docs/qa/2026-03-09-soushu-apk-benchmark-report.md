# 2026-03-09 搜书大师 APK 逆向对照报告（v23.3）

## 1. 范围与目标
- 对象 APK：`e:\Antigavity program\book\wenwen_tome\tmp\apk_analysis\soushu\soushu.apk`
- 目标：提取对 `wenwen_tome` 可直接借鉴的搜书、书源、缓存、阅读器、TTS 设计。
- 重点：优先服务你当前反馈的 8 个痛点（搜书少、加书架无章节、EPUB/TXT卡顿、阅读交互、缓存、TTS崩溃等）。

## 2. 分析方法
- `aapt dump badging`：包信息、SDK、权限。
- `apkanalyzer manifest print`：Activity/Service/IntentFilter 架构。
- `apkanalyzer files list`：assets 与资源文件结构。
- 约束：本次未做 Java/Kotlin 反编译（无 JADX/apktool 可用），结论基于清单与资源结构，适合做架构复刻，不直接复制专有代码。

## 3. 关键证据（已验证）

### 3.1 基本信息
- 包名：`com.flyersoft.seekbooks`
- 版本：`v23.3`（`versionCode=230300`）
- `minSdk=21`，`targetSdk=29`，`compileSdk=30`

### 3.2 功能模块（Manifest）
- 网文搜索/浏览链路：
  - `com.flyersoft.WB.WebSearchAct`
  - `com.flyersoft.WB.WebSitesAct`
  - `com.flyersoft.WB.WebBookDetailAct`
  - `com.flyersoft.WB.BrowserAct`
  - `com.flyersoft.WB.WebCacheAct`
- 阅读器主界面：
  - `com.flyersoft.seekbooks.ActivityTxt`
- 下载与缓存：
  - `com.flyersoft.seekbooks.BookDownloadService`
  - `com.flyersoft.seekbooks.ChapterDownloadService`
- 朗读：
  - `com.flyersoft.source.service.HttpReadAloudService`
- 书源导入 Intent：
  - `ssds://booksource`
  - `yuedu://booksource`

### 3.3 资源结构（assets）
- 书源与收集配置：
  - `assets/default_source.json`
  - `assets/free_source.json`
  - `assets/auto_collect.json`
  - `assets/hotbooks.txt`
- TTS 配置：
  - `assets/httpTTS.json`
- 站点规则库（大量）：
  - `assets/cnweb/*.wj`
  - `assets/cnweb/*.wj2`
  - `assets/cnweb/*.sub`
- 本地数据迁移：
  - `assets/sql/2.sql` ~ `assets/sql/5.sql`
- 可见 Rhino 相关资源：
  - `org/mozilla/javascript/...`
  - 说明：存在基于 JS/规则解释执行的强迹象（用于站点解析逻辑的概率很高）。

## 4. 对你项目最有用的“可抄架构”

## 4.1 网文搜书（解决“搜出来太少”）
- 采用“书源并行聚合”而不是“网页关键词直抓”：
  - 输入关键词 -> 并发命中多个书源规则 -> 标准化结果 -> 去重（书名+作者+主站域名）。
- 结果页必须返回来源维度：
  - 每条结果保留 `sourceId/sourceName/detailUrl/chapterListUrl`，为后续“加入书架后拉章节”做链路保证。

## 4.2 加书架后无法阅读（解决“未获取网络章节”）
- “加入书架”拆成两阶段：
  1. `AddBook`: 先落库基础元数据（书名、作者、封面、来源、详情页链接）。
  2. `ResolveCatalog`: 后台任务拉章节目录并持久化（状态机：`pending -> loading -> success/failed`）。
- 阅读入口强制校验：
  - 无章节时不直接报错，触发一次 `ResolveCatalog` 重试并显示进度与错误原因。

## 4.3 网页搜书触屏问题（WebView交互）
- 单独定义 Web 搜书容器层：
  - 启用手势透传、禁止父容器拦截、滚动冲突处理（横向翻页模式下尤其要处理）。
- 浏览器加书架路径：
  - 右上角“加入书架”触发“当前URL匹配书源规则”，匹配成功后走统一 `AddBook + ResolveCatalog`。

## 4.4 EPUB/TXT 卡顿与乱码
- 解析与分页必须后台化（Isolate/Worker）：
  - `Parse -> DetectEncoding -> Normalize -> BuildChapters -> BuildPageMap` 全流程异步，不阻塞 UI。
- TXT 长文本：
  - 章节识别结果单独落库缓存，禁止每次打开重算。
  - 章节跳转和进度条仅操作索引映射，不直接重排全文。
- EPUB 乱码：
  - 统一编码检测与 HTML 清洗流程（优先 UTF-8，失败再回退），并对异常章节按段降级展示。

## 4.5 阅读交互（菜单/翻页）
- 提供点击策略开关（你提到的两种模式）：
  - `Mode A`: 中间点击召唤菜单，左右点击翻页。
  - `Mode B`: 全区域点击都召唤菜单（翻页仅手势/按钮）。
- 该设置进入阅读页后即时生效，避免重启页面。

## 4.6 下载缓存（本地离线）
- 下载任务模型分层：
  - 书级任务 -> 章节级任务（可暂停/继续/重试）。
- 缓存校验：
  - 每章保存状态与校验（章节标题、正文长度、更新时间），避免“显示已缓存但内容空”。

## 4.7 TTS 稳定性（解决卡死闪退）
- TTS 播放器与阅读器渲染彻底解耦：
  - 采用独立服务/控制器，不在 UI 线程做语音初始化。
- 朗读引擎切换入口：
  - 阅读页提供“引擎切换 + 语速 + 音色 + 网络/本地优先级”。
- 崩溃兜底：
  - 本地引擎初始化失败自动降级到备选引擎，并写入可读错误日志。

## 5. 与你当前 8 条问题的对照结论
- 1 内置 TTS 模型状态显示异常：需要“安装状态机 + 校验文件”而不是单一布尔值。
- 2 网页端不能触屏：WebView 手势冲突/父容器拦截是高概率根因。
- 3 搜书少 + 加书架不可读：核心是缺“书源并行聚合 + 加书架后二阶段拉目录”。
- 4 EPUB/TXT 卡顿/乱码/章节跳转卡死：核心是“解析分页未后台化 + 章节索引未缓存”。
- 5 阅读界面菜单呼出：需要可配置点击映射。
- 6 网文缓存：需要书级/章节级下载任务队列与状态落库。
- 7 下载 TTS 闪退 + 无切换：需要独立朗读服务和阅读页引擎切换面板。
- 8 翻译大模型去除：建议移除本地翻译大模型模块，统一走 API AI 翻译能力。

## 6. 直接落地建议（按优先级）
- P0（先做）：
  1) 网文“加书架后二阶段拉目录”重构。
  2) 阅读交互点击策略开关。
  3) TTS 独立控制器 + 引擎切换入口。
- P1：
  1) TXT/EPUB 后台解析与章节缓存。
  2) 浏览器加书架规则匹配与触屏冲突修复。
- P2：
  1) 书源导入协议兼容（`ssds://booksource`、`yuedu://booksource`）。
  2) 书源规则执行器（可先 JSON 规则，后续再扩展 JS 规则）。

## 7. 合规说明
- 可借鉴：模块边界、任务状态机、数据结构、交互流程、规则引擎设计。
- 不建议：直接复制其专有代码、资源、签名、品牌素材。
- 建议做法：基于你项目现有代码实现“等价功能”和“兼容协议”。

