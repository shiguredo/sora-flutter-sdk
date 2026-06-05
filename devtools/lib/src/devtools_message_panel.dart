/// DataChannel メッセージングの送受信 UI を提供するパネル。
library;

import 'package:flutter/material.dart';

import 'devtools_models.dart';

class DevToolsMessagePanel extends StatefulWidget {
  const DevToolsMessagePanel({
    super.key,
    required this.label,
    required this.messages,
    required this.sendEnabled,
    required this.onSend,
  });

  final String? label;
  final List<DevToolsMessageEntry> messages;
  final bool sendEnabled;
  final void Function(String text) onSend;

  @override
  State<DevToolsMessagePanel> createState() => _DevToolsMessagePanelState();
}

class _DevToolsMessagePanelState extends State<DevToolsMessagePanel> {
  late final TextEditingController _messageController;

  @override
  void initState() {
    super.initState();
    _messageController = TextEditingController();
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  void _send() {
    final text = _messageController.text.trim();
    if (text.isNotEmpty) {
      widget.onSend(text);
      _messageController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.label;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                Text(
                  'Label: ',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _messageController,
                  decoration: const InputDecoration(
                    labelText: 'Message',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  enabled: widget.sendEnabled,
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: widget.sendEnabled ? _send : null,
                child: const Text('Send'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: widget.messages.isEmpty
              ? const Center(child: Text('No messages'))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: widget.messages.length,
                  itemBuilder: (context, index) {
                    final entry = widget.messages[index];
                    return _MessageTile(entry: entry);
                  },
                ),
        ),
      ],
    );
  }
}

class _MessageTile extends StatelessWidget {
  const _MessageTile({required this.entry});

  final DevToolsMessageEntry entry;

  @override
  Widget build(BuildContext context) {
    final time =
        '${entry.timestamp.hour.toString().padLeft(2, '0')}:'
        '${entry.timestamp.minute.toString().padLeft(2, '0')}:'
        '${entry.timestamp.second.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              time,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ),
          SizedBox(
            width: 60,
            child: Text(
              entry.isSent ? 'SENT' : 'RECV',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: entry.isSent
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.secondary,
              ),
            ),
          ),
          Container(
            constraints: const BoxConstraints(maxWidth: 80),
            child: Text(
              entry.label,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.outline,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              entry.text,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
