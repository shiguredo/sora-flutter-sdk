/// DevTools 画面のログパネル UI を提供するモジュール。
///
/// ログ種別の切り替え、ログ本文の表示、クリップボードコピーを行う
/// 表示専用 widget をここに集約する。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'devtools_models.dart';

class DevToolsLogPanel extends StatelessWidget {
  /// ログパネルを構築する。
  const DevToolsLogPanel({
    super.key,
    required this.selectedLogTab,
    required this.selectedLogDescription,
    required this.selectedLogs,
    required this.logSearchController,
    required this.onLogTabChanged,
    required this.onLogSearchQueryChanged,
    required this.onCopyLogs,
    required this.onClearLogs,
    required this.scrollController,
    required this.followLatest,
    required this.onFollowLatestChanged,
    this.onClose,
    this.canFetchStats = false,
    this.onFetchStats,
    this.plain = false,
  });

  final DevToolsLogTab selectedLogTab;
  final String selectedLogDescription;
  final List<String> selectedLogs;
  final TextEditingController logSearchController;
  final ValueChanged<DevToolsLogTab> onLogTabChanged;
  final ValueChanged<String> onLogSearchQueryChanged;
  final VoidCallback onCopyLogs;
  final VoidCallback onClearLogs;
  final ScrollController scrollController;
  final bool followLatest;
  final ValueChanged<bool> onFollowLatestChanged;
  final VoidCallback? onClose;
  final bool canFetchStats;
  final VoidCallback? onFetchStats;
  final bool plain;

  /// 現在のログ種別とログ本文を表示するログパネルを描画する。
  @override
  Widget build(BuildContext context) {
    final logText = _buildLogText();
    if (followLatest) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scrollController.hasClients) {
          scrollController.jumpTo(scrollController.position.maxScrollExtent);
        }
      });
    }
    final content = Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<DevToolsLogTab>(
                  initialValue: selectedLogTab,
                  decoration: const InputDecoration(
                    labelText: 'Log Type',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: DevToolsLogTab.app,
                      child: Text('Logs'),
                    ),
                    DropdownMenuItem(
                      value: DevToolsLogTab.event,
                      child: Text('Events'),
                    ),
                    DropdownMenuItem(
                      value: DevToolsLogTab.timeline,
                      child: Text('Timeline'),
                    ),
                    DropdownMenuItem(
                      value: DevToolsLogTab.stats,
                      child: Text('Stats'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    onLogTabChanged(value);
                  },
                ),
              ),
              if (onClose != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: onClose,
                  icon: const Icon(Icons.close),
                  tooltip: 'Close Logs',
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: logSearchController,
            decoration: InputDecoration(
              labelText: 'Search Logs',
              hintText: 'Filter log lines',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: logSearchController.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        logSearchController.clear();
                        onLogSearchQueryChanged('');
                      },
                      icon: const Icon(Icons.clear),
                      tooltip: 'Clear Search',
                    ),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: onLogSearchQueryChanged,
          ),
          const SizedBox(height: 8),
          Text(
            selectedLogDescription,
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilterChip(
                selected: followLatest,
                onSelected: onFollowLatestChanged,
                avatar: const Icon(Icons.vertical_align_bottom, size: 18),
                label: const Text('Follow latest'),
              ),
              if (selectedLogTab == DevToolsLogTab.stats &&
                  onFetchStats != null)
                OutlinedButton(
                  onPressed: canFetchStats ? onFetchStats : null,
                  child: const Text('Get Stats'),
                ),
              OutlinedButton(
                onPressed: selectedLogs.isEmpty ? null : onClearLogs,
                child: const Text('Clear Logs'),
              ),
              OutlinedButton(
                onPressed: onCopyLogs,
                child: const Text('Copy Logs'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: NotificationListener<UserScrollNotification>(
              onNotification: (notification) {
                if (!scrollController.hasClients) {
                  return false;
                }
                final distance =
                    scrollController.position.maxScrollExtent -
                    scrollController.position.pixels;
                final isAtLatest = distance <= 48;
                if (isAtLatest != followLatest) {
                  onFollowLatestChanged(isAtLatest);
                }
                return false;
              },
              child: SingleChildScrollView(
                controller: scrollController,
                child: SelectableText.rich(logText),
              ),
            ),
          ),
        ],
      ),
    );
    if (plain) {
      return content;
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF4F4F4),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: content,
    );
  }

  /// 検索語句に一致する部分をハイライトしたログ本文を構築する。
  TextSpan _buildLogText() {
    const baseStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: 12,
      height: 1.4,
    );
    final query = logSearchController.text;
    if (selectedLogs.isEmpty) {
      return TextSpan(
        text: query.isEmpty ? 'No logs yet' : 'No matching logs',
        style: baseStyle,
      );
    }
    if (query.isEmpty) {
      return TextSpan(text: selectedLogs.join('\n'), style: baseStyle);
    }

    final normalizedQuery = query.toLowerCase();
    final highlightStyle = baseStyle.copyWith(
      color: Colors.black,
      backgroundColor: Colors.amberAccent,
      fontWeight: FontWeight.bold,
    );
    final children = <InlineSpan>[];
    for (var index = 0; index < selectedLogs.length; index++) {
      if (index > 0) {
        children.add(const TextSpan(text: '\n'));
      }
      children.addAll(
        _highlightLine(
          selectedLogs[index],
          normalizedQuery: normalizedQuery,
          baseStyle: baseStyle,
          highlightStyle: highlightStyle,
        ),
      );
    }
    return TextSpan(style: baseStyle, children: children);
  }

  /// 1 行のログを検索語句との一致部分で分割する。
  static List<InlineSpan> _highlightLine(
    String line, {
    required String normalizedQuery,
    required TextStyle baseStyle,
    required TextStyle highlightStyle,
  }) {
    final normalizedLine = line.toLowerCase();
    final spans = <InlineSpan>[];
    var cursor = 0;
    while (cursor < line.length) {
      final matchStart = normalizedLine.indexOf(normalizedQuery, cursor);
      if (matchStart == -1) {
        spans.add(TextSpan(text: line.substring(cursor), style: baseStyle));
        break;
      }
      if (matchStart > cursor) {
        spans.add(
          TextSpan(text: line.substring(cursor, matchStart), style: baseStyle),
        );
      }
      final matchEnd = matchStart + normalizedQuery.length;
      spans.add(
        TextSpan(
          text: line.substring(matchStart, matchEnd),
          style: highlightStyle,
        ),
      );
      cursor = matchEnd;
    }
    return spans;
  }

  /// 表示中ログをクリップボードへコピーする。
  static Future<void> copyLogs(List<String> selectedLogs) {
    final text = selectedLogs.isEmpty ? 'No logs yet' : selectedLogs.join('\n');
    return Clipboard.setData(ClipboardData(text: text));
  }
}
