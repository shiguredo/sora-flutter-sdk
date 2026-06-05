/// MediaStream の共通基底型
///
/// ローカル (`LocalMediaStream`) とリモート (`RemoteMediaStream`) の
/// 両方が実装する。
///
/// W3C 準拠のためクラス名に Sora プレフィックスを付けていない。
/// `flutter_webrtc` 等の他パッケージと名前が衝突する場合は
/// `import 'package:sora_sdk/sora_sdk.dart' as sora;` で回避する。
abstract class MediaStream {
  /// ストリーム ID
  String get id;

  /// ストリームに含まれる全トラックを返す。
  ///
  // W3C Media Capture and Streams の `MediaStream.getTracks()` と
  // 名前をそろえるため、`get` をあえて残している。
  List<MediaStreamTrack> getTracks();
}

/// MediaStreamTrack の共通基底型
///
/// ローカル (`LocalMediaStreamTrack`) とリモート (`RemoteMediaStreamTrack`) の
/// 両方が実装する。
///
/// W3C 準拠のためクラス名に Sora プレフィックスを付けていない。
/// `flutter_webrtc` 等の他パッケージと名前が衝突する場合は
/// `import as` で回避する。
abstract class MediaStreamTrack {
  /// トラック ID
  String get trackId;

  /// トラックの kind ("audio" または "video")
  String get kind;
}
