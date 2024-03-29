// 接続設定

// 以下の lint ルールを無視する
// ignore_for_file: avoid_classes_with_only_static_members
// ignore_for_file: unnecessary_nullable_for_final_variable_declarations

class Environment {

  static const String flutterVersion = '3.3.10';

  static final List<Uri> urlCandidates = [
    Uri.parse('wss://sora.example.com/signaling')
  ];

  static const String channelId = 'sora';

  static const dynamic signalingMetadata = null;
}
