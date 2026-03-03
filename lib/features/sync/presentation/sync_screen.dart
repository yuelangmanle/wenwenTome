import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../sync_providers.dart';

/// 同步管理界面 - 展示 QR 码 + 开关服务
class SyncScreen extends ConsumerWidget {
  const SyncScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serverState = ref.watch(syncServerStateProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('局域网同步', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 服务状态卡片 ──
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Icon(
                      serverState.isRunning ? Icons.wifi : Icons.wifi_off,
                      color: serverState.isRunning ? Colors.green : Colors.grey,
                      size: 32,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            serverState.isRunning ? '同步服务运行中' : '同步服务已关闭',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          if (serverState.localIp != null)
                            Text(
                              '${serverState.localIp}:${serverState.port}',
                              style: TextStyle(color: colorScheme.onSurface.withValues(alpha: 0.6)),
                            ),
                        ],
                      ),
                    ),
                    Switch(
                      value: serverState.isRunning,
                      onChanged: (_) => ref.read(syncServerStateProvider.notifier).toggle(),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // ── QR 码配对 ──
            if (serverState.isRunning && serverState.connectUrl != null) ...[
              const Text('手机扫码连接', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              const Text('打开手机端文文Tome，扫描下方二维码即可配对',
                  style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 16),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8)],
                  ),
                  child: QrImageView(
                    data: serverState.connectUrl!,
                    version: QrVersions.auto,
                    size: 200,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: SelectableText(
                  serverState.connectUrl!,
                  style: TextStyle(
                    color: colorScheme.primary,
                    fontFamily: 'monospace',
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],

            // ── 同步说明 ──
            const _SyncInstructionCard(),
          ],
        ),
      ),
    );
  }
}

class _SyncInstructionCard extends StatelessWidget {
  const _SyncInstructionCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Row(children: [
              Icon(Icons.info_outline, size: 18),
              SizedBox(width: 8),
              Text('同步说明', style: TextStyle(fontWeight: FontWeight.bold)),
            ]),
            SizedBox(height: 12),
            _InfoRow(icon: Icons.sync, text: '阅读进度与书签：自动实时双向同步'),
            _InfoRow(icon: Icons.download, text: '书籍文件：手动触发，按需传输'),
            _InfoRow(icon: Icons.lan, text: '数据不经过任何外部服务器，完全本地'),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Icon(icon, size: 16, color: Colors.grey),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
      ]),
    );
  }
}
