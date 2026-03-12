import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:page_flip/page_flip.dart';

import '../../logging/app_run_log_service.dart';
import '../providers/reader_settings_provider.dart';
import '../reader_style.dart';
import '../utils/text_paginator.dart';

class ReaderPagedTextLocation {
  const ReaderPagedTextLocation({
    required this.pageIndex,
    required this.pageCount,
    required this.startOffset,
    required this.endOffset,
    required this.progress,
  });

  final int pageIndex;
  final int pageCount;
  final int startOffset;
  final int endOffset;
  final double progress;
}

class ReaderPagedTextView extends StatefulWidget {
  const ReaderPagedTextView({
    super.key,
    required this.text,
    required this.settings,
    required this.metaText,
    required this.initialProgress,
    this.baseOffset = 0,
    this.totalTextLength,
    this.onBoundaryPageRequest,
    required this.onLocationChanged,
  });

  final String text;
  final ReaderSettings settings;
  final String metaText;
  final double initialProgress;
  final int baseOffset;
  final int? totalTextLength;
  final Future<void> Function(int delta)? onBoundaryPageRequest;
  final ValueChanged<ReaderPagedTextLocation> onLocationChanged;

  @override
  ReaderPagedTextViewState createState() => ReaderPagedTextViewState();
}

class ReaderPagedTextViewState extends State<ReaderPagedTextView> {
  static const _outerPadding = EdgeInsets.fromLTRB(18, 76, 18, 30);
  static const _innerPadding = EdgeInsets.fromLTRB(24, 24, 24, 52);
  static const _footerHeight = 24.0;
  static const int _incrementalPaginationThreshold = 50000;

  final PageController _pageController = PageController();
  PageFlipController? _pageFlipController;
  int _pageFlipItemCount = 0;
  List<TextPageSlice> _pages = const <TextPageSlice>[];
  String? _layoutSignature;
  int _currentPage = 0;
  bool _isPaginating = false;
  int _pageFlipEpoch = 0;
  int? _pendingJumpPage;
  int? _pendingJumpOffset;
  bool _pendingJumpAnimated = false;
  int _paginationRequestId = 0;
  bool _boundaryRequestInFlight = false;
  DateTime? _lastBoundaryRequestAt;

  int get currentOffset {
    if (_pages.isEmpty) {
      return widget.baseOffset +
          (widget.text.length * widget.initialProgress).round();
    }
    return widget.baseOffset +
        _pages[_currentPage.clamp(0, _pages.length - 1)].startOffset;
  }

  String get currentSpeakWindowText {
    if (_pages.isEmpty) {
      return widget.text;
    }
    final start = _currentPage.clamp(0, _pages.length - 1);
    final end = math.min(_pages.length, start + 2);
    return _pages
        .sublist(start, end)
        .map((page) => page.displayText)
        .join('\n\n')
        .trim();
  }

  @override
  void didUpdateWidget(covariant ReaderPagedTextView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text == widget.text &&
        oldWidget.baseOffset == widget.baseOffset &&
        oldWidget.totalTextLength == widget.totalTextLength) {
      return;
    }

    _layoutSignature = null;
    _isPaginating = false;
    _pendingJumpPage = null;
    _pages = const <TextPageSlice>[];
    _currentPage = 0;
    if (oldWidget.settings.pageAnimation != widget.settings.pageAnimation &&
        !_usePageCurl) {
      _pageFlipController = null;
      _pageFlipItemCount = 0;
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  bool get _usePageCurl => widget.settings.pageAnimation == 'page_curl';

  void _ensurePageFlipController(int itemCount) {
    if (_pageFlipController == null || _pageFlipItemCount != itemCount) {
      _pageFlipController = PageFlipController();
      _pageFlipItemCount = itemCount;
    }
  }

  Future<void> jumpToProgress(double progress, {bool animated = true}) async {
    final totalLength =
        widget.totalTextLength != null && widget.totalTextLength! > 0
        ? widget.totalTextLength!
        : widget.text.length;
    final absoluteOffset = (totalLength * progress.clamp(0.0, 1.0)).round();
    if (_pages.isEmpty) {
      _pendingJumpOffset = absoluteOffset;
      _pendingJumpAnimated = animated;
      return;
    }
    await jumpToOffset(absoluteOffset, animated: animated);
  }

  Future<void> jumpToOffset(int offset, {bool animated = true}) async {
    _pendingJumpOffset = offset;
    _pendingJumpAnimated = animated;
    if (_pages.isEmpty) {
      return;
    }
    final localOffset = (offset - widget.baseOffset).clamp(
      0,
      widget.text.length,
    );
    final pageIndex = TextPaginationResult(
      _pages,
    ).pageIndexForOffset(localOffset);
    _pendingJumpPage = pageIndex;
    if (_usePageCurl) {
      setState(() {
        _currentPage = pageIndex;
        _pageFlipController = null;
        _pageFlipItemCount = 0;
        _pageFlipEpoch++;
      });
      _handlePageChanged(pageIndex);
      return;
    }
    if (!_pageController.hasClients) {
      return;
    }

    if (animated) {
      await _pageController.animateToPage(
        pageIndex,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    } else {
      _pageController.jumpToPage(pageIndex);
    }
    _handlePageChanged(pageIndex);
  }

  Future<bool> goToAdjacentPage(int delta, {bool animated = true}) async {
    if (_pages.isEmpty) {
      return false;
    }
    if (_usePageCurl) {
      _ensurePageFlipController(_pages.length);
      final target = _currentPage + delta;
      if (target < 0 || target >= _pages.length) {
        return false;
      }
      try {
        if (delta > 0) {
          _pageFlipController?.nextPage();
        } else if (delta < 0) {
          _pageFlipController?.previousPage();
        } else {
          return false;
        }
      } catch (_) {
        setState(() {
          _currentPage = target;
          _pageFlipController = null;
          _pageFlipItemCount = 0;
          _pageFlipEpoch++;
        });
        _handlePageChanged(target);
      }
      return true;
    }
    if (!_pageController.hasClients) {
      return false;
    }
    final target = (_currentPage + delta).clamp(0, _pages.length - 1);
    if (target == _currentPage) {
      return false;
    }
    if (animated) {
      await _pageController.animateToPage(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    } else {
      _pageController.jumpToPage(target);
    }
    _handlePageChanged(target);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final viewportSize = MediaQuery.sizeOf(context);
    _schedulePaginationIfNeeded(viewportSize);

    if (widget.text.trim().isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('当前文档没有可显示的文本内容。'),
        ),
      );
    }

    if (_isPaginating && _pages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_pages.isEmpty) {
      return const SizedBox.shrink();
    }

    final background = Color(widget.settings.bgColor);

    if (_usePageCurl) {
      _ensurePageFlipController(_pages.length);
      return ColoredBox(
        color: background,
        child: PageFlipWidget(
          key: ValueKey<String?>(
            'page_curl_${_layoutSignature ?? ''}_${_pages.length}_$_pageFlipEpoch$_currentPage',
          ),
          controller: _pageFlipController,
          backgroundColor: background,
          initialIndex: _currentPage.clamp(0, _pages.length - 1),
          onPageFlipped: _handlePageChanged,
          children: [
            for (var index = 0; index < _pages.length; index++)
              _buildPage(index, _pages[index]),
          ],
        ),
      );
    }

    return ColoredBox(
      color: background,
      child: NotificationListener<ScrollNotification>(
        onNotification: _handlePageScrollNotification,
        child: PageView.builder(
          controller: _pageController,
          padEnds: false,
          allowImplicitScrolling: true,
          itemCount: _pages.length,
          onPageChanged: _handlePageChanged,
          itemBuilder: (context, index) {
            final page = _pages[index];
            return AnimatedBuilder(
              animation: _pageController,
              child: _buildPage(index, page),
              builder: (context, child) {
                final delta = _pageDeltaFor(index);
                return _AnimatedPageTurn(
                  delta: delta,
                  animationType: widget.settings.pageAnimation,
                  backgroundColor: background,
                  child: child!,
                );
              },
            );
          },
        ),
      ),
    );
  }

  bool _handlePageScrollNotification(ScrollNotification notification) {
    final onBoundaryPageRequest = widget.onBoundaryPageRequest;
    if (onBoundaryPageRequest == null || _pages.isEmpty || _isPaginating) {
      return false;
    }
    if (notification is! OverscrollNotification) {
      return false;
    }
    if (_boundaryRequestInFlight) {
      return false;
    }

    var delta = 0;
    if (notification.overscroll > 0 && _currentPage >= _pages.length - 1) {
      delta = 1;
    } else if (notification.overscroll < 0 && _currentPage <= 0) {
      delta = -1;
    }
    if (delta == 0) {
      return false;
    }

    final now = DateTime.now();
    final last = _lastBoundaryRequestAt;
    if (last != null &&
        now.difference(last) < const Duration(milliseconds: 260)) {
      return false;
    }
    _lastBoundaryRequestAt = now;
    _boundaryRequestInFlight = true;
    unawaited(
      onBoundaryPageRequest(delta).whenComplete(() {
        _boundaryRequestInFlight = false;
      }),
    );
    return false;
  }

  void _schedulePaginationIfNeeded(Size viewportSize) {
    if (viewportSize.width <= 0 || viewportSize.height <= 0) {
      return;
    }

    final signature =
        '${widget.text.hashCode}|${viewportSize.width.round()}|${viewportSize.height.round()}|'
        '${widget.settings.fontSize}|${widget.settings.lineHeight}|${widget.settings.fontFamily}|'
        '${widget.baseOffset}|${widget.totalTextLength ?? widget.text.length}';
    if (signature == _layoutSignature || _isPaginating) {
      return;
    }

    _layoutSignature = signature;
    _isPaginating = true;
    final requestId = ++_paginationRequestId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(_paginate(viewportSize, requestId));
    });
  }

  Future<void> _paginate(Size viewportSize, int requestId) async {
    final stopwatch = Stopwatch()..start();
    final desiredAbsoluteOffset = _pendingJumpOffset ?? currentOffset;
    final preservedOffset = (desiredAbsoluteOffset - widget.baseOffset).clamp(
      0,
      widget.text.length,
    );
    final contentSize = Size(
      math.max(
        24,
        viewportSize.width -
            _outerPadding.horizontal -
            _innerPadding.horizontal,
      ),
      math.max(
        24,
        viewportSize.height -
            _outerPadding.vertical -
            _innerPadding.vertical -
            _footerHeight,
      ),
    );
    final style = buildReaderTextStyle(
      widget.settings,
      color: Color(widget.settings.fgColor),
    );
    final useIncremental =
        widget.text.length >= _incrementalPaginationThreshold;

    if (!useIncremental) {
      final result = TextPaginator.paginate(
        text: widget.text,
        style: style,
        size: contentSize,
        cacheKey: _layoutSignature,
      );
      final pages = result.pages.isEmpty
          ? <TextPageSlice>[
              TextPageSlice(
                startOffset: 0,
                endOffset: widget.text.length,
                text: widget.text,
              ),
            ]
          : result.pages;
      final targetPage =
          _pendingJumpPage?.clamp(0, pages.length - 1) ??
          TextPaginationResult(pages).pageIndexForOffset(preservedOffset);
      _finalizePagination(
        pages: pages,
        targetPage: targetPage,
        requestId: requestId,
        stopwatch: stopwatch,
      );
      return;
    }

    var targetResolved = false;
    var targetPage = 0;
    final result = await TextPaginator.paginateIncremental(
      text: widget.text,
      style: style,
      size: contentSize,
      cacheKey: _layoutSignature,
      isCancelled: () =>
          !mounted || requestId != _paginationRequestId || !_isPaginating,
      onProgress: (pages) {
        if (!mounted || requestId != _paginationRequestId || pages.isEmpty) {
          return;
        }
        if (!targetResolved && pages.last.endOffset >= preservedOffset) {
          targetResolved = true;
          targetPage = TextPaginationResult(
            pages,
          ).pageIndexForOffset(preservedOffset);
        }
        setState(() {
          _pages = pages;
          if (targetResolved) {
            _currentPage = targetPage;
          }
        });
      },
    );

    if (!targetResolved) {
      targetPage = TextPaginationResult(
        result.pages,
      ).pageIndexForOffset(preservedOffset);
    }
    _finalizePagination(
      pages: result.pages.isEmpty
          ? <TextPageSlice>[
              TextPageSlice(
                startOffset: 0,
                endOffset: widget.text.length,
                text: widget.text,
              ),
            ]
          : result.pages,
      targetPage: targetPage,
      requestId: requestId,
      stopwatch: stopwatch,
    );
  }

  void _finalizePagination({
    required List<TextPageSlice> pages,
    required int targetPage,
    required int requestId,
    required Stopwatch stopwatch,
  }) {
    if (!mounted || requestId != _paginationRequestId) {
      return;
    }
    final shouldAnimateJump = _pendingJumpAnimated;
    setState(() {
      _pages = pages;
      _currentPage = targetPage;
      _isPaginating = false;
      if (_usePageCurl) {
        _pageFlipController = null;
        _pageFlipItemCount = 0;
        _pageFlipEpoch++;
      }
      _pendingJumpPage = null;
      _pendingJumpOffset = null;
      _pendingJumpAnimated = false;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || requestId != _paginationRequestId) {
        return;
      }
      if (_usePageCurl) {
        _handlePageChanged(targetPage);
        return;
      }
      if (!_pageController.hasClients) {
        return;
      }
      if (shouldAnimateJump) {
        _pageController.animateToPage(
          targetPage,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
      } else {
        _pageController.jumpToPage(targetPage);
      }
      _handlePageChanged(targetPage);
    });

    stopwatch.stop();
    unawaited(
      AppRunLogService.instance.logEvent(
        action: 'reader.page.paginate',
        result: 'ok',
        durationMs: stopwatch.elapsedMilliseconds,
        context: <String, Object?>{
          'pages': pages.length,
          'text_length': widget.text.length,
          'base_offset': widget.baseOffset,
          'incremental': widget.text.length >= _incrementalPaginationThreshold,
        },
      ),
    );
  }

  void _handlePageChanged(int index) {
    if (_pages.isEmpty) {
      return;
    }
    _currentPage = index.clamp(0, _pages.length - 1);
    final page = _pages[_currentPage];
    final totalTextLength =
        widget.totalTextLength != null && widget.totalTextLength! > 0
        ? widget.totalTextLength!
        : widget.text.length;
    final absoluteStart = widget.baseOffset + page.startOffset;
    final absoluteEnd = widget.baseOffset + page.endOffset;
    final progress = totalTextLength <= 0
        ? 0.0
        : (absoluteStart / totalTextLength).clamp(0.0, 1.0);
    widget.onLocationChanged(
      ReaderPagedTextLocation(
        pageIndex: _currentPage,
        pageCount: _pages.length,
        startOffset: absoluteStart,
        endOffset: absoluteEnd,
        progress: progress,
      ),
    );
    if (mounted) {
      setState(() {});
    }
  }

  double _pageDeltaFor(int index) {
    if (!_pageController.hasClients) {
      return (_currentPage - index).toDouble();
    }
    final page = _pageController.page;
    if (page == null) {
      return (_currentPage - index).toDouble();
    }
    return page - index;
  }

  Widget _buildPage(int index, TextPageSlice page) {
    final background = Color(widget.settings.bgColor);
    final foreground = Color(widget.settings.fgColor);

    return Padding(
      padding: _outerPadding,
      child: RepaintBoundary(
        child: DecoratedBox(
          decoration: BoxDecoration(color: background),
          child: Padding(
            padding: _innerPadding,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Text(
                    page.displayText,
                    style: buildReaderTextStyle(
                      widget.settings,
                      color: foreground,
                    ),
                    textAlign: resolveReaderTextAlign(widget.settings),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.metaText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: buildReaderTextStyle(
                            widget.settings,
                            color: foreground.withValues(alpha: 0.55),
                            fontSize: 12,
                            lineHeight: 1.2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${index + 1} / ${_pages.length}',
                        style: buildReaderTextStyle(
                          widget.settings,
                          color: foreground.withValues(alpha: 0.55),
                          fontSize: 12,
                          lineHeight: 1.2,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedPageTurn extends StatelessWidget {
  const _AnimatedPageTurn({
    required this.delta,
    required this.animationType,
    required this.backgroundColor,
    required this.child,
  });

  final double delta;
  final String animationType;
  final Color backgroundColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final clamped = delta.clamp(-1.0, 1.0);
    final distance = clamped.abs();

    switch (animationType) {
      case 'fade':
        return Opacity(
          opacity: 1 - (distance * 0.38),
          child: Transform.translate(
            offset: Offset(clamped * 24, 0),
            child: child,
          ),
        );
      case 'flip':
      case 'sheet':
        final shadowOpacity = 0.22 * distance;
        return Stack(
          children: [
            Transform.translate(
              offset: Offset(clamped * -22, 0),
              child: Transform(
                alignment: clamped >= 0
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0019)
                  ..rotateY(-clamped * 0.66)
                  ..translateByDouble(clamped * -16, 0, 0, 1),
                child: child,
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: clamped >= 0
                          ? Alignment.centerLeft
                          : Alignment.centerRight,
                      end: clamped >= 0
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      colors: [
                        Colors.black.withValues(alpha: shadowOpacity),
                        Colors.black.withValues(alpha: shadowOpacity * 0.33),
                        backgroundColor.withValues(alpha: 0),
                      ],
                      stops: const [0, 0.36, 1],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      case 'slide':
      default:
        return Transform.translate(
          offset: Offset(clamped * 12, 0),
          child: child,
        );
    }
  }
}
