import 'dart:io';

import 'package:http/http.dart' as http;

import 'download_task_store.dart';

typedef DownloadStatusCallback = void Function(String message);
typedef DownloadProgressCallback =
    void Function(ResumableDownloadProgress progress);

class ResumableDownloadProgress {
  const ResumableDownloadProgress({
    required this.source,
    required this.downloadedBytes,
    required this.totalBytes,
    required this.resumeOffset,
    required this.usedRangeRequest,
    required this.fellBackToFullRedownload,
  });

  final String source;
  final int downloadedBytes;
  final int totalBytes;
  final int resumeOffset;
  final bool usedRangeRequest;
  final bool fellBackToFullRedownload;

  double get progress {
    if (totalBytes <= 0) {
      return 0;
    }
    return (downloadedBytes / totalBytes).clamp(0, 1);
  }
}

class ResumableDownloadResult {
  const ResumableDownloadResult({
    required this.source,
    required this.downloadedBytes,
    required this.totalBytes,
    required this.resumeOffset,
    required this.usedRangeRequest,
    required this.fellBackToFullRedownload,
  });

  final String source;
  final int downloadedBytes;
  final int totalBytes;
  final int resumeOffset;
  final bool usedRangeRequest;
  final bool fellBackToFullRedownload;
}

class SingleConnectionResumableDownloader {
  SingleConnectionResumableDownloader({
    required DownloadTaskStore downloadTaskStore,
    http.Client Function()? clientFactory,
    this.userAgent = 'WenwenTome/1.0',
  }) : _downloadTaskStore = downloadTaskStore,
       _clientFactory = clientFactory ?? http.Client.new;

  final DownloadTaskStore _downloadTaskStore;
  final http.Client Function() _clientFactory;
  final String userAgent;

  Future<ResumableDownloadResult> download({
    required DownloadTaskKind kind,
    required String modelId,
    required List<String> candidates,
    required File tempFile,
    required String finalPath,
    DownloadStatusCallback? onStatus,
    DownloadProgressCallback? onProgress,
  }) async {
    if (candidates.isEmpty) {
      throw Exception('No download candidates available.');
    }

    await _downloadTaskStore.ensureInitialized();

    Object? lastError;
    for (final source in candidates) {
      final task = await _downloadTaskStore.getTask(kind, modelId);
      final existingBytes = await _existingPartialLength(
        tempFile: tempFile,
        task: task,
        source: source,
      );
      try {
        return await _downloadFromSource(
          kind: kind,
          modelId: modelId,
          source: source,
          tempFile: tempFile,
          finalPath: finalPath,
          existingBytes: existingBytes,
          onStatus: onStatus,
          onProgress: onProgress,
        );
      } catch (error) {
        lastError = error;
      }
    }

    throw Exception('All download sources failed: $lastError');
  }

  Future<ResumableDownloadResult> _downloadFromSource({
    required DownloadTaskKind kind,
    required String modelId,
    required String source,
    required File tempFile,
    required String finalPath,
    required int existingBytes,
    DownloadStatusCallback? onStatus,
    DownloadProgressCallback? onProgress,
  }) async {
    if (existingBytes > 0) {
      try {
        onStatus?.call(
          'Found a partial download (${_formatBytes(existingBytes)}). Trying to resume with Range.',
        );
        return await _performRequest(
          kind: kind,
          modelId: modelId,
          source: source,
          tempFile: tempFile,
          finalPath: finalPath,
          resumeOffset: existingBytes,
          onProgress: onProgress,
        );
      } on _RestartFullDownloadException catch (error) {
        onStatus?.call(error.message);
      }
    }

    return _performRequest(
      kind: kind,
      modelId: modelId,
      source: source,
      tempFile: tempFile,
      finalPath: finalPath,
      resumeOffset: 0,
      onProgress: onProgress,
      fellBackToFullRedownload: existingBytes > 0,
    );
  }

  Future<ResumableDownloadResult> _performRequest({
    required DownloadTaskKind kind,
    required String modelId,
    required String source,
    required File tempFile,
    required String finalPath,
    required int resumeOffset,
    required DownloadProgressCallback? onProgress,
    bool fellBackToFullRedownload = false,
  }) async {
    final client = _clientFactory();
    IOSink? sink;
    var downloadedBytes = resumeOffset;
    var totalBytes = 0;
    try {
      await tempFile.parent.create(recursive: true);
      if (resumeOffset == 0) {
        await _resetPartialFile(tempFile);
      }

      await _downloadTaskStore.markQueued(
        kind: kind,
        modelId: modelId,
        source: source,
        tempPath: tempFile.path,
        finalPath: finalPath,
      );

      final request = http.Request('GET', Uri.parse(source))
        ..headers['User-Agent'] = userAgent;
      if (resumeOffset > 0) {
        request.headers['Range'] = 'bytes=$resumeOffset-';
      }

      final response = await client.send(request);
      final metadata = _validateResponse(
        response: response,
        resumeOffset: resumeOffset,
      );

      downloadedBytes = metadata.initialDownloadedBytes;
      totalBytes = metadata.totalBytes;

      await _downloadTaskStore.markProgress(
        kind: kind,
        modelId: modelId,
        source: source,
        tempPath: tempFile.path,
        finalPath: finalPath,
        downloadedBytes: downloadedBytes,
        totalBytes: totalBytes,
      );
      onProgress?.call(
        ResumableDownloadProgress(
          source: source,
          downloadedBytes: downloadedBytes,
          totalBytes: totalBytes,
          resumeOffset: resumeOffset,
          usedRangeRequest: metadata.usedRangeRequest,
          fellBackToFullRedownload: fellBackToFullRedownload,
        ),
      );

      if (metadata.isAlreadyComplete) {
        return ResumableDownloadResult(
          source: source,
          downloadedBytes: downloadedBytes,
          totalBytes: totalBytes,
          resumeOffset: resumeOffset,
          usedRangeRequest: metadata.usedRangeRequest,
          fellBackToFullRedownload: fellBackToFullRedownload,
        );
      }

      sink = tempFile.openWrite(
        mode: resumeOffset > 0 ? FileMode.append : FileMode.writeOnly,
      );
      await for (final chunk in response.stream) {
        sink.add(chunk);
        downloadedBytes += chunk.length;
        await _downloadTaskStore.markProgress(
          kind: kind,
          modelId: modelId,
          source: source,
          tempPath: tempFile.path,
          finalPath: finalPath,
          downloadedBytes: downloadedBytes,
          totalBytes: totalBytes,
        );
        onProgress?.call(
          ResumableDownloadProgress(
            source: source,
            downloadedBytes: downloadedBytes,
            totalBytes: totalBytes,
            resumeOffset: resumeOffset,
            usedRangeRequest: metadata.usedRangeRequest,
            fellBackToFullRedownload: fellBackToFullRedownload,
          ),
        );
      }
      await sink.flush();
      await sink.close();
      sink = null;

      if (totalBytes > 0 && downloadedBytes != totalBytes) {
        throw Exception(
          'Downloaded file length mismatch: expected $totalBytes bytes, got $downloadedBytes bytes.',
        );
      }

      return ResumableDownloadResult(
        source: source,
        downloadedBytes: downloadedBytes,
        totalBytes: totalBytes,
        resumeOffset: resumeOffset,
        usedRangeRequest: metadata.usedRangeRequest,
        fellBackToFullRedownload: fellBackToFullRedownload,
      );
    } catch (error) {
      await sink?.close();
      await _downloadTaskStore.markFailed(
        kind: kind,
        modelId: modelId,
        source: source,
        tempPath: tempFile.path,
        finalPath: finalPath,
        error: error.toString(),
        downloadedBytes: downloadedBytes,
        totalBytes: totalBytes,
      );
      rethrow;
    } finally {
      client.close();
    }
  }

  Future<int> _existingPartialLength({
    required File tempFile,
    required DownloadTaskRecord? task,
    required String source,
  }) async {
    if (!await tempFile.exists()) {
      return 0;
    }
    if (task == null || task.source != source) {
      return 0;
    }
    return tempFile.length();
  }

  Future<void> _resetPartialFile(File tempFile) async {
    if (await tempFile.exists()) {
      await tempFile.delete();
    }
  }

  _ValidatedResponse _validateResponse({
    required http.StreamedResponse response,
    required int resumeOffset,
  }) {
    final statusCode = response.statusCode;
    final contentLength = _normalizedContentLength(response.contentLength);
    final contentRangeHeader = response.headers['content-range'];
    final contentRange = contentRangeHeader == null
        ? null
        : _ContentRangeHeader.tryParse(contentRangeHeader);

    if (resumeOffset > 0) {
      if (statusCode == HttpStatus.partialContent) {
        if (contentRange == null ||
            contentRange.totalBytes == null ||
            contentRange.start != resumeOffset) {
          throw _RestartFullDownloadException(
            'Resume response had an invalid Content-Range. Falling back to a full redownload.',
          );
        }
        final expectedLength = contentRange.end - contentRange.start + 1;
        if (contentLength > 0 && contentLength != expectedLength) {
          throw _RestartFullDownloadException(
            'Resume response length did not match Content-Range. Falling back to a full redownload.',
          );
        }
        if (contentRange.totalBytes! < resumeOffset) {
          throw _RestartFullDownloadException(
            'Resume response total length was smaller than the local partial file. Falling back to a full redownload.',
          );
        }
        return _ValidatedResponse(
          totalBytes: contentRange.totalBytes!,
          initialDownloadedBytes: resumeOffset,
          usedRangeRequest: true,
        );
      }

      if (statusCode == HttpStatus.requestedRangeNotSatisfiable) {
        final totalBytes = contentRange?.totalBytes;
        if (totalBytes != null && totalBytes == resumeOffset) {
          return _ValidatedResponse(
            totalBytes: totalBytes,
            initialDownloadedBytes: resumeOffset,
            isAlreadyComplete: true,
            usedRangeRequest: true,
          );
        }
        throw _RestartFullDownloadException(
          'Server rejected the Range request. Falling back to a full redownload.',
        );
      }

      if (statusCode == HttpStatus.ok) {
        throw _RestartFullDownloadException(
          'Server ignored the Range request. Falling back to a full redownload.',
        );
      }

      throw Exception('HTTP $statusCode');
    }

    if (statusCode < HttpStatus.ok ||
        statusCode >= HttpStatus.multipleChoices) {
      throw Exception('HTTP $statusCode');
    }

    if (statusCode == HttpStatus.partialContent) {
      if (contentRange == null ||
          contentRange.totalBytes == null ||
          contentRange.start != 0) {
        throw Exception(
          'Unexpected 206 response without a valid Content-Range.',
        );
      }
      final expectedLength = contentRange.end - contentRange.start + 1;
      if (contentLength > 0 && contentLength != expectedLength) {
        throw Exception(
          '206 response length did not match Content-Range during a full download.',
        );
      }
      return _ValidatedResponse(
        totalBytes: contentRange.totalBytes!,
        initialDownloadedBytes: 0,
      );
    }

    return _ValidatedResponse(
      totalBytes: contentLength,
      initialDownloadedBytes: 0,
    );
  }

  int _normalizedContentLength(int? contentLength) {
    if (contentLength == null || contentLength < 0) {
      return 0;
    }
    return contentLength;
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) {
      return '0 B';
    }
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _ValidatedResponse {
  const _ValidatedResponse({
    required this.totalBytes,
    required this.initialDownloadedBytes,
    this.isAlreadyComplete = false,
    this.usedRangeRequest = false,
  });

  final int totalBytes;
  final int initialDownloadedBytes;
  final bool isAlreadyComplete;
  final bool usedRangeRequest;
}

class _RestartFullDownloadException implements Exception {
  const _RestartFullDownloadException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _ContentRangeHeader {
  const _ContentRangeHeader({
    required this.start,
    required this.end,
    required this.totalBytes,
  });

  final int start;
  final int end;
  final int? totalBytes;

  static _ContentRangeHeader? tryParse(String value) {
    final fullMatch = RegExp(r'^bytes (\d+)-(\d+)/(\d+|\*)$').firstMatch(value);
    if (fullMatch != null) {
      final start = int.parse(fullMatch.group(1)!);
      final end = int.parse(fullMatch.group(2)!);
      if (end < start) {
        return null;
      }
      final totalGroup = fullMatch.group(3)!;
      return _ContentRangeHeader(
        start: start,
        end: end,
        totalBytes: totalGroup == '*' ? null : int.parse(totalGroup),
      );
    }

    final totalMatch = RegExp(r'^bytes \*/(\d+)$').firstMatch(value);
    if (totalMatch != null) {
      final totalBytes = int.parse(totalMatch.group(1)!);
      return _ContentRangeHeader(
        start: totalBytes,
        end: totalBytes,
        totalBytes: totalBytes,
      );
    }

    return null;
  }
}
