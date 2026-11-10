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
    required this.sendGuidance,
    required this.onSend,
  });

  final String? label;
  final List<DevToolsMessageEntry> messages;
  final bool sendEnabled;
  final String? sendGuidance;
  final void Function(String text) onSend;

  @override
  State<DevToolsMessagePanel> createState() => _DevToolsMessagePanelState();
}

class _DevToolsMessagePanelState extends State<DevToolsMessagePanel> {
  late final TextEditingController _messageController;
  late final ScrollController _scrollController;
  bool _followsLatest = true;
  late int _previousMessageCount;

  @override
  void initState() {
    super.initState();
    _messageController = TextEditingController();
    _scrollController = ScrollController()..addListener(_handleScroll);
    _previousMessageCount = widget.messages.length;
  }

  @override
  void didUpdateWidget(covariant DevToolsMessagePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final hasNewMessage = widget.messages.length > _previousMessageCount;
    _previousMessageCount = widget.messages.length;
    if (hasNewMessage && _followsLatest) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToLatest());
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  // 末尾付近にいる間だけ、新着メッセージへの追従を継続する。
  void _handleScroll() {
    if (!_scrollController.hasClients) {
      return;
    }
    final next =
        _scrollController.position.maxScrollExtent -
            _scrollController.position.pixels <=
        48;
    if (next != _followsLatest) {
      setState(() {
        _followsLatest = next;
      });
    }
  }

  // メッセージ一覧の末尾へ移動する。
  void _scrollToLatest() {
    if (!mounted || !_scrollController.hasClients) {
      return;
    }
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
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
        if (widget.sendGuidance case final guidance?)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(guidance)),
              ],
            ),
          ),
        const Divider(height: 1),
        Expanded(
          child: widget.messages.isEmpty
              ? const Center(child: Text('No messages'))
              : ListView.builder(
                  controller: _scrollController,
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
