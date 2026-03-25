import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../app/runtime_platform.dart';
import 'foliate_host_runtime.dart';

class FoliateBridgeEvent {
  const FoliateBridgeEvent({
    required this.type,
    required this.detail,
  });

  final String type;
  final Map<String, Object?> detail;

  factory FoliateBridgeEvent.fromDynamic(dynamic value) {
    final payload =
        value is Map ? Map<String, Object?>.from(value.cast<String, Object?>()) : const <String, Object?>{};
    final detailValue = payload['detail'];
    return FoliateBridgeEvent(
      type: payload['type']?.toString() ?? 'unknown',
      detail: detailValue is Map
          ? Map<String, Object?>.from(detailValue.cast<String, Object?>())
          : const <String, Object?>{},
    );
  }
}

class FoliateTextSection {
  const FoliateTextSection({
    required this.id,
    required this.title,
    required this.content,
  });

  final String id;
  final String title;
  final String content;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'content': content,
  };
}

class FoliateReaderBridgeController {
  InAppWebViewController? _webViewController;
  final Completer<void> _readyCompleter = Completer<void>();
  bool _disposed = false;

  bool get isReady => _readyCompleter.isCompleted;

  void attach(InAppWebViewController controller) {
    if (_disposed) {
      return;
    }
    _webViewController = controller;
  }

  void detach() {
    _webViewController = null;
  }

  void dispose() {
    _disposed = true;
    _webViewController = null;
    if (!_readyCompleter.isCompleted) {
      _readyCompleter.complete();
    }
  }

  void handleEvent(FoliateBridgeEvent event) {
    if (event.type == 'ready' && !_readyCompleter.isCompleted) {
      _readyCompleter.complete();
    }
  }

  Future<void> waitUntilReady() => _readyCompleter.future;

  Future<void> openEpubFile(String filePath) async {
    final uri = Uri.file(filePath).toString();
    await _invoke(
      'window.WenwenReaderHost?.openEpubUrl(${jsonEncode(uri)});',
    );
  }

  Future<void> openText({
    required String title,
    required String text,
    String? author,
    List<FoliateTextSection> sections = const <FoliateTextSection>[],
  }) async {
    final payload = <String, Object?>{
      'title': title,
      'author': author,
      'text': text,
      'sections': sections.map((section) => section.toJson()).toList(),
    };
    await _invoke(
      'window.WenwenReaderHost?.openText(${jsonEncode(payload)});',
    );
  }

  Future<void> _invoke(String source) async {
    await waitUntilReady();
    final controller = _webViewController;
    if (_disposed || controller == null) {
      return;
    }
    await controller.evaluateJavascript(source: source);
  }
}

class FoliateReaderBridge extends StatefulWidget {
  const FoliateReaderBridge({
    super.key,
    required this.session,
    required this.controller,
    this.onEvent,
    this.loadingBuilder,
    this.unsupportedBuilder,
  });

  final FoliateHostRuntimeSession session;
  final FoliateReaderBridgeController controller;
  final ValueChanged<FoliateBridgeEvent>? onEvent;
  final WidgetBuilder? loadingBuilder;
  final WidgetBuilder? unsupportedBuilder;

  @override
  State<FoliateReaderBridge> createState() => _FoliateReaderBridgeState();
}

class _FoliateReaderBridgeState extends State<FoliateReaderBridge> {
  bool _pageLoaded = false;

  bool get _isSupportedPlatform =>
      detectLocalRuntimePlatform() == LocalRuntimePlatform.android &&
      InAppWebViewPlatform.instance != null;

  @override
  void dispose() {
    widget.controller.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isSupportedPlatform) {
      return widget.unsupportedBuilder?.call(context) ??
          const Center(child: Text('foliate bridge is only enabled on Android.'));
    }

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        InAppWebView(
          initialFile: widget.session.entryFile.path,
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            transparentBackground: true,
            allowFileAccessFromFileURLs: true,
            allowUniversalAccessFromFileURLs: true,
            allowFileAccess: true,
            disableHorizontalScroll: false,
            disableVerticalScroll: false,
            useShouldOverrideUrlLoading: false,
          ),
          onWebViewCreated: (controller) {
            widget.controller.attach(controller);
            controller.addJavaScriptHandler(
              handlerName: 'foliateHost',
              callback: (arguments) {
                final event = FoliateBridgeEvent.fromDynamic(
                  arguments.isEmpty ? null : arguments.first,
                );
                widget.controller.handleEvent(event);
                widget.onEvent?.call(event);
                return null;
              },
            );
          },
          onLoadStop: (_, _) {
            if (mounted) {
              setState(() => _pageLoaded = true);
            }
          },
        ),
        if (!_pageLoaded)
          Positioned.fill(
            child: widget.loadingBuilder?.call(context) ??
                const ColoredBox(
                  color: Colors.transparent,
                  child: Center(child: CircularProgressIndicator()),
                ),
          ),
      ],
    );
  }
}
