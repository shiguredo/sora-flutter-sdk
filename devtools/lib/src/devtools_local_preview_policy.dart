// Connect 設定変更時に local preview を破棄してよいかを判定する。
bool shouldClearLocalPreviewForConnectAudioChange({
  required bool hasRetainedConnection,
  required bool nextConnectAudio,
  required bool connectVideo,
}) {
  return !hasRetainedConnection && !nextConnectAudio && !connectVideo;
}

// Connect Video は接続オブジェクトを保持していない接続前状態だけ preview を破棄する。
bool shouldClearLocalPreviewForConnectVideoChange({
  required bool hasRetainedConnection,
}) {
  return !hasRetainedConnection;
}
