/// DevTools 画面で共有する固定選択肢をまとめるモジュール。
///
/// `main.dart` や設定セクションから参照する値のうち、
/// 実行時状態ではない静的な候補定義だけをここに集約する。
class DevToolsConstants {
  /// 映像接続設定で選択できる video codec の候補一覧。
  static const List<String> videoCodecTypeOptions = <String>[
    'VP8',
    'VP9',
    'AV1',
    'H264',
    'H265',
  ];

  /// Simulcast 利用時に選択できる RID の候補一覧。
  static const List<String> simulcastRidOptions = <String>[
    'r0',
    'r1',
    'r2',
    'none',
  ];

  /// 映像送信時に選択できるビットレートの候補一覧。単位は kbps。
  static const List<int> videoBitRateOptions = <int>[
    10,
    30,
    50,
    100,
    300,
    500,
    800,
    1000,
    1500,
    2000,
    2500,
    3000,
    5000,
    10000,
    15000,
  ];

  /// 映像入力設定で選択できる frame rate の候補一覧。単位は fps。
  static const List<int> frameRateOptions = <int>[60, 30, 24, 20, 15, 10, 5];
}
