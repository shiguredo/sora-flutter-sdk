# `@nodoc` / `@internal` / `@immutable` / class modifier の付与ポリシーを統一する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/fix-annotation-policy
- Polished: 2026-09-07

## 目的

同種の宣言に対して annotation / class modifier の付け方が不揃いで、保守時に判断根拠が読み取れない状態を解消する。方針を `CODEBASE.md` に明文化して既存コードに反映する。

## 現状

以下の不揃いが確認されている:

- `@nodoc` vs 日本語 dartdoc 混在:
  - `SoraConnectionConfig`, `GetUserMediaOptions`, `SoraTimeoutOptions`, `SoraRpcOptions`, `SoraRpcError` のコンストラクタが `/// @nodoc` タグで dartdoc から消える (形式は annotation ではなく dartdoc タグ)
  - `lib/` 全体の `/// @nodoc` は 42 件あり、上記 5 件以外にも event 系・device 系等に分散している
- `@internal` を付ければ済むところに `@nodoc` を使っている:
  - `@nodoc` は生成 dartdoc から外すだけで利用者コードから呼べる
  - ただし公開コンストラクタへの `@internal` 付与は `invalid_use_of_internal_member` 警告の対象になる破壊的変更であり、一律置換はできない
- `@immutable` の有無が data class ごとにまちまち:
  - あり: `AudioInputDevice`, `AudioOutputDevice`, `SoraDisconnectCloseInfo`, `SoraLocalVideoHandle`, `VideoCaptureSettings`, `GetUserMediaOptions`, `SoraRpcOptions`, `VideoInputDevice`, `VideoInputFormat`, `SoraTimeoutOptions`
  - なし: `SoraConnectionConfig`, `ExternalVideoFrame`, `SoraDataChannelEvent`, `SoraLogEvent`, `SoraDataChannelMessage`, `SoraTimelineEvent`, `SoraSignalingEvent`, `SoraRpcError`, `RemoteMediaStreamTrack`, `SoraConnectionErrorDetails`
- `final class` / `sealed class` の使い分け:
  - `SoraConnectionState` / `SoraConnectionEvent` / `SoraDebugEvent` の階層は `sealed` + `final class` で統一
  - `SoraConnectionErrorDetails` は階層外で `final class`、`MediaDevices` は `abstract final class` であり、「独立 data class は modifier 一切なし」ではない

`CODEBASE.md` は存在するが annotation 方針の記載は無い。`0099` (`@internal` 3 件追加)・`0129` (二重付与解消)・`0118` (非変更 view) は個別対応済みであり、本 issue の範囲外とする。`pending/0005` (deep immutable 化保留) との関係では、本 issue は現状の浅い不変性の方針に留め、deep 化には踏み込まない。

## 設計方針

- `CODEBASE.md` に以下の方針を追記する (`0136` のファイル構造に従い、競合する場合は `0136` を優先する):
  1. 公開 data class は `@immutable` + `final class` を原則とする。可変内部 (`Uint8List`, `Map<String, Object?>` 等) を持つ場合 (`ExternalVideoFrame`, `SoraConnectionConfig` 等) は `@immutable` を付けず、その理由を dartdoc に明記する。`final` 付与は継承の有無 (`test/` / `e2e_test_app` / `devtools` からの継承なしを確認) を調査してから判断する。
  2. dartdoc は `///` のみで統一（同一宣言で `///` と `//` を混在させない）。`0095` の 7 箇所と重なる場合は `0095` 完了後に実施する。
  3. 公開コンストラクタの `/// @nodoc` はドキュメント記述に置き換える。`@internal` への置換は破壊的変更になるため行わない。内部限定が真に必要な宣言のみ `@internal` とし、判断基準を明記する。
- 決まったポリシーに沿って既存コードを本 issue のスコープで一気に修正する (小分けしない)。
- 挙動変更なし。annotation / modifier / dartdoc の整理のみ (公開コンストラクタの `@internal` 化のような破壊的変更は含まない)。

## 完了条件

- [ ] `CODEBASE.md` に annotation / class modifier の方針が明記されている。
- [ ] 公開コンストラクタ 5 件 (`SoraConnectionConfig`, `GetUserMediaOptions`, `SoraTimeoutOptions`, `SoraRpcOptions`, `SoraRpcError`) の `/// @nodoc` がドキュメント記述に置換されている (他の `/// @nodoc` 37 件は対象外とする)。
- [ ] 上記列挙の data class に対し、方針に沿って annotation / modifier が付与されている。
- [ ] `flutter analyze` と `flutter test` が成功する。
