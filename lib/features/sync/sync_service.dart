import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:multicast_dns/multicast_dns.dart';
import '../library/data/library_service.dart';

/// 文文Tome 同步服务（PC 端为服务器，移动端为客户端）
class SyncServer {
  static const int _port = 7755;
  static const String _serviceType = '_wenwentome._tcp';
  static const String _serviceName = 'WenwenTome';

  HttpServer? _server;
  MDnsClient? _mdns;
  final LibraryService _libraryService;

  SyncServer(this._libraryService);

  /// 获取当前设备 IP（局域网）
  Future<String?> getLocalIp() async {
    try {
      for (var interface in await NetworkInterface.list()) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// 启动 HTTP 服务器（提供阅读进度同步 + 书籍文件传输）
  Future<void> startServer() async {
    if (_server != null) return; // 已在运行

    final router = Router()
      ..get('/ping', _handlePing)
      ..get('/books', _handleGetBooks)
      ..get('/books/<id>/progress', _handleGetProgress)
      ..post('/books/<id>/progress', _handlePostProgress)
      ..get('/books/<id>/file', _handleGetFile);

    final handler = const Pipeline()
        .addMiddleware(logRequests())
        .addMiddleware(_corsMiddleware())
        .addHandler(router.call);

    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, _port);
    debugPrint('[同步] 文文Tome 服务启动: http://${_server!.address.host}:${_server!.port}');

    await _startMdnsBroadcast();
  }

  /// 停止服务
  Future<void> stopServer() async {
    await _server?.close(force: true);
    _server = null;
    _mdns?.stop();
    _mdns = null;
    debugPrint('[同步] 文文Tome 服务已停止');
  }

  bool get isRunning => _server != null;

  // ─── API 处理器 ───

  Response _handlePing(Request request) {
    return Response.ok(jsonEncode({
      'status': 'ok',
      'device': Platform.localHostname,
      'version': '0.1.0',
    }), headers: {'content-type': 'application/json'});
  }

  Future<Response> _handleGetBooks(Request request) async {
    final books = await _libraryService.loadBooks();
    final json = books.map((b) => {
      'id': b.id,
      'title': b.title,
      'author': b.author,
      'format': b.format.name,
      'progress': b.readingProgress,
    }).toList();
    return Response.ok(jsonEncode(json), headers: {'content-type': 'application/json'});
  }

  Future<Response> _handleGetProgress(Request request, String id) async {
    final books = await _libraryService.loadBooks();
    final book = books.firstWhere((b) => b.id == id, orElse: () => throw Exception('not found'));
    return Response.ok(jsonEncode({
      'id': book.id,
      'position': book.lastPosition,
      'progress': book.readingProgress,
    }), headers: {'content-type': 'application/json'});
  }

  Future<Response> _handlePostProgress(Request request, String id) async {
    final body = await request.readAsString();
    final data = jsonDecode(body) as Map<String, dynamic>;
    await _libraryService.updateProgress(
      id,
      data['position'] as int,
      (data['progress'] as num).toDouble(),
    );
    return Response.ok(jsonEncode({'status': 'updated'}),
        headers: {'content-type': 'application/json'});
  }

  Future<Response> _handleGetFile(Request request, String id) async {
    final books = await _libraryService.loadBooks();
    try {
      final book = books.firstWhere((b) => b.id == id);
      final file = File(book.filePath);
      if (!await file.exists()) {
        return Response.notFound('文件不存在');
      }
      final bytes = await file.readAsBytes();
      return Response.ok(bytes, headers: {
        'content-type': 'application/octet-stream',
        'content-disposition': 'attachment; filename="${file.uri.pathSegments.last}"',
        'content-length': bytes.length.toString(),
      });
    } catch (_) {
      return Response.notFound('Book not found');
    }
  }

  // ─── mDNS 广播 ───

  Future<void> _startMdnsBroadcast() async {
    // multicast_dns 在 Windows 上支持有限，仅用于发现
    // 完整 mDNS 广播在 Android 端通过 NSD API 实现
    debugPrint('[同步] mDNS 广播已标记: service=$_serviceName type=$_serviceType（移动端通过 NSD 发现）');
  }

  // ─── CORS 中间件 ───

  Middleware _corsMiddleware() {
    return (Handler handler) {
      return (Request request) async {
        if (request.method == 'OPTIONS') {
          return Response.ok('', headers: _corsHeaders);
        }
        final response = await handler(request);
        return response.change(headers: _corsHeaders);
      };
    };
  }

  static const _corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
  };
}

/// 同步客户端（移动端连接到 PC 端服务器）
class SyncClient {
  final String serverIp;
  final int port;
  final _client = HttpClient();

  SyncClient({required this.serverIp, this.port = 7755});

  String get baseUrl => 'http://$serverIp:$port';

  /// 检测服务器是否在线
  Future<bool> ping() async {
    try {
      final req = await _client.getUrl(Uri.parse('$baseUrl/ping'));
      final resp = await req.close().timeout(const Duration(seconds: 3));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// 获取服务器书目列表
  Future<List<Map<String, dynamic>>> getBooks() async {
    final req = await _client.getUrl(Uri.parse('$baseUrl/books'));
    final resp = await req.close();
    final body = await resp.transform(utf8.decoder).join();
    return List<Map<String, dynamic>>.from(jsonDecode(body));
  }

  /// 推送本地进度到服务器
  Future<void> pushProgress(String bookId, int position, double progress) async {
    final req = await _client.postUrl(Uri.parse('$baseUrl/books/$bookId/progress'));
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode({'position': position, 'progress': progress}));
    await req.close();
  }

  /// 拉取服务器进度
  Future<Map<String, dynamic>?> getProgress(String bookId) async {
    try {
      final req = await _client.getUrl(Uri.parse('$baseUrl/books/$bookId/progress'));
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      return Map<String, dynamic>.from(jsonDecode(body));
    } catch (_) {
      return null;
    }
  }

  void dispose() => _client.close();
}
