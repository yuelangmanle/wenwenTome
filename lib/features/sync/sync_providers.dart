import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/providers/library_providers.dart' as lib_providers;
import 'sync_service.dart';

// ─── 服务实例 ───
final syncServerProvider = Provider<SyncServer>((ref) {
  final libService = ref.read(lib_providers.libraryServiceProvider);
  final server = SyncServer(libService);
  ref.onDispose(() => server.stopServer());
  return server;
});

// ─── 服务器运行状态 ───
final syncServerStateProvider =
    NotifierProvider<SyncServerNotifier, SyncServerState>(
      SyncServerNotifier.new,
    );

class SyncServerState {
  final bool isRunning;
  final String? localIp;
  final int port;

  const SyncServerState({
    this.isRunning = false,
    this.localIp,
    this.port = 7755,
  });

  SyncServerState copyWith({bool? isRunning, String? localIp}) =>
      SyncServerState(
        isRunning: isRunning ?? this.isRunning,
        localIp: localIp ?? this.localIp,
        port: port,
      );

  String? get connectUrl =>
      localIp != null ? 'wenwentome://$localIp:$port' : null;
}

class SyncServerNotifier extends Notifier<SyncServerState> {
  @override
  SyncServerState build() => const SyncServerState();

  Future<void> start() async {
    final server = ref.read(syncServerProvider);
    await server.startServer();
    final ip = await server.getLocalIp();
    state = state.copyWith(isRunning: true, localIp: ip);
  }

  Future<void> stop() async {
    await ref.read(syncServerProvider).stopServer();
    state = state.copyWith(isRunning: false);
  }

  Future<void> toggle() => state.isRunning ? stop() : start();
}

enum SyncConnectionStatus { disconnected, connecting, connected, failed }

class SyncConnectionState {
  const SyncConnectionState({
    this.status = SyncConnectionStatus.disconnected,
    this.host = '',
    this.port = 7755,
    this.remoteBooks = const <Map<String, dynamic>>[],
    this.error,
    this.connectedAt,
  });

  final SyncConnectionStatus status;
  final String host;
  final int port;
  final List<Map<String, dynamic>> remoteBooks;
  final String? error;
  final DateTime? connectedAt;

  bool get isConnecting => status == SyncConnectionStatus.connecting;
  bool get isConnected => status == SyncConnectionStatus.connected;
  String get endpoint => host.trim().isEmpty ? '' : '$host:$port';

  SyncConnectionState copyWith({
    SyncConnectionStatus? status,
    String? host,
    int? port,
    List<Map<String, dynamic>>? remoteBooks,
    Object? error = _syncConnectionSentinel,
    Object? connectedAt = _syncConnectionSentinel,
  }) {
    return SyncConnectionState(
      status: status ?? this.status,
      host: host ?? this.host,
      port: port ?? this.port,
      remoteBooks: remoteBooks ?? this.remoteBooks,
      error: identical(error, _syncConnectionSentinel)
          ? this.error
          : error as String?,
      connectedAt: identical(connectedAt, _syncConnectionSentinel)
          ? this.connectedAt
          : connectedAt as DateTime?,
    );
  }
}

const Object _syncConnectionSentinel = Object();

final syncConnectionProvider =
    NotifierProvider<SyncConnectionNotifier, SyncConnectionState>(
      SyncConnectionNotifier.new,
    );

class SyncConnectionNotifier extends Notifier<SyncConnectionState> {
  SyncClient? _client;

  @override
  SyncConnectionState build() {
    ref.onDispose(() {
      _client?.dispose();
      _client = null;
    });
    return const SyncConnectionState();
  }

  Future<bool> connect({
    required String host,
    required int port,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final trimmedHost = host.trim();
    if (trimmedHost.isEmpty || port <= 0) {
      state = const SyncConnectionState(
        status: SyncConnectionStatus.failed,
        error: '连接地址无效',
      );
      return false;
    }

    state = SyncConnectionState(
      status: SyncConnectionStatus.connecting,
      host: trimmedHost,
      port: port,
    );

    final candidate = SyncClient(serverIp: trimmedHost, port: port);
    try {
      final ok = await candidate.ping().timeout(timeout);
      if (!ok) {
        candidate.dispose();
        state = SyncConnectionState(
          status: SyncConnectionStatus.failed,
          host: trimmedHost,
          port: port,
          error: '未能连接到主机，请确认电脑端同步服务已开启',
        );
        return false;
      }

      List<Map<String, dynamic>> remoteBooks = const <Map<String, dynamic>>[];
      try {
        remoteBooks = await candidate.getBooks().timeout(
          const Duration(seconds: 5),
        );
      } catch (_) {
        remoteBooks = const <Map<String, dynamic>>[];
      }

      _client?.dispose();
      _client = candidate;
      state = SyncConnectionState(
        status: SyncConnectionStatus.connected,
        host: trimmedHost,
        port: port,
        remoteBooks: remoteBooks,
        connectedAt: DateTime.now(),
      );
      return true;
    } catch (error) {
      candidate.dispose();
      state = SyncConnectionState(
        status: SyncConnectionStatus.failed,
        host: trimmedHost,
        port: port,
        error: error.toString(),
      );
      return false;
    }
  }

  Future<void> refreshRemoteBooks() async {
    final client = _client;
    if (client == null || !state.isConnected) {
      return;
    }

    state = state.copyWith(
      status: SyncConnectionStatus.connecting,
      error: null,
    );
    try {
      final ok = await client.ping().timeout(const Duration(seconds: 3));
      if (!ok) {
        state = state.copyWith(
          status: SyncConnectionStatus.failed,
          remoteBooks: const <Map<String, dynamic>>[],
          error: '连接已断开，请重新扫码或手动连接',
        );
        return;
      }

      final remoteBooks = await client.getBooks().timeout(
        const Duration(seconds: 5),
      );
      state = state.copyWith(
        status: SyncConnectionStatus.connected,
        remoteBooks: remoteBooks,
        error: null,
        connectedAt: DateTime.now(),
      );
    } catch (error) {
      state = state.copyWith(
        status: SyncConnectionStatus.failed,
        remoteBooks: const <Map<String, dynamic>>[],
        error: error.toString(),
      );
    }
  }

  void disconnect() {
    _client?.dispose();
    _client = null;
    state = const SyncConnectionState();
  }
}
