import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'sync_service.dart';
import '../library/data/library_service.dart';

// ─── 服务实例 ───
final syncServerProvider = Provider<SyncServer>((ref) {
  final libService = ref.read(libraryServiceProvider);
  final server = SyncServer(libService);
  ref.onDispose(() => server.stopServer());
  return server;
});

// 需要从 library_providers 导入
final libraryServiceProvider = Provider<LibraryService>((ref) => LibraryService());

// ─── 服务器运行状态 ───
final syncServerStateProvider = StateNotifierProvider<SyncServerNotifier, SyncServerState>(
  (ref) => SyncServerNotifier(ref.read(syncServerProvider)),
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

  SyncServerState copyWith({bool? isRunning, String? localIp}) => SyncServerState(
    isRunning: isRunning ?? this.isRunning,
    localIp: localIp ?? this.localIp,
    port: port,
  );

  String? get connectUrl => localIp != null ? 'wenwentome://$localIp:$port' : null;
}

class SyncServerNotifier extends StateNotifier<SyncServerState> {
  final SyncServer _server;

  SyncServerNotifier(this._server) : super(const SyncServerState());

  Future<void> start() async {
    await _server.startServer();
    final ip = await _server.getLocalIp();
    state = state.copyWith(isRunning: true, localIp: ip);
  }

  Future<void> stop() async {
    await _server.stopServer();
    state = state.copyWith(isRunning: false);
  }

  Future<void> toggle() => state.isRunning ? stop() : start();
}
