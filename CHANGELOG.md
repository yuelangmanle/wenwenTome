# 文文Tome 更新日志

本文件记录近期可交付版本的主要变化。

## [2.6.12] - 2026-03-13 「分页稳定性与云端出包修复」
### 修复与优化
- TXT 编码判定改为候选评分，优先在 `utf-8 / gb18030 / utf-16` 中选择更可读结果，减少长篇中文 TXT 被误判成乱码。
- 长 TXT 保留翻页模式，超大文件只启用后台分段加载；仅在极端超长文本下才强制切滚动，避免“一打开就自动滚动阅读”。
- 分页阅读跨章节切换时不再强依赖 `page_flip` 的 `goToPage` 跳转，改为重建 page curl 视图并做降级兜底，降低跨章节闪屏和空指针崩溃。
- Windows 安装包版本提升到 `2.6.12`，补齐云端打包所需的 Inno Setup 语言资源跟踪。

## [2.6.11] - 2026-03-11 「全量收敛与网页阅读闭环」
### 新增
- reader_mode 网页阅读闭环：识别 → 进入阅读模式 → 加书架 → 缓存 → 目录。
- 搜书结果流式增长 + 聚合展示 + 详情补齐（双标签页）。
- AI 搜书重排与非小说过滤；AI 书源修复（影子验证）+ 版本回滚。
- EPUB 解析缓存、TXT 超大文本懒加载与后台补齐。
- 翻页仿真二（TurnPageView）+ 预分页耗时埋点。
- `RUN_EVENT` 补齐：webnovel 搜书会话、reader_mode 识别、AI 任务、memory pressure。

### 修复与优化
- 点击区域逻辑统一，音量键翻页去重并可关闭。
- UI 文案与字体名称清洗，修复乱码展示。
- 书源搜索与网页搜索严格分离，兜底需显式开启。
- TXT 分页改为渐进式分页，大文件默认切换滚动模式并支持一键切回。
- 超大 TXT 改为流式后台加载，减少冷启动卡顿并持续补齐滚动内容。
- 阅读页新增底部状态栏（电量/章节/进度/剩余时间），阅读体验更接近搜书大师。
- 仿真翻页2替换为 PageCurl 拖拽翻页，移除重复“翻页”模式。
- 网文页搜索结果与并发设置持久化，切换页面不再清空。
- 网页识别优先使用 WebView DOM 抽取，返回键优先回退网页。
- 书源管理入口直达设置/网文菜单，修复移动端菜单乱码与无响应。
- 搜书 AI 重排结果显示“AI 已排序/过滤”提示。
- 网文页补充“书源管理 / AI 搜索增强”显式入口与配置提醒。

## [2.6.10] - 2026-03-11 「翻译收敛与稳定性观测」
### 新增
- 稳定性观测：补齐“闪退/未捕获异常/卡死（事件循环阻塞）/严重卡顿帧”的结构化运行日志（`RUN_EVENT`）。

### 修复与优化
- 翻译模块策略收敛：下线默认“本地翻译大模型”入口，翻译与 AI 统一走已配置的 API；迁移旧配置（`useLocalTranslate` 自动降级）。
- UI 文字乱码清理：修复设置页与阅读页的目录/书签/加载提示等乱码。
- Windows 出包稳定性：修复路径含空格导致的 Windows 构建失败（SUBST 映射改为父目录映射）；预拉取/解压 PDFium，避免 CMake 下载产物为 0 字节。
- 内置书源清理：修复喜马拉雅内置源 URL 占位符乱码；清理内置书源规则中的“�”占位符，避免在书源编辑界面出现乱码。

### 测试与复现
- flutter analyze --no-fatal-infos
- flutter test
- powershell -ExecutionPolicy Bypass -File scripts/release_check.ps1 -SkipWindows

## [2.6.9] - 2026-03-11 「质量闭环与发布检查」
### 新增
- 运行日志关键事件标准化：关键路径写入 `RUN_EVENT`（action/result/error_code + context + duration）。
- 发布前检查脚本：新增 `scripts/release_check.ps1`（版本一致性 + analyze/test + 可选出包）。
- QAT 回归集脚本：新增超大 TXT 样本与异常 EPUB 样本生成脚本（生成型样本，不提交大文件）。
- 弱网/高延迟回归：新增 webnovel 高延迟超时回归用例（测试侧可配置超短 timeout）。

### 修复与优化
- Windows 出包脚本默认将 `PUB_CACHE/TEMP` 放在项目目录内，避免构建缓存落到系统盘。
- 网文书源连通性测试文案修复（避免乱码）。

### 测试与复现
- flutter analyze --no-fatal-infos
- flutter test
- powershell -ExecutionPolicy Bypass -File scripts/release_check.ps1 -SkipWindows

## [2.6.8] - 2026-03-10 「格式与目录跳转收敛」
### 修复与优化
- PDF：目录页码映射归一化，支持按目录跳页；阅读进度与书签按页持久化。
- MOBI/AZW3：自动转换链路可解释失败（平台限制/工具缺失/DRM 等），并复用已有 `_converted.epub` 结果。
- 阅读器：目录弹层列表改为懒加载；分段分页模式下目录跳转请求可在分页完成后生效，减少大目录卡顿。

### 测试与复现
- flutter test
- 手工复现：打开带目录的 PDF，点目录条目跳页；拖动进度条跳页；添加书签后可在书签列表跳回该页。

## [2.6.7] - 2026-03-10 「缓存下载服务化」
### 新增
- 新增网文章节缓存下载任务系统：书级任务展开为章级任务，任务状态可持久化并在重启后自动恢复。
- 新增缓存管理页：查看任务列表/空间占用，支持暂停/继续、清理任务、清空缓存。
- 新增缓存清理策略：支持按“缓存上限（MB）/最多保留本数/保留天数”进行自动清理与限额控制。

### 修复与优化
- 网文章节缓存表补充 `last_accessed_at` 与 `size_bytes`：为 LRU/配额清理提供可计算依据。
- 阅读页与网文中心的“缓存”改为后台任务模式：避免长时间阻塞 UI，进度可在缓存管理页追踪。
- 缓存任务入队去重与暂停语义收敛：同一本书重复入队会合并范围；处于“暂停全部”时新增任务保持暂停不自动开跑。

### 测试与复现
- flutter test
- 手工复现：阅读页点击“缓存后续章节”，在“设置 → 网文缓存管理”查看任务进度；设置缓存上限后观察自动清理生效。

## [2.6.6] - 2026-03-10 「搜书质量工程化」
### 新增
- 新增搜书“查询扩展”开关：可选为关键词补充站点/类型词，提升弱关键词命中率。
- 新增搜书并发度开关：可按网络环境调整并发，减少“全军覆没式超时”。
- 新增搜书失败报告：按书源聚合超时/空结果/异常，空态给出可操作建议。
- 新增书源导入详细报告：每条记录 imported/updated/skipped/failed，并统计 `updatedCount`。
- 新增书源管理页“复制导入报告”：便于用户回溯失败原因与定位问题书源（最多 200 行）。

### 修复与优化
- 搜书排序与去噪：结果按“来源可信度”打分，直接命中优先；疑似搜索/索引页结果降权。
- 入库候选 URL 策略优化：识别页入库优先选取目录/TOC 类链接，提高后续拉目录命中率。
- 书源导出一致性：导出仅包含自定义书源（排除内置），支持“导出→再导入”闭环。
- 导入来源统一：`file://` 自动转本地路径；`content://` 作为流式来源优先处理；白名单提示补齐 `CBR`。

### 测试与复现
- flutter test test/webnovel_repository_test.dart test/webnovel_screen_test.dart test/webnovel_source_pack_compat_test.dart

## [2.6.5] - 2026-03-10 「搜书质量基础」
### 新增
- 新增搜书标签筛选：书源标签可多选筛选，筛选后只搜索匹配标签的书源。

### 修复与优化
- 书源导入字段映射补齐：非 Legado 书源缺少 `siteDomains` 时自动从 baseUrl 推断并回填。
- 搜书结果去重策略增强：按 `title + author + detailUrl` 指纹聚合，减少重复刷屏。
- 搜书结果排序稳定性提升：去重时保留更高优先级/更匹配的结果。

### 测试与复现
- 手工复现（标签筛选）：在搜书页点击“筛选标签”，选择 1~2 个标签后搜索，结果只来自对应书源。
- 手工复现（去重）：导入包含重复书源的书包，搜索同一关键词，结果列表不重复刷屏。

## [2.6.4] - 2026-03-10 「会话归档与TTS服务化」
### 新增
- 新增网页搜索会话保存与按站点归档：登录站点后可保存 Cookie，会话列表按站点分组并支持一键应用到 WebView。
- 新增浏览历史管理：识别历史按站点归档，支持单条删除与按站点/全部清空。
- 新增 TTS 会话控制器：TTS 状态与阅读 UI 解耦，统一管理播放/暂停/恢复/停止。
- 新增长时 TTS 稳定性回归用例：新增 `test/tts_long_playback_smoke_test.dart`（虚拟 30 分钟朗读）。

### 修复与优化
- 网文请求支持按站点会话回落：当 source 会话缺失时按域名回落 Cookie 与 User-Agent。
- 阅读页 TTS 面板接入会话状态监听，播放状态更稳定。

### 测试与复现
- flutter test test/tts_long_playback_smoke_test.dart test/tts_service_split_test.dart
- 手工复现（会话保存/复用）：网页搜索打开站点并登录后点击“保存会话”，在会话页选择站点会话应用，刷新后保持登录。
- 手工复现（历史归档）：识别多个站点页面后，在历史页按站点查看并清除记录。

## [2.6.3] - 2026-03-10 「Step2-3 阅读交互收尾」
### 修复
- 修复超长 TXT 首屏卡顿：TXT 目录解析改为后台异步构建，首屏先渲染正文，目录完成后自动回填。
- 修复分页阅读超长章节抖动：章节过长时自动拆分为可分页的小段，减少单段分页耗时。
- 修复阅读模式切换跳页：分页/滚动切换时按当前位置迁移进度，避免切换后跳页。
- 修复阅读菜单误触：覆盖层显示时优先关闭菜单不翻页，进度拖动期间菜单不自动隐藏。

### 测试与复现
- flutter test test/reader_document_probe_test.dart test/reader_document_probe_recovery_test.dart test/reader_text_paginator_test.dart test/reader_text_paginator_cache_test.dart test/reader_settings_provider_test.dart
- 手工复现（TXT 首屏）：导入 300KB+ TXT，打开阅读页应先显示正文，稍后目录自动补全。
- 手工复现（模式切换）：分页/滚动相互切换，进度保持在当前位置附近不跳章。
- 手工复现（菜单触控）：覆盖层显示时点击左右区域不翻页，仅关闭菜单；拖动进度条时菜单不自动隐藏。

## [2.6.2] - 2026-03-10 「Step3-4 阅读与TTS稳态」
### 修复
- 修复超长 TXT/EPUB 分页性能退化：分页结果加入布局维度缓存（字号/行高/宽度等），重复进入或微调设置可直接复用，减少重新分页耗时。
- 修复异常 EPUB 打开后无正文：解析失败时自动回退到 raw 内容提取并带超时兜底，目录仍可生成。
- 修复 TTS 稳定性与恢复：朗读改为分段队列串行，加入并发防抖、前后台中断恢复、失败自动降级到系统 TTS，避免下载模型后闪退。
- 修复 TTS 分段预读中断：下一段合成失败可回退重试，不再整体中断朗读。

### 测试与复现
- flutter test test/reader_document_probe_test.dart test/reader_document_probe_recovery_test.dart test/reader_text_paginator_test.dart test/reader_text_paginator_cache_test.dart test/tts_service_split_test.dart test/local_tts_configuration_test.dart
- 手工复现（超长 TXT 分页性能）：导入 300KB+ TXT，分页模式下返回阅读页或微调字号/行距，预期分页生成明显更快且翻页稳定。
- 手工复现（异常 EPUB 兜底）：打开破损/截断 EPUB，预期仍可读正文且目录可跳转。
- 手工复现（TTS 稳定性）：下载本地模型后在阅读页切到离线 TTS 开始朗读，前后台切换或来电后恢复朗读不闪退；若离线失败自动回退到系统 TTS 并提示。

## [2.6.1] - 2026-03-10 「Step1-2 搜索跳转热修」
### 修复
- 修复网页搜索二级跳转边界：将导航补丁适配范围扩展到 baidu/sogou/so/sohu 相关域名，减少百度与搜狗/搜狐场景下点击结果后无法继续进入站内详情页的问题。
- 修复深链回退命中率：补充 u/ru/jumpurl/link/fromurl/srcurl 等参数解析，并支持多轮 URL 解码，提升重定向链接回退到 http(s) 目标页的成功率。

### 测试与复现
- flutter test test/webnovel_screen_test.dart test/webnovel_repository_test.dart
- flutter analyze lib/features/webnovel/presentation/webnovel_screen.dart
- 手工复现（网页搜索二级跳转）：
  1. 在网页搜索切换到 Bing/百度/搜狗（或搜狐系结果页）分别检索同一关键词。
  2. 点击搜索结果后，再次点击站内下一层链接（含新窗口链接/跳转链接）。
  3. 预期：可继续进入目标站点详情页，不会停留在搜索中转层。

## [2.6.0] - 2026-03-10 「Step1-2 主链路收敛」
### 修复
- 修复阅读页菜单与提示文案乱码：阅读外观面板、TTS 面板、目录弹层、章节加载提示、书签提示等核心 UI 文案恢复为可读中文。
- 修复网文目录弹层定位错误：打开目录时会按当前阅读位置定位（网文章节不再固定显示第一章）。
- 修复百度/搜狗网页搜索二级点击失败：补齐 window.open/target=_blank 接管、深链 http(s) 回退和站点点击导航补丁，提升二次跳转成功率。
- 修复网页搜索识别后的主链路：从“仅网页内预览阅读”改为“优先识别入库书架 + 后台目录同步 + 预缓存前 20 章”。
- 修复网文目录刷新后的缓存一致性：目录变更时会重建章节映射并迁移可复用缓存，避免“章节索引更新后缓存错位/失效”。
- 修复换源后进度漂移：切主书源时按章节标题优先映射阅读位置，失败时按进度比例兜底迁移。
- 修复 TXT 编码容错边界：新增 UTF-16（无 BOM）识别逻辑，减少导入乱码概率。
- 修复 EPUB“只有章节名、无正文”场景：主解析与压缩包 fallback 并行评估，自动选择正文质量更高的结果。
- 优化文档解析性能：阅读探测结果新增文件维度缓存（格式 + 路径 + 文件元信息 + 版本键），降低重复打开大文件的解析开销。

### 测试与复现
- flutter test test/webnovel_repository_test.dart test/webnovel_screen_test.dart test/reader_settings_provider_test.dart
- flutter test test/book_text_loader_test.dart test/reader_document_probe_test.dart
- flutter analyze lib/features/webnovel/presentation/webnovel_screen.dart lib/features/webnovel/webnovel_repository.dart lib/features/reader/book_text_loader.dart lib/features/reader/reader_document_probe.dart lib/features/reader/presentation/reader_screen.dart（仅剩既有 info 级提示）
- 手工复现（阅读菜单乱码）：打开阅读页，点击目录/外观/TTS，确认菜单和提示文案均为正常中文。
- 手工复现（网页搜索二级跳转）：在网页搜索分别使用 Bing/百度/搜狗，点击结果后继续点站内链接（含新窗口链接），确认可继续进入目标站点。
- 手工复现（识别入库与缓存）：网页搜索中进入详情页后点“识别入库并缓存”，确认书籍进入书架并触发后台目录同步与章节预缓存。
- 手工复现（目录定位）：打开已阅读到中间章节的 TXT/EPUB/网文，点目录按钮，确认自动滚到当前章节附近并高亮。

## [2.5.0] - 2026-03-10 「阅读交互与导入稳态」
### 新增
- 新增阅读页「音量键翻页」开关（Android）：支持 音量+ 上一页、音量- 下一页，可在阅读外观设置中随时开关并持久化。
- 新增内置开源字体族：MiSans、LXGWWenKai、LXGWWenKaiMono，阅读外观可直接切换，无需再手动导入。

### 修复
- 修复一次性导入多个文件（尤其多个大 TXT）时闪退：文件选择从全量内存读取改为流式落盘，显著降低导入峰值内存。
- 修复阅读页长按选字失效：滚动阅读与分页阅读正文改为可选择文本，并降低外层手势对文本选择的干扰。
- 修复阅读配色编辑体验：将原 HSV 条状滑杆改为真正调色盘，背景色与文字色都支持可视化取色和实时预览。

### 测试与复现
- flutter test test/import_and_download_policy_test.dart test/reader_settings_provider_test.dart
- flutter analyze lib/features/library/providers/library_providers.dart lib/features/reader/providers/reader_settings_provider.dart lib/features/reader/presentation/reader_screen.dart lib/features/reader/presentation/paged_text_reader.dart lib/features/reader/reader_volume_key_service.dart test/import_and_download_policy_test.dart test/reader_settings_provider_test.dart（仅剩既有 info 级提示）
- 手工复现（多文件导入）：同时选择 2 个以上大 TXT 导入书架，观察不再闪退；导入后可正常打开。
- 手工复现（音量键翻页）：阅读外观中打开「音量键翻页」，在分页模式下按 音量+/- 验证翻页；关闭开关后按键不再触发翻页。
- 手工复现（长按选字）：在 TXT/EPUB 阅读页长按正文，确认可出现系统文本选择手柄与复制菜单。
- 手工复现（调色盘）：在阅读外观中分别调整背景色与文字色，确认预览区实时生效并可持久化到下次打开。

## [2.4.0] - 2026-03-10 「阅读触控与入库稳态」
### 修复
- 修复 EPUB 打开后“只有章节名、无正文”的问题：当主解析只产出标题且无正文块时，自动回退到压缩包正文提取路径，不再把“仅标题文本”误判为成功内容。
- 修复 TXT/EPUB 分页跨章节滑动断点：分页视图支持章节边界越界手势衔接，滑到章节末尾可直接进入下一章节，滑到开头可回上一章节。
- 修复目录弹窗总是停在第一章的问题：目录打开时会定位并高亮当前阅读章节（含 TXT/EPUB），不再固定首项。
- 优化仿纸翻页动画（sheet/flip）：增强页角阴影、透视和位移参数，减少“塑料感”翻页。
- 修复网页搜索“不能二次点进网站”：补齐 target=_blank 新窗口接管、相对链接解析和导航放行策略，二级跳转可进入目标站点。
- 修复网页搜索引擎切换“看起来切了但不生效”：切换引擎后会立即对当前关键词重开检索。
- 调整网页搜索操作为触屏优先：移除“上翻/下翻”按钮，保留前进/后退/回顶，避免方向按钮误触并减少干扰。
- 修复“搜出来的书加入书架会获取失败”场景：入库详情解析新增“按详情 URL 域名回退候选书源”策略，sourceId 失效或错配时可回退到同域可用书源继续入库。
- 优化段落排布：阅读外观新增“文本对齐（两端/左对齐/居中）+ 段落排布（紧凑/均衡/舒朗）”选项并持久化。

### 测试与复现
- flutter test test/webnovel_repository_test.dart
- flutter test test/webnovel_screen_test.dart
- flutter test test/reader_settings_provider_test.dart
- flutter test test/reader_document_probe_test.dart
- flutter analyze lib/features/reader/presentation/reader_screen.dart lib/features/reader/presentation/paged_text_reader.dart lib/features/reader/providers/reader_settings_provider.dart lib/features/reader/reader_style.dart lib/features/reader/reader_document_probe.dart lib/features/webnovel/presentation/webnovel_screen.dart lib/features/webnovel/webnovel_repository.dart test/reader_settings_provider_test.dart test/webnovel_repository_test.dart（仅剩既有 DropdownButtonFormField.value info 级提示）
- 手工复现（阅读跨章节）：导入多章节 TXT 或 EPUB，分页模式下连续左右滑动跨章节，确认不会卡在章节边界；打开目录应自动定位到当前章节。
- 手工复现（EPUB 正文）：打开此前“仅章节名无正文”的 EPUB，确认正文可见且目录可跳转。
- 手工复现（网页搜索二次点进）：在网页搜索中打开搜索页后继续点击站内详情（含新窗口链接和相对链接），确认可进入目标页；切换搜索引擎后应立即重开关键词检索。
- 手工复现（入库回退）：构造 sourceId 失效但详情 URL 域名可匹配其他书源的搜索结果，点击加入书架应成功入库并进入后续目录同步。

## [2.3.3] - 2026-03-10 「阅读与TTS稳态」
### 修复
- 修复超长 TXT 分页退化问题：当原始目录缺失时，阅读器会自动生成“第 N 段”分段目录用于分页横翻，不再在常见超长文本场景强制退化为竖向滚动。
- 修复 EPUB 章节兜底标题乱码：章节名 fallback 统一为 章节N，目录与当前章节标题保持一致，不再出现乱码占位。
- 修复阅读页 TTS 引擎切换启动链路：在阅读页统一面板内补齐引擎可用性预检（本地模型、Android 外部引擎），不可用时直接提示并阻断启动。
- 修复下载模型后朗读稳定性：TtsService 增加本地模型可用性前置检查与本地合成全局串行锁，避免缺文件和并发启动导致的闪退风险。
- 修复本地 TTS 模型检测日志文案乱码，统一为可读中文提示，便于排障。

### 测试与复现
- flutter test test/reader_document_probe_test.dart
- flutter test test/local_tts_configuration_test.dart
- flutter analyze lib/features/reader/presentation/reader_screen.dart lib/features/reader/reader_document_probe.dart lib/features/reader/tts_service.dart lib/features/reader/local_tts_model_manager.dart test/reader_document_probe_test.dart（仅剩既有 deprecated info 提示）
- 手工复现（RDR-007）：导入无章节超长 TXT，设置阅读模式为分页，左右点击翻页应持续可用，不会被强制切回滚动。
- 手工复现（TTS-003/004）：在本地 TTS 管理页下载模型后，回阅读页切到离线模型并点“开始朗读”；若模型不完整应直接提示不可用，应用不闪退。

## [2.3.2] - 2026-03-10 「触控与跳章流畅度」
### 修复
- 修复网页搜索 WebView 触控策略：补齐点击、长按、拖动、缩放手势识别，安卓端可直接手势滚动与交互，不再依赖工具栏按钮滚动。
- 调整内嵌浏览器设置：启用 hybrid composition、wide viewport、内建缩放控件和双向滚动条，提升移动端页面点击与缩放稳定性。
- 修复阅读页进度条在频繁拖动时的抖动与并发跳转问题：新增 seek 提交防抖和串行执行，避免重复跳转造成卡顿。
- 修复章节跳转卡 UI：目录/书签跳章改为“占位态 + 异步跳转”，网文章节切换支持并发请求淘汰与加载提示，减少界面冻结感。
- 修复 test/webnovel_screen_test.dart 的仓储测试桩缺失 cacheBookChapters 实现导致的编译失败。

### 验证
- flutter test test/webnovel_screen_test.dart
- flutter analyze lib/features/webnovel/presentation/webnovel_screen.dart lib/features/reader/presentation/reader_screen.dart test/webnovel_screen_test.dart（仅剩既有 info 级提示）

## [2.3.1] - 2026-03-09 「网文章节闭环」
### 修复
- 修复“加入书架后未获取网络章节”主链路：入库改为二阶段目录同步（先入库，后异步拉目录）。
- 新增目录同步任务表 web_chapter_sync_tasks 与 web_books 状态字段，统一回写 未拉取 / 已拉取 / 失效。
- 新增目录同步重试策略（指数退避）与同书源候选切换，失败原因会写回书籍状态。
- 阅读页打开网文时，若章节仍不可用，会展示状态化错误信息而非仅提示“未获取到网文章节”。
- 网文页“加入书架”提示改为“已加入书架，正在后台获取目录”，减少误判为立即可读。
- 修复规则提取链路中 null.isNotEmpty 崩溃点，避免目录同步被空值异常打断。

### 验证
- flutter test test/webnovel_repository_test.dart
- flutter analyze lib/features/webnovel/webnovel_repository.dart lib/features/webnovel/models.dart lib/features/webnovel/presentation/webnovel_screen.dart lib/features/reader/presentation/reader_screen.dart test/webnovel_repository_test.dart（仅剩既有 info 级提示）

## [2.3.0] - 2026-03-09 「聚焦与书源」
### 新增
- 新增内置大书源包 assets/webnovel/bundled_sources.json，移动端在无自定义书源时可自动导入首批可用书源。
- 新增真实大书源兼容测试，直接用仓库内 书源.json 校验导入、去重与落库表现。
- 新增《搜书大师 v23.3 APK 逆向对照报告》，沉淀搜书、书源、缓存、阅读器与 TTS 的可借鉴架构（docs/qa/2026-03-09-soushu-apk-benchmark-report.md）。
- 新增《搜书大师全模块借鉴/抄写评估报告》，覆盖网文、文件读取解析、翻页引擎、缓存下载与业务流程（docs/qa/2026-03-09-soushu-full-reference-and-copy-report.md）。
- 新增《全链路重构任务清单（极详细）》用于持续执行和验收（docs/plans/2026-03-09-soushu-reference-implementation-tasklist.md）。
- 新增《项目开发进度书（交接版）》与《下一位开发提示词》（docs/qa/2026-03-09-project-progress-book.md、docs/qa/2026-03-09-handover-prompt.md）。

### 调整
- 桌面端功能范围收敛为书架、同步、设置，并保留书源文件管理、运行日志和版本更新日志入口。
- 桌面端旧的网文、翻译配置和本地 TTS 管理入口改为回落到更轻量的设置页或书源文件页，减少误触和维护面。

### 修复
- 修复大书源导入时 sourceId 冲突导致的书源覆盖问题，只有在真实冲突时才追加稳定后缀。
- 修复手机端“全部书源”搜索在数千条书源下容易卡顿和超时的问题，改为优先搜索高优先级直连书源，再补网页搜索结果。
- 修复手机端网文链路首次进入缺少可用书源的问题，避免必须手动导入后才能开始搜书。
- 修复 EPUB/TXT 阅读目录稀疏问题：章节标题缺失时会自动补全目录项，并对超长无章节 TXT 自动生成分段目录。
- 修复 TXT/EPUB 首次打开卡顿：文本分块改为按需懒加载，分页阅读不再强制等待全量 chunk 生成。
- 修复导入文件选择缺少 cbr 的问题，移动端导入白名单已补齐。
- 修复阅读页、网文页、设置页、TTS/翻译服务的多处中文乱码文案，恢复核心流程可读性（打开书籍、搜书、加入书架、环境检测、目录/书签、错误提示）。

### 验证
- flutter analyze lib/features/webnovel/webnovel_repository.dart lib/features/webnovel/presentation/webnovel_screen.dart test/webnovel_source_pack_compat_test.dart test/webnovel_repository_test.dart test/webnovel_screen_test.dart
- flutter test

## [2.2.0] - 2026-03-08 「阅读恢复与续传」
### 新增
- 新增 TXT / EPUB 真分页阅读链路，阅读器默认模式切换为 paged，并接通目录跳转、书签跳转、进度定位和当前页朗读窗口。
- 新增翻页动画选项，支持 sheet、slide、fade、flip 四种过渡效果。
- 新增自定义字体导入与字体选择面板。
- 新增阅读主题与配色编辑能力，支持预设主题、自定义前景色和背景色。
- 新增 EPUB 备用渲染路径，在正文提取较差时仍可打开并明确显示 EPUB 备用渲染。
- 新增 Legado JSONPath-aware 与受约束 JS-aware 解析闭环，提升导入书源的可用率。
- 新增 llama-server.zip 运行时断点续传测试覆盖，和已有 GGUF / TTS 续传链路一起形成统一恢复策略。

### 修复
- 修复阅读器仍停留在长滚动模式的问题，分页阅读已替代原始 TXT / EPUB 长滚动主路径。
- 修复大批量网文书源下搜索与管理卡顿的问题，现已加入缓存、域名索引、批量 fallback 和更轻量的列表渲染。
- 修复嵌入网页阅读模式滚动和操作不足的问题，补齐刷新、前进后退、上下翻页、回顶部和阅读优化注入。
- 修复翻译模型、TTS 模型和 Windows llama-server.zip 下载“文案显示可续传、实际从 0 开始”的问题，统一切换为单连接断点续传。

