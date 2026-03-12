# 2026-03-09 搜书大师全模块借鉴/抄写评估报告

## 0. 你这次要的结论（先说人话）
- 你要的不是“只看网文”，而是全链路：`文件导入 -> 解析 -> 阅读翻页 -> 缓存下载 -> TTS -> 业务流程`，这份报告覆盖了。
- **可以抄的层**：配置结构、协议、流程、状态机、数据模型。
- **不建议直接抄的层**：APK 反编译后的专有实现代码（法律风险 + 技术维护灾难）。
- **最优路线**：按搜书大师架构“对齐设计 + 自己实现”，并兼容它的书源与配置格式。

---

## 1. 分析范围与证据来源

### 1.1 样本
- APK：`e:\Antigavity program\book\wenwen_tome\tmp\apk_analysis\soushu\soushu.apk`
- 包名：`com.flyersoft.seekbooks`
- 版本：`v23.3`（`versionCode=230300`）

### 1.2 使用手段
- `apkanalyzer manifest print`
- `apkanalyzer files list`
- `apkanalyzer files cat --file ...`
- `apkanalyzer dex packages`
- `aapt dump badging`

### 1.3 已知限制
- 类名存在大量混淆（`com.lygame.aaa.*`），只能做“结构级/行为级”逆向。
- 本报告结论可指导工程实现与兼容，不建议当作“可直接复制源码”的依据。

---

## 2. 搜书大师整体架构（从 APK 证据还原）

### 2.1 主要业务 Activity / Service
- 阅读主界面：`com.flyersoft.seekbooks.ActivityTxt`
- 网文链路：
  - `com.flyersoft.WB.WebSearchAct`
  - `com.flyersoft.WB.WebBookDetailAct`
  - `com.flyersoft.WB.WebCacheAct`
  - `com.flyersoft.WB.BrowserAct`
- 下载服务：
  - `com.flyersoft.seekbooks.BookDownloadService`
  - `com.flyersoft.seekbooks.ChapterDownloadService`
- 朗读服务：
  - `com.flyersoft.source.service.HttpReadAloudService`
  - 基类：`com.flyersoft.source.service.BaseReadAloudService`

### 2.2 内部“服务化”能力
- 发现 `com.flyersoft.source.service.web.WebService` 与 `ServiceControll`，存在本地 HTTP/WebSocket 服务能力。
- `ServiceControll` 暴露的方法名包含：
  - `addShelf`, `shelfBook`, `getChapterList`, `getEBookSource`, `getEBookChapterText`, `netSource`, `enableBookSource`, `saveFile` 等。
- 这说明它的业务已经不是单纯 UI 逻辑，而是“服务层 + UI 层”。

---

## 3. 文件导入与格式支持（你最关心的之一）

### 3.1 Manifest 提取出的扩展名支持
- `epub`, `azw3`, `mobi`, `txt`, `fb2`, `fb2.zip`, `docx`, `odt`, `md`, `rtf`, `chm`, `cbz`, `cbr`, `wbpub`

### 3.2 Manifest 提取出的 MIME 支持
- `application/epub+zip`
- `application/x-mobipocket-ebook`
- `application/x-fictionbook`
- `application/x-cbr`
- `application/x-cbz`
- `application/vnd.openxmlformats-officedocument.wordprocessingml.document`
- `text/*`, `text/plain`, `image/*`
- 以及若干 `application/azw3/docx/odt/rtf/fb2/octet-stream`

### 3.3 打开来源协议
- `file://`, `content://`, `http://`, `https://`, `epub://` 等意图路径都存在。

### 3.4 解析引擎线索
- PDF 相关：`com.radaee.pdf.Page`（商用阅读引擎线索）
- MOBI 相关：`com.dozof.app.mobi.MobiDecoder`
- EPUB 相关：`com.flyersoft.source.service.web.utils.EPubWeb`
- 结论：它不是靠单一 WebView/纯文本读取，而是多引擎混合。

---

## 4. 阅读渲染与翻页实现（重点）

### 4.1 核心阅读类体量
- `ActivityTxt` 体量极大（`1008` 个方法条目），阅读交互、翻页、缓存、下载回调等大量逻辑耦合在此。

### 4.2 自研分页渲染引擎证据
- 明确存在 `com.flyersoft.staticlayout.MRTextView`、`com.flyersoft.staticlayout.l`、`com.flyersoft.staticlayout.f`。
- `MRTextView` 方法与字段中出现：
  - `getPageBreakLine`, `getCurPosition`, `getRealLineCount`, `setTextSize`, `onDraw` 等。
- 其他字段名出现：
  - `nofpages`, `lineppage`, `pagebb`, `softpage`, `frmtxt...`, `txtbrl...`
- 结论：这是“预计算分页 + 自绘渲染 + 手势驱动”的重型阅读引擎，不是普通 `TextView` 滚动翻页。

### 4.3 对你项目的含义
- 你可以借鉴它的思路，但**不应该试图原样搬它的引擎代码**。
- 正确做法：在你当前分页基础上扩展成“布局缓存 + 章节页索引 + 动画器分层”。

---

## 5. 网文书源与搜书逻辑（不止网文）

### 5.1 资产文件结构
- 书源核心：
  - `assets/default_source.json`
  - `assets/free_source.json`
  - `assets/cnweb/*.wj / *.wj2 / *.sub`
- 采集扩展：
  - `assets/auto_collect.json`
- 朗读配置：
  - `assets/httpTTS.json`
- 数据迁移：
  - `assets/sql/2.sql` ~ `assets/sql/5.sql`

### 5.2 规则引擎能力证据
- `default_source.json` 字段直接包含：
  - `ruleSearchUrl`, `ruleSearchList`, `ruleChapterList`, `ruleBookContent`, `ruleContentUrlNext` 等。
- `free_source.json` 出现 JSONPath + JS 风格表达：
  - 例如 `$.data.list`、`@js:java.put(...)`、`java.get(...)`。
- `org/mozilla/javascript/*` 资源存在，说明 JS 规则执行能力概率很高。

### 5.3 数据库规则字段演进（SQL）
- `assets/sql/2.sql` 出现多条 `BOOK_SOURCE` 新字段：
  - `RULE_*`、`RULE_BOOK_CONTENT_WEB_JS`、`IS_VIP` 等。
- 说明它书源模型是持续扩展的，不是固定死字段。

---

## 6. 缓存下载与离线链路

### 6.1 服务拆分证据
- `BookDownloadService`（书级任务）
- `ChapterDownloadService`（章节级任务，含通知更新、任务推进）
- `WebCacheAct`（缓存管理 UI）

### 6.2 流程推断
- 搜索/详情 -> 加书架 -> 目录/章节下载 -> 缓存可管理 -> 阅读端消费缓存。
- 这是你当前“加入书架后看不了、未获取章节”问题的直接对照解法。

---

## 7. TTS 业务逻辑

### 7.1 服务层
- `BaseReadAloudService`：会话控制、焦点管理、播放状态、计时、通知。
- `HttpReadAloudService`：下载音频、MediaPlayer 播放、上一段/下一段、速率调整。

### 7.2 配置层
- `assets/httpTTS.json` 明确是“多声线 + HTTP 模板”的策略配置。
- URL 模板里支持变量与表达式（如 `speakText`, `speakSpeed` 等）。

### 7.3 对你项目的建议
- 朗读要做“服务化 + 引擎适配层”，不要在阅读页面直接串所有状态。

---

## 8. “借鉴”与“直接抄”可行性评估

## 8.1 可以直接借鉴（建议做）
- 业务流程：
  - 搜索 -> 详情 -> 加书架 -> 拉目录 -> 章节缓存 -> 阅读
- 数据模型：
  - 书源规则字段、章节缓存结构、下载任务状态机
- 配置思路：
  - 书源 JSON、HTTP TTS 模板、自动采集规则
- 阅读交互：
  - 点击区域策略、分页模式与滚动模式并存、翻页动画配置化

## 8.2 可以“抄结构，但自己写实现”
- 解析执行器（规则解释、JSONPath/JS扩展）
- 文件解析管线（多格式适配器 + 统一章节索引）
- 分页渲染器（分页缓存、章节跳转、进度映射）
- 下载调度器（书级/章节级并发与重试）

## 8.3 不建议直接抄（高风险）
- 反编译得到的专有 Java/Kotlin/Smali 代码
- 商业/闭源依赖的具体实现（例如 PDF 引擎、加密/风控 SDK）
- 品牌资源、站点内置数据的原样打包分发

## 8.4 直接抄的现实阻力（技术角度）
- 大量混淆类（`com.lygame.aaa.*`），可读性很差。
- 体量巨大且耦合高（阅读主类超大），直接迁移维护成本极高。
- 三方依赖组合复杂，迁移后稳定性通常更差。

---

## 9. 面向你项目（wenwen_tome）的落地路线

## 阶段 1：先把体验拉齐（优先）
1. 统一“加书架后二阶段拉目录”流程，确保不会出现“未获取网络章节”。
2. 文件解析走后台任务，首屏可读优先，长任务延迟处理（目录/全文索引异步补齐）。
3. 阅读交互固定两种模式：
   - 中间菜单 + 左右翻页
   - 全屏菜单

## 阶段 2：补齐能力面
1. 书源规则执行器升级为“JSONPath + JS 可扩展”。
2. 下载服务拆分书级/章节级，落库状态可恢复。
3. TTS 采用服务化 + 引擎切换面板 + 失败降级。

## 阶段 3：做质量和性能
1. 构建章节索引缓存与分页缓存，避免重复解析。
2. 建立稳定性回归集（超大 TXT、异常 EPUB、弱网网文、TTS 连续朗读）。
3. 监控崩溃点：阅读跳转、进度条拖动、离线 TTS 初始化。

---

## 10. 对“要不要直接抄”的最终建议
- 如果你目标是“最快稳定上线”，建议：
  - **抄架构、抄流程、抄配置思想**；
  - **不抄专有代码实现**。
- 如果你坚持“全量直接抄代码”：
  - 法律风险、维护风险、版本升级风险都非常高；
  - 从工程投入看，通常比“重写对齐实现”更慢。

---

## 附录 A：本次报告用到的关键 APK 证据点
- Manifest：
  - 多格式 MIME / pathPattern
  - `ActivityTxt`, `WebSearchAct`, `WebBookDetailAct`, `WebCacheAct`, `BrowserAct`
  - `BookDownloadService`, `ChapterDownloadService`, `HttpReadAloudService`
  - `ssds://booksource` / `yuedu://booksource`
- Assets：
  - `default_source.json`, `free_source.json`, `auto_collect.json`, `httpTTS.json`
  - `assets/cnweb/*.wj/*.wj2/*.sub`
  - `assets/sql/2.sql..5.sql`
- DEX：
  - `com.flyersoft.staticlayout.MRTextView`
  - `com.flyersoft.source.service.web.ServiceControll`
  - `com.flyersoft.source.service.BaseReadAloudService`
  - `com.flyersoft.source.service.HttpReadAloudService`
  - `com.flyersoft.seekbooks.BookDownloadService`
  - `com.flyersoft.seekbooks.ChapterDownloadService`
  - `com.dozof.app.mobi.MobiDecoder`
  - `com.radaee.pdf.Page`

