# camera → external `replaceVideoTrack` 時に `localVideo` Stream から解除を能動通知する

- Created: 2026-08-31
- Completed: {YYYY-MM-DD}
- Branch: feature/add-local-video-release-notification
- Polished: {YYYY-MM-DD}

## 目的

`SoraConnection.replaceVideoTrack` で camera→external に切り替えたとき、
公開 `SoraConnection.localVideo` Stream が何も emit しない silent-drop
契約になっている。この挙動は docstring に明記されているが、SDK 側から
「解除」を能動通知する仕組みがないため、消費者が旧 camera texture id を
保持し続け、`SoraLocalVideoWidget` に stale な texture が渡り続けるリスクが
残る。消費者側が Stream 経由で「external に切り替わった / preview を破棄
すべき」を検出できるようにする。

## 現状

`lib/src/sora_connection.dart` の `_applyVideoCaptureBackend` は external
capture で null を返し、`_emitLocalVideo(int? textureId)` が null で emit
スキップする。これによって公開 Stream に無効値が漏れないという不変条件は
担保できているが、逆方向 (external に切り替わった、または `disconnect()`
された) を消費者に通知する emit が存在しない。

現状の消費側実装:

- `devtools/lib/main.dart` の `_localTextureId` は `prepareForConnect()` /
  `resetAfterDisconnect()` / `_clearLocalPreview()` / role 変更時に明示的に
  クリアされる設計で、camera→external の `replaceVideoTrack` 経路自体を
  持たない (external track 使用時は必ず切断を挟む) ため実害は顕在化しない。
- 3rd-party 消費者が camera→external replace パターンを踏むと、
  `SoraLocalVideoWidget(textureId: _localTextureId)` が旧 camera の
  texture id を保持し続け、実際には停止している camera 映像を UI が
  描画し続ける。

`SoraConnection.replaceVideoTrack` / `SoraConnection.localVideo` の
docstring では「消費者は自力で `SoraConnectionState` などと合わせて破棄する
こと」と明示されているが、消費者に責任を押し付けているだけで SDK 側の
支援がない。

## 設計方針

以下の候補から設計判断する (0147 の textureId semantics 設計と併せて検討)。

- (a) `SoraLocalVideoHandle.textureId` を `int?` に戻し、external 切替や
  disconnect で `SoraLocalVideoHandle(textureId: null)` を emit する。
  消費者は null を「解除」として扱う。
- (b) `localVideo` の型を `Stream<SoraLocalVideoHandle?>` に変え、null を
  「解除」として emit する。
- (c) 別 Stream (`localVideoReleased` など) を追加し、解除イベントだけを
  別経路で通知する。
- (d) 現状維持で docstring だけを強化し、SDK に「消費者向けヘルパ」
  (例: `SoraConnection` のフラグ / メソッドで「今 preview があるか」を
  外部から確認できるように) を追加する。

いずれの選択肢も公開 API 変更を伴うため、破壊的変更範囲・後方互換の扱い・
`CHANGELOG.md` への反映を含めて設計判断を行う。0147 の textureId semantics
設計と整合させること。

## 完了条件

- [ ] 消費者が「external に切り替わった / preview を破棄すべき」を
      Stream 経由で検出できる仕組みが実装されている。
- [ ] `devtools/lib/**` と `e2e_test_app/**` が新しい契約に追随している。
- [ ] `SoraConnection.replaceVideoTrack` / `SoraConnection.localVideo` の
      docstring が新契約と一致している。
- [ ] 破壊的変更を伴う場合、`CHANGELOG.md` に `[CHANGE]` として記載する
      (`CODEBASE.md` の運用に従う)。
- [ ] `flutter analyze` と関連テストが成功する。

## 関連

- `issues/closed/0078-bug-fix-external-video-texture-id-leak.md` (本 issue
  の直接の起点)
- `issues/0147-refactor-texture-id-semantics.md` (textureId 契約の統一)
