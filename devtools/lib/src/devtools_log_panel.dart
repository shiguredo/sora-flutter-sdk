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
    required this.onLogTabChanged,
    required this.onCopyLogs,
    this.onClose,
    this.canFetchStats = false,
    this.onFetchStats,
    this.plain = false,
  });

  final DevToolsLogTab selectedLogTab;
  final String selectedLogDescription;
  final List<String> selectedLogs;
  final ValueChanged<DevToolsLogTab> onLogTabChanged;
  final VoidCallback onCopyLogs;
  final VoidCallback? onClose;
  final bool canFetchStats;
  final VoidCallback? onFetchStats;
  final bool plain;

  /// 現在のログ種別とログ本文を表示するログパネルを描画する。
  @override
  Widget build(BuildContext context) {
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
          Row(
            children: [
              Expanded(
                child: Text(
                  selectedLogDescription,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
              const SizedBox(width: 8),
              if (selectedLogTab == DevToolsLogTab.stats &&
                  onFetchStats != null)
                OutlinedButton(
                  onPressed: canFetchStats ? onFetchStats : null,
                  child: const Text('Get Stats'),
                ),
              OutlinedButton(
                onPressed: onCopyLogs,
                child: const Text('Copy Logs'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: SelectableText(
                selectedLogs.isEmpty ? 'No logs yet' : selectedLogs.join('\n'),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.4,
                ),
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

  /// 表示中ログをクリップボードへコピーする。
  static Future<void> copyLogs(List<String> selectedLogs) {
    final text = selectedLogs.isEmpty ? 'No logs yet' : selectedLogs.join('\n');
    return Clipboard.setData(ClipboardData(text: text));
  }
}
