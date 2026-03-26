import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../../../core/storage/app_storage_paths.dart';

class FoliateHostRuntimeSession {
  FoliateHostRuntimeSession({
    required this.rootDirectory,
    required this.entryFile,
    required this.assetKeys,
    required this.entryUrl,
    required Future<String> Function(String filePath) registerBookFileUrl,
  }) : _registerBookFileUrl = registerBookFileUrl;

  final Directory rootDirectory;
  final File entryFile;
  final List<String> assetKeys;
  final String entryUrl;
  final Future<String> Function(String filePath) _registerBookFileUrl;

  Uri get entryUri => Uri.parse(entryUrl);

  Future<String> registerBookFileUrl(String filePath) {
    return _registerBookFileUrl(filePath);
  }
}

class FoliateHostRuntime {
  static const String assetPrefix = 'assets/reader/foliate/';
  static const String _entryAsset = '${assetPrefix}reader.html';

  static _FoliateHostServer? _server;

  static Future<FoliateHostRuntimeSession> ensureReady() async {
    final supportDir = await getSafeApplicationSupportDirectory();
    final runtimeDir = Directory(
      p.join(supportDir.path, 'reader_engines', 'foliate_host'),
    );
    await runtimeDir.create(recursive: true);

    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assetKeys =
        manifest
            .listAssets()
            .where((key) => key.startsWith(assetPrefix))
            .toList(growable: false)
          ..sort();

    for (final assetKey in assetKeys) {
      final relativePath = assetKey.substring(assetPrefix.length);
      final targetFile = File(p.join(runtimeDir.path, relativePath));
      await targetFile.parent.create(recursive: true);
      await _copyAssetIfNeeded(assetKey, targetFile);
    }

    final server = await _ensureServer(runtimeDir);
    return FoliateHostRuntimeSession(
      rootDirectory: runtimeDir,
      entryFile: File(p.join(runtimeDir.path, 'reader.html')),
      assetKeys: assetKeys,
      entryUrl: server.entryUrl,
      registerBookFileUrl: server.registerBookFileUrl,
    );
  }

  static Future<_FoliateHostServer> _ensureServer(Directory runtimeDir) async {
    final existing = _server;
    if (existing != null && existing.rootDirectory.path == runtimeDir.path) {
      return existing;
    }
    if (existing != null) {
      await existing.dispose();
    }
    final server = await _FoliateHostServer.start(runtimeDir);
    _server = server;
    return server;
  }

  static Future<void> _copyAssetIfNeeded(
    String assetKey,
    File targetFile,
  ) async {
    final data = await rootBundle.load(assetKey);
    final bytes = Uint8List.sublistView(data);
    if (await targetFile.exists()) {
      final existing = await targetFile.readAsBytes();
      if (_bytesEqual(existing, bytes)) {
        return;
      }
    }
    await targetFile.writeAsBytes(bytes, flush: true);
  }

  static bool _bytesEqual(Uint8List left, Uint8List right) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) {
        return false;
      }
    }
    return true;
  }

  static String assetKeyForRelativePath(String relativePath) {
    final normalized = relativePath.replaceAll('\\', '/');
    return '$assetPrefix$normalized';
  }

  static bool containsRequiredEntry(Iterable<String> assetKeys) {
    return assetKeys.contains(_entryAsset);
  }
}

class _FoliateHostServer {
  _FoliateHostServer._({
    required this.rootDirectory,
    required this.server,
  });

  final Directory rootDirectory;
  final HttpServer server;
  final Map<String, File> _registeredBooks = <String, File>{};

  String get entryUrl => 'http://127.0.0.1:${server.port}/reader.html';

  static Future<_FoliateHostServer> start(Directory rootDirectory) async {
    late final _FoliateHostServer host;
    final router = Router()
      ..get('/', (Request request) => Response.movedPermanently('/reader.html'))
      ..get('/book/<token>/<name>', (
        Request request,
        String token,
        String name,
      ) {
        final _ = name;
        return host._serveRegisteredBook(token);
      })
      ..get('/<path|.*>', (Request request, String path) {
        final relativePath = path.trim().isEmpty ? 'reader.html' : path;
        return host._serveAsset(relativePath);
      });

    final handler = const Pipeline()
        .addMiddleware(_corsMiddleware())
        .addHandler(router.call);
    final server = await shelf_io.serve(handler, InternetAddress.loopbackIPv4, 0);
    host = _FoliateHostServer._(rootDirectory: rootDirectory, server: server);
    return host;
  }

  Future<void> dispose() async {
    await server.close(force: true);
  }

  Future<String> registerBookFileUrl(String filePath) async {
    final file = File(filePath);
    final token = base64Url.encode(utf8.encode(file.absolute.path));
    _registeredBooks[token] = file;
    final fileName = Uri.encodeComponent(p.basename(file.path));
    return 'http://127.0.0.1:${server.port}/book/$token/$fileName';
  }

  Future<Response> _serveRegisteredBook(String token) async {
    final file = _registeredBooks[token];
    if (file == null || !await file.exists()) {
      return Response.notFound('missing book');
    }
    return _serveFile(file);
  }

  Future<Response> _serveAsset(String relativePath) async {
    final normalizedPath = p.normalize(relativePath).replaceAll('\\', '/');
    if (normalizedPath == '..' || normalizedPath.startsWith('../')) {
      return Response.forbidden('invalid asset path');
    }
    final file = File(p.join(rootDirectory.path, normalizedPath));
    if (!await file.exists()) {
      return Response.notFound('missing asset');
    }
    return _serveFile(file);
  }

  Future<Response> _serveFile(File file) async {
    final fileLength = await file.length();
    return Response.ok(
      file.openRead(),
      headers: <String, String>{
        'cache-control': 'no-store',
        'content-length': fileLength.toString(),
        'content-type': _contentTypeFor(file.path),
      },
    );
  }

  static Middleware _corsMiddleware() {
    return (Handler innerHandler) {
      return (Request request) async {
        if (request.method == 'OPTIONS') {
          return Response.ok('', headers: _corsHeaders);
        }
        final response = await innerHandler(request);
        return response.change(
          headers: <String, String>{...response.headers, ..._corsHeaders},
        );
      };
    };
  }

  static String _contentTypeFor(String filePath) {
    switch (p.extension(filePath).toLowerCase()) {
      case '.html':
        return 'text/html; charset=utf-8';
      case '.js':
      case '.mjs':
        return 'text/javascript; charset=utf-8';
      case '.css':
        return 'text/css; charset=utf-8';
      case '.json':
        return 'application/json; charset=utf-8';
      case '.svg':
        return 'image/svg+xml';
      case '.png':
        return 'image/png';
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.ttf':
        return 'font/ttf';
      case '.otf':
        return 'font/otf';
      case '.woff':
        return 'font/woff';
      case '.woff2':
        return 'font/woff2';
      case '.epub':
        return 'application/epub+zip';
      case '.txt':
        return 'text/plain; charset=utf-8';
      default:
        return 'application/octet-stream';
    }
  }

  static const Map<String, String> _corsHeaders = <String, String>{
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
  };
}
