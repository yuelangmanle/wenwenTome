import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../app/runtime_platform.dart';
import '../nsd_discovery.dart';
import '../sync_providers.dart';

class SyncScreen extends ConsumerStatefulWidget {
  const SyncScreen({super.key});

  @override
  ConsumerState<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<SyncScreen> {
  final NsdDiscovery _discovery = NsdDiscovery();
  final TextEditingController _manualCodeController = TextEditingController();

  List<DiscoveredDevice> _devices = const <DiscoveredDevice>[];
  bool _scanning = false;

  bool get _isDesktop =>
      detectLocalRuntimePlatform() == LocalRuntimePlatform.windows;

  bool get _isMobile =>
      detectLocalRuntimePlatform() == LocalRuntimePlatform.android;

  @override
  void dispose() {
    _manualCodeController.dispose();
    _discovery.dispose();
    super.dispose();
  }

  Future<void> _scanNearbyDevices() async {
    setState(() {
      _scanning = true;
      _devices = const <DiscoveredDevice>[];
    });
    final found = await _discovery.scan();
    if (!mounted) {
      return;
    }
    setState(() {
      _devices = found;
      _scanning = false;
    });
  }

  Future<void> _connectToHost({required String host, required int port}) async {
    final ok = await ref
        .read(syncConnectionProvider.notifier)
        .connect(host: host, port: port);
    if (!mounted) {
      return;
    }
    final state = ref.read(syncConnectionProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? '已连接到 ${state.endpoint}' : (state.error ?? '连接失败')),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _connectToDevice(
    BuildContext context,
    DiscoveredDevice device,
  ) async {
    await _connectToHost(host: device.host, port: device.port);
  }

  ({String host, int port})? _parseConnectCode(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      return null;
    }

    final normalized = text.startsWith('wenwentome://')
        ? text
        : 'wenwentome://$text';
    final uri = Uri.tryParse(normalized);
    final host = uri?.host.trim() ?? '';
    final port = uri?.port ?? 0;
    if (host.isEmpty || port <= 0) {
      return null;
    }
    return (host: host, port: port);
  }

  Future<void> _submitManualCode() async {
    final parsed = _parseConnectCode(_manualCodeController.text);
    if (parsed == null) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('连接码无效，请输入 wenwentome://host:port')),
      );
      return;
    }
    await _connectToHost(host: parsed.host, port: parsed.port);
  }

  Future<void> _openQrScanner() async {
    if (!_isMobile) {
      return;
    }

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => const _QrScannerSheet(),
    );
    if (result == null || !mounted) {
      return;
    }

    _manualCodeController.text = result;
    final parsed = _parseConnectCode(result);
    if (parsed == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('二维码内容无效')));
      return;
    }
    await _connectToHost(host: parsed.host, port: parsed.port);
  }

  @override
  Widget build(BuildContext context) {
    final serverState = ref.watch(syncServerStateProvider);
    final connectionState = ref.watch(syncConnectionProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '局域网同步',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (_isDesktop) ...[
            _buildDesktopServiceCard(serverState),
            const SizedBox(height: 24),
            _buildDesktopHostSection(serverState),
            const SizedBox(height: 24),
          ],
          if (_isMobile) ...[
            _buildMobileConnectionCard(connectionState),
            const SizedBox(height: 24),
            _buildMobileConnectSection(connectionState),
            const SizedBox(height: 24),
            if (connectionState.isConnected) ...[
              _buildRemoteLibraryCard(connectionState),
              const SizedBox(height: 24),
            ],
          ],
          _buildNearbyDevicesSection(),
          const SizedBox(height: 24),
          const _SyncInstructionCard(),
        ],
      ),
    );
  }

  Widget _buildDesktopServiceCard(SyncServerState serverState) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
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
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  if (serverState.localIp != null)
                    Text(
                      '${serverState.localIp}:${serverState.port}',
                      style: TextStyle(
                        color: colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  Text(
                    '电脑端负责展示二维码、连接地址并充当同步主机。',
                    style: TextStyle(
                      color: colorScheme.onSurface.withValues(alpha: 0.72),
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: serverState.isRunning,
              onChanged: (_) =>
                  ref.read(syncServerStateProvider.notifier).toggle(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopHostSection(SyncServerState serverState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '手机扫码连接',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),
        const Text('电脑端展示二维码后，手机端文文Tome 直接扫码即可进入连接流程。'),
        const SizedBox(height: 16),
        if (serverState.isRunning && serverState.connectUrl != null)
          Center(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: QrImageView(
                    data: serverState.connectUrl!,
                    version: QrVersions.auto,
                    size: 220,
                    backgroundColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                SelectableText(
                  serverState.connectUrl!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontFamily: 'monospace',
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          )
        else
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('先开启桌面端同步服务，二维码和连接码才会显示。'),
            ),
          ),
      ],
    );
  }

  Widget _buildMobileConnectionCard(SyncConnectionState connectionState) {
    final colorScheme = Theme.of(context).colorScheme;
    final notifier = ref.read(syncConnectionProvider.notifier);

    IconData leadingIcon;
    Color leadingColor;
    String title;
    String subtitle;

    switch (connectionState.status) {
      case SyncConnectionStatus.connected:
        leadingIcon = Icons.cloud_done_outlined;
        leadingColor = Colors.green;
        title = '已连接到桌面端';
        subtitle = connectionState.endpoint;
      case SyncConnectionStatus.connecting:
        leadingIcon = Icons.sync;
        leadingColor = colorScheme.primary;
        title = '正在连接桌面端';
        subtitle = connectionState.endpoint.isEmpty
            ? '正在验证连接'
            : connectionState.endpoint;
      case SyncConnectionStatus.failed:
        leadingIcon = Icons.error_outline;
        leadingColor = Colors.orange;
        title = '连接失败';
        subtitle = connectionState.error ?? '请重新扫码或手动输入连接码';
      case SyncConnectionStatus.disconnected:
        leadingIcon = Icons.qr_code_scanner;
        leadingColor = colorScheme.primary;
        title = '尚未连接桌面端';
        subtitle = '手机端只负责扫码、手输连接码和发现附近主机';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                Icon(leadingIcon, color: leadingColor, size: 32),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: colorScheme.onSurface.withValues(alpha: 0.68),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: connectionState.isConnecting
                      ? null
                      : _openQrScanner,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('扫码连接'),
                ),
                OutlinedButton.icon(
                  onPressed: connectionState.isConnecting
                      ? null
                      : _scanNearbyDevices,
                  icon: const Icon(Icons.search),
                  label: const Text('发现主机'),
                ),
                if (connectionState.isConnected)
                  OutlinedButton.icon(
                    onPressed: notifier.refreshRemoteBooks,
                    icon: const Icon(Icons.refresh),
                    label: const Text('刷新远端书架'),
                  ),
                if (connectionState.isConnected)
                  OutlinedButton.icon(
                    onPressed: notifier.disconnect,
                    icon: const Icon(Icons.link_off),
                    label: const Text('断开连接'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileConnectSection(SyncConnectionState connectionState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '扫码或手动连接',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),
        const Text('手机端不再展示主机二维码，只负责扫描电脑端二维码或手动输入连接码。'),
        const SizedBox(height: 16),
        TextField(
          controller: _manualCodeController,
          enabled: !connectionState.isConnecting,
          decoration: const InputDecoration(
            labelText: '连接码',
            hintText: 'wenwentome://192.168.1.10:7755',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _submitManualCode(),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.tonal(
            onPressed: connectionState.isConnecting ? null : _submitManualCode,
            child: const Text('手动连接'),
          ),
        ),
      ],
    );
  }

  Widget _buildRemoteLibraryCard(SyncConnectionState connectionState) {
    final books = connectionState.remoteBooks;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('远端书架', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('${connectionState.endpoint} 共 ${books.length} 本书'),
            const SizedBox(height: 12),
            if (books.isEmpty)
              const Text('已连接，但暂未拉取到远端书架条目。')
            else
              for (final book in books.take(6))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.menu_book_outlined),
                  title: Text(book['title'] as String? ?? '未命名书籍'),
                  subtitle: Text(book['author'] as String? ?? ''),
                  trailing: Text(
                    '${(((book['progress'] as num?) ?? 0) * 100).toStringAsFixed(0)}%',
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _buildNearbyDevicesSection() {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '附近的文文Tome设备',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const Spacer(),
            IconButton(
              icon: _scanning
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              tooltip: '扫描局域网',
              onPressed: _scanning ? null : _scanNearbyDevices,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          _isDesktop
              ? '电脑端可刷新查看同一 Wi‑Fi 下的其他文文Tome 设备。'
              : '与电脑连接同一 Wi‑Fi 后，点击刷新自动搜索附近主机。',
          style: TextStyle(
            color: colorScheme.onSurface.withValues(alpha: 0.65),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 12),
        if (_devices.isEmpty && !_scanning)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24),
            decoration: BoxDecoration(
              border: Border.all(color: colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Column(
              children: [
                Icon(Icons.devices_other, size: 40, color: Colors.grey),
                SizedBox(height: 8),
                Text(
                  '暂未发现附近设备\n点击右上角刷新开始扫描',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ],
            ),
          )
        else
          ..._devices.map(
            (device) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  child: Icon(
                    _isDesktop ? Icons.phone_android : Icons.computer,
                  ),
                ),
                title: Text(device.name),
                subtitle: Text('${device.host}:${device.port}'),
                trailing: FilledButton.tonal(
                  onPressed: () => _connectToDevice(context, device),
                  child: const Text('连接'),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _QrScannerSheet extends StatefulWidget {
  const _QrScannerSheet();

  @override
  State<_QrScannerSheet> createState() => _QrScannerSheetState();
}

class _QrScannerSheetState extends State<_QrScannerSheet> {
  bool _handled = false;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.72,
        child: Column(
          children: [
            const ListTile(
              title: Text('扫描电脑端二维码'),
              subtitle: Text('识别 wenwentome://host:port 后会自动返回'),
            ),
            const Divider(height: 1),
            Expanded(
              child: MobileScanner(
                onDetect: (capture) {
                  if (_handled) {
                    return;
                  }
                  final code = capture.barcodes.first.rawValue?.trim() ?? '';
                  if (!code.startsWith('wenwentome://')) {
                    return;
                  }
                  _handled = true;
                  Navigator.of(context).pop(code);
                },
              ),
            ),
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
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, size: 18),
                SizedBox(width: 8),
                Text('同步说明', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            SizedBox(height: 12),
            _InfoRow(icon: Icons.sync, text: '阅读进度与书签：自动实时双向同步'),
            _InfoRow(icon: Icons.download, text: '书籍文件：按需手动拉取，不走外部服务器'),
            _InfoRow(icon: Icons.lan, text: '所有传输都限定在本地局域网内完成'),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}
