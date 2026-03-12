# 2026-03-11 Release Verification

Target release: `2.6.11+38`（以 `pubspec.yaml` 为准）

## Scope（本轮关注）

- QAT：大样本/异常样本/弱网回归集落地；关键路径运行日志标准化（action/result/error_code）；关键路径超时/取消策略收敛
- REL：出包脚本稳定化、发布前检查清单、release notes、回滚方案

## Release Gating（一键）

- `powershell -ExecutionPolicy Bypass -File scripts/release_check.ps1 -SkipWindows`
  - 如果本机已安装 Inno Setup，再去掉 `-SkipWindows`

## Manual Checks（核心路径）

- 阅读：打开 TXT/EPUB/PDF；目录跳转、拖动进度条；书签创建/跳转
- 网文：搜书→加入书架→打开章节；目录定位当前章节；后台缓存后续章节；缓存管理页暂停/继续/清理
- TTS：阅读页打开 TTS 面板，切换引擎后开始朗读；暂停/继续/停止
- 运行日志：设置页导出/分享运行日志，确认包含 `RUN_EVENT` 结构化事件行

## QAT 回归集（生成型样本，不提交大文件）

### 超大 TXT（30/50/100MB）

- 生成：`powershell -ExecutionPolicy Bypass -File tools/qa/generate_large_txt.ps1`
- 导入并打开：验证首屏可读、目录可延迟生成、拖动进度条可跳转

### 异常 EPUB（恢复/失败可解释）

- 生成：`powershell -ExecutionPolicy Bypass -File tools/qa/generate_epub_samples.ps1`
- 验证：
  - `raw_html.epub` 能被恢复并可读（备用通道）
  - `truncated_zip.epub` 报错可解释（不崩溃）

### 弱网/高延迟（自动化回归）

- `flutter test test/qa/webnovel_weak_network_test.dart`

## Outputs

- Android APK：`releases/<version>/wenwen_tome_android_<version>.apk`
- Windows installer：`releases/<version>/wenwen_tome_windows_<version>_setup.exe`
- Release notes：`releases/<version>/release_notes.md`
