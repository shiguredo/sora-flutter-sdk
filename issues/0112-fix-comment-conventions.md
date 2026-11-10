# `//` 英語見出しの日本語化と全角半角スペース抜け修正

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/fix-comment-conventions
- Polished: 2026-09-07

## 目的

AGENTS.md「コメントは全て日本語にすること」「全角と半角の間には半角スペースを入れること」に反しているコメント断片を修正する。対象は `//` の英語見出しと、他 issue の範囲外である `sora_timeline_event.dart` の `///` 2 行とする (`0093` は `sora_push_audio.dart` 13 行目のみのため競合しない)。

## 現状

英語の `//` 見出しが以下の 19 行にある:

- `lib/src/ffi/webrtc_client.dart`: 79 (`PeerConnectionFactory / PeerConnection`)、101 (`Audio / Video RtpSender`)、110-118 (`DataChannel (notify)` / `(push)` / `(rpc)` / `(stats)` / `(signaling)` の 5 亜種)、963 (`Stats`)、1255 (`PeerConnectionFactory`)、1268 (`PeerConnection`)、1290 (`ICE Transport Policy`)、1975 (`DataChannel`)
- `lib/src/ffi/bindings.dart`: 3386 (`SDP Semantics`)、3391 (`ICE Transport Types`)、3396 (`SDP Type`)、3400 (`VideoRotation`)、3403 (`PeerConnectionState`)、3420 (`DataChannel DataState`)
- `lib/src/sora_remote_track_manager.dart`: 371 (`Video track attach / detach`)

対象外とする:

- 識別子・キー名のみの注記 (`webrtc_client.dart` 1307 `URL`、1801 `rid`、1813 `active`、1846 `scaleResolutionDownBy`、1859 `maxFramerate`、1868 `scalabilityMode`)。フィールド名の注記のため残す。
- 日本語混じりの行 (例: `DataChannel (カスタムラベル)`、`PeerConnection Observer コールバック`)。
- `0093` の `///` 1 箇所、`0095` の 7 箇所、`0113` の定数側 60-61 行目と 62-63 行目には触れない。

`lib/src/sora_remote_track_manager.dart` の `_connectionIdFromTrackId` / `_requireRemoteConnectionId` の dartdoc (293, 310 行目) に「Track IDから Connection ID を取得する」と書かれており、`ID` と `から` の間に半角スペースが無い。同種パターン (`[A-Za-z0-9](から|まで|へ|を|に|が|は|の|と|で)` + かな漢字) の走査では他に該当が無く、当該 2 件のみが対象である。

`lib/src/sora_timeline_event.dart` の `/// DataChannel ID` (42 行目) / `/// DataChannel label` (45 行目) は `///` だが他 issue の範囲外のため、本 issue で日本語化する (`DataChannel の ID` / `DataChannel のラベル` 相当)。

## 設計方針

- 英語見出しは日本語見出しに置き換える。WebRTC 仕様固有の英字名やコード識別子は残しつつ、日本語で意味付けを添える (`0093` / `0106` と同等の基準)。例:
  - `// Stats` → `// 統計収集 (Stats)`
  - `// DataChannel` → `// DataChannel 操作`
  - `// DataChannel (notify)` → `// 通知用 DataChannel (notify)` (他 4 亜種も同ルール: `// プッシュ通知用 DataChannel (push)`、`// RPC 用 DataChannel (rpc)`、`// 統計用 DataChannel (stats)`、`// シグナリング用 DataChannel (signaling)`)
- 「Track IDから」を「Track ID から」に修正する。
- 日本語化後にスペース抜けが残っていないか再確認する。
- 挙動変更なし。コメント / dartdoc のみの修正。

## 完了条件

- [ ] 上記 19 行の英語見出しが日本語化されている。
- [ ] `Track IDから` 2 件の半角スペース抜けが解消されている。
- [ ] `DataChannel ID` / `DataChannel label` が日本語化されている。
- [ ] `flutter analyze` が成功する。コメントのみの変更のため専用の関連テストはなし。
