# camera → external `replaceVideoTrack` 時に解除を別 Stream で能動通知する

- Created: 2026-08-31
- Completed: {YYYY-MM-DD}
- Branch: feature/add-local-video-release-notification
- Polished: 2026-09-07

## 目的

`SoraConnection.replaceVideoTrack` で camera→external に切り替えたとき、
公開 `SoraConnection.localVideo` Stream が何も emit しない silent-drop
契約になっている。この挙動は docstring に明記されているが、SDK 側から
「解除」を能動通知する仕組みがないため、消費者が旧 camera texture id を
保持し続けるリスクが残る。解除通知専用の別 Stream を追加し、消費者が
preview 破棄を検出できるようにする。

## 現状

`lib/src/sora_connection.dart` の `_applyVideoCaptureBackend` は external
capture で null を返し、`_emitLocalVideo(int? textureId)` が null で emit
スキップする。これによって公開 Stream に無効値が漏れないという不変条件は
担保できているが、external への切替を消費者に通知する emit が存在しない。

`disconnect()` については `SoraConnectionState` 遷移で検出可能なため、本 issue の対象外とする。

現状の消費側実装:

- `devtools` は camera→external の `replaceVideoTrack` 経路自体を持たない (external track 使用時は切断を挟む) ため実害は顕在化しない。よって `devtools` / `e2e_test_app` の追随は不要とする。
- 3rd-party 消費者が camera→external replace パターンを踏むと、
  `SoraLocalVideoWidget(textureId: _localTextureId)` が旧 camera の
  texture id を保持し続ける可能性がある (推論であり再現報告は無い)。

## 設計方針

- 解除通知専用の別 Stream (例: `localVideoReleased`) を追加し、camera→external 切替時に解除イベントを emit する。
- 本案は `SoraLocalVideoHandle.textureId` の `int` 契約を変えず、`0078` の却下理由 (`int?` 拡大の破壊性) と衝突しない。`Stream<Handle?>` 化案と `int?` 化案は取らない。
- `0147` の textureId 契約決定に依存しないため、`0147` の完了を待たず単独で実施する。
- `0111` の結合点 (`_emitLocalVideo` の null skip) は変更しない。実装時は rebase で競合を整理する。
- `0146` の `==` / `hashCode` 設計に影響しない (`Handle` 契約不変のため)。
- 後方互換がある追加 (`[ADD]` 相当) であり破壊的変更ではない。正式リリース前のため `CHANGELOG.md` には記載しない (`CODEBASE.md` の運用に従う)。

## 完了条件

- [ ] 解除通知専用の別 Stream が追加され、camera→external 切替時に emit される。
- [ ] `SoraConnection.replaceVideoTrack` / `SoraConnection.localVideo` の
      docstring が新契約と一致している。
- [ ] `flutter analyze` と関連テストが成功する。

## 関連

- `issues/closed/0078-bug-fix-external-video-texture-id-leak.md` (本 issue
  の直接の起点)
- `issues/pending/0147-refactor-texture-id-semantics.md` (textureId 契約の統一。本 issue は依存しない)
