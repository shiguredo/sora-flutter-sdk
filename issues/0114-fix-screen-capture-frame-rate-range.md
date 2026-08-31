# `ScreenCaptureOptions.frameRate` の silent clamp を `RangeError` に変更する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/fix-screen-capture-frame-rate-range
- Polished: 2026-08-27
- Milestone: 2026.1.0

## 目的

`ScreenCaptureOptions` のコンストラクタで `frameRate` の範囲外値を silent に clamp している挙動を、`RangeError` で fail-fast する形に変更する。利用者が指定した値と実際の値が食い違いデバッグを困難にする。

## 現状

`lib/src/sora_screen_capture.dart` の `ScreenCaptureOptions` のコンストラクタは、`frameRate` を `frameRate < 1 ? 1 : (frameRate > 120 ? 120 : frameRate)` として silent に clamp する。`frameRate: 200` を渡すと 120 に丸められる。ユーザーは 200 fps を指定したつもりだが実際は 120。

なお、この clamp は 0069（iOS のアプリ内画面キャプチャ API、2026-08-18 に develop へマージ済み）の設計方針「Sora iOS SDK の `ScreenCaptureSettings.targetFPS` と同様に 1 から 120 へ丸める」と完了条件「入力値が 1 から 120 へ丸められる」により仕様として固定されたものである。

## 設計方針

- `ScreenCaptureOptions` は const コンストラクタを持ち、const コンストラクタの初期化リストでは throw できない。したがって、コンストラクタでの `RangeError` 送出は実装不可能である。代わりに、利用箇所である `MediaDevices.createScreenVideoTrack` の冒頭で `frameRate < 1 || frameRate > 120` を `RangeError.range(frameRate, 1, 120, 'frameRate', ...)` で拒否する。const コンストラクタは維持し、`ScreenCaptureOptions` 自体の clamp は削除して範囲外の値をそのまま保持する。
- clamp を残したい利用者向けのヘルパーは提供しない（本 issue の目的は silent clamp の排除であり、ヘルパー提供は対象外）。
- 範囲値（1〜120）の根拠を dartdoc に明記する。根拠は Sora iOS SDK の `ScreenCaptureSettings.targetFPS` の仕様（「指定できる最大値は 120」）であり、iOS ReplayKit / Android MediaProjection の制約ではない。`createScreenVideoTrack` は iOS 専用のため、Android の制約は根拠として記載しない。
- 0069 は clamp を仕様として実装済みのため、本 issue の実装に合わせて 0069 の完了条件（「入力値が 1 から 120 へ丸められる」）と設計方針（「1 から 120 へ丸める」）を更新する。0069 は open のまま残っているため、本 issue のマージ時に 0069 の記述を修正する。
- 挙動変更となるため、CHANGELOG に CHANGE（後方互換のない変更）として記載する（silent clamp は仕様として実装・検証済みであり、バグ修正の FIX ではない）。
- `createScreenVideoTrack` は冒頭で `Platform.isIOS` チェックにより `UnsupportedError` を先に投げるため、unit test 環境では `RangeError` 検証が `UnsupportedError` にマスクされる。frameRate 検証をテスト可能にするため、`frameRate` の範囲検証ロジックをテスト可能な純粋関数として分離し、`createScreenVideoTrack` から呼ぶ。unit test は純粋関数に `ScreenCaptureOptions` の実インスタンスを渡して検証する（モックやスタブは使わない）。

## 完了条件

- [ ] `MediaDevices.createScreenVideoTrack(ScreenCaptureOptions(frameRate: 200))` が iOS 上で `RangeError` で拒否される。
- [ ] 分離した frameRate 範囲検証の純粋関数が、範囲外の `ScreenCaptureOptions` を `RangeError` で拒否することをユニットテストで検証する（モックやスタブは使わない）。
- [ ] 既存テスト（`test/sora_screen_capture_test.dart` の「フレームレートは 1 から 120 の範囲へ丸める」）を fail-fast に合わせて書き換える。
- [ ] 有効範囲の根拠（Sora iOS SDK の `ScreenCaptureSettings.targetFPS` の仕様）が dartdoc に明記されている。
- [ ] 0069 の完了条件・設計方針が本 issue の変更（fail-fast）と整合するよう更新されている。
- [ ] CHANGELOG に CHANGE として記載されている。
- [ ] `flutter analyze` と関連テストが成功する。
