# `@nodoc` / `@internal` / `@immutable` / class modifier の付与ポリシーを統一する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/fix-annotation-policy
- Polished: {YYYY-MM-DD}

## 目的

同種の宣言に対して annotation / class modifier の付け方が不揃いで、保守時に判断根拠が読み取れない状態を解消する。方針を統一して既存コードに反映する。

## 現状

以下の不揃いが確認されている:

- `@nodoc` vs 日本語 dartdoc 混在:
  - `SoraConnectionConfig`, `GetUserMediaOptions`, `SoraTimeoutOptions`, `SoraRpcOptions`, `SoraRpcError` のコンストラクタが `@nodoc` で dartdoc から消える
  - `ScreenCaptureOptions` は日本語 dartdoc を持つ
- `@internal` を付ければ済むところに `@nodoc` を使っている:
  - `@nodoc` は生成 dartdoc から外すだけで利用者コードから呼べる
  - 内部限定にしたいなら `@internal`（`package:meta`）または private コンストラクタ + factory を使うべき
- `@immutable` の有無が data class ごとにまちまち:
  - あり: `AudioInputDevice`, `AudioOutputDevice`, `SoraDisconnectCloseInfo`, `SoraLocalVideoHandle`, `VideoCaptureSettings`, `GetUserMediaOptions`, `SoraRpcOptions`, `ScreenCaptureOptions`, `VideoInputDevice`, `VideoInputFormat`, `SoraTimeoutOptions`
  - なし: `SoraConnectionConfig`, `ExternalVideoFrame`, `SoraDataChannelEvent`, `SoraLogEvent`, `SoraDataChannelMessage`, `SoraTimelineEvent`, `SoraSignalingEvent`, `SoraRpcError`, `RemoteMediaStreamTrack`
- `final class` / `sealed class` の使い分け:
  - `SoraConnectionState` / `SoraConnectionEvent` / `SoraDebugEvent` の階層は `sealed` + `final class` で統一
  - 独立 data class は modifier 一切なし

これらの根拠がどこにも文書化されていない。

## 設計方針

- `CODEBASE.md`（未作成 → 別 issue で作成予定）に以下の方針を明文化する:
  1. 公開 data class は `@immutable` + `final class`。可変内部（`Uint8List`, `Map<String, Object?>` 等）を持つ場合は `@immutable` を付けず、その理由を dartdoc に明記する。
  2. dartdoc は `///` のみで統一（同一宣言で `///` と `//` を混在させない）。
  3. コンストラクタで `@nodoc` は使わない。`@internal` またはドキュメント記述で扱う。
- 決まったポリシーに沿って既存コードを一括修正する。範囲は大きいので、修正は本 issue のスコープで一気にやるか、data class の分類ごとに小分けするかは判断する。
- 挙動変更なし。annotation / modifier / dartdoc の整理のみ。

## 完了条件

- [ ] `CODEBASE.md` に annotation / class modifier の方針が明記されている。
- [ ] 既存の全 data class に対し、方針に沿って annotation / modifier が付与されている。
- [ ] `@nodoc` から `@internal` またはドキュメントへの置き換えが完了している。
- [ ] `flutter analyze` と関連テストが成功する。
