import 'package:flutter/material.dart';

import 'bootstrap_controller.dart';

class AppBootstrapScreen extends StatelessWidget {
  const AppBootstrapScreen({
    super.key,
    required this.controller,
    required this.onRetry,
    required this.onEnterSafeMode,
  });

  final BootstrapController controller;
  final VoidCallback onRetry;
  final VoidCallback onEnterSafeMode;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final snapshot = controller.snapshot;
        final failed = snapshot.stage == BootstrapStage.failed;
        final colorScheme = Theme.of(context).colorScheme;

        return Scaffold(
          body: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  colorScheme.primaryContainer,
                  colorScheme.surface,
                ],
              ),
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Card(
                  margin: const EdgeInsets.all(24),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        CircleAvatar(
                          radius: 34,
                          backgroundColor: colorScheme.primaryContainer,
                          child: Icon(
                            Icons.menu_book_rounded,
                            size: 36,
                            color: colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          '文文Tome',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          snapshot.safeMode ? '安全模式' : '正在启动',
                          style: TextStyle(
                            color: colorScheme.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(height: 20),
                        if (!failed) ...<Widget>[
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                        ],
                        Text(snapshot.message, textAlign: TextAlign.center),
                        if (snapshot.degradedStartup &&
                            snapshot.backgroundWarmupPending) ...<Widget>[
                          const SizedBox(height: 8),
                          Text(
                            '主界面将优先进入，后台继续准备网文和缓存。',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.65,
                              ),
                            ),
                          ),
                        ],
                        if (failed) ...<Widget>[
                          const SizedBox(height: 12),
                          Text(
                            snapshot.error.toString(),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: colorScheme.error,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: onRetry,
                                  child: const Text('重试'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton(
                                  onPressed: onEnterSafeMode,
                                  child: const Text('安全模式启动'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
