# external video track で `textureId = -1` が公開 `localVideo` Stream に emit され Texture Widget が黒画面になる

- Created: 2026-08-27
- Completed: 2026-08-31
- Branch: feature/fix-external-video-texture-id-leak
- Polished: 2026-08-27
- Milestone: 2026.1.0

## 目的

`VideoTrackCaptureType.external` の映像トラックで、`_applyVideoCaptureBackend` が内部 sentinel として返す `-1` が公開 `SoraConnection.localVideo` Stream に漏れ、`SoraLocalVideoWidget` が `Texture(textureId: -1)` を描画してしまうバグを修正する。

## 現状

`lib/src/sora_connection.dart` の `SoraConnection._applyVideoCaptureBackend` は `track.captureType == VideoTrackCaptureType.external` の場合に内部 sentinel `-1` を返す。

- `SoraConnection._connect` は `_currentVideoTrack.captureType != VideoTrackCaptureType.screen` でしかガードしないため、external track でも `_emitLocalVideo(SoraLocalVideoHandle(textureId: -1))` を実行する。
- `SoraConnection._replaceVideoTrackInternal` にも同じ経路がある。
- `lib/src/sora_local_video_handle.dart` の `SoraLocalVideoHandle.textureId` は `int` 型のため、`-1` を型で除去できていない。
- `lib/src/sora_video_widget.dart` の `SoraLocalVideoWidget` は `textureId == null` を placeholder に落とすが、`textureId <= 0` を判定しないため `Texture(textureId: -1)` を Flutter に渡し黒画面が描画される。

## 設計方針

- `SoraLocalVideoHandle.textureId` を `int` から `int?` に変更し、sentinel `-1` を型で除去する（enum ベースの struct への置き換えは公開 API の破壊的変更が大きいため採用しない）。`_applyVideoCaptureBackend` の返り値も `Future<int?>` に変更し、external では `null` を返す。
- `SoraConnection._connect` / `_replaceVideoTrackInternal` は external track で `_emitLocalVideo` 自体をスキップする。external では Flutter Texture ベースのプレビューを持たないため、公開 Stream に流す必要がない。型変更と emit スキップの両方を実装し、`-1` が公開 Stream に漏れる経路を根絶する。
- `SoraLocalVideoWidget` は `textureId == null` に加えて `textureId <= 0` を placeholder に落とす防御を追加する。
- 既存の camera / screen 経路の挙動を変更しない。
- `textureId` の `int` → `int?` は後方互換のない変更のため、CHANGELOG に `[CHANGE]` として記載する（バグ修正の `[FIX]` とは別エントリ）。
- `_applyVideoCaptureBackend` は 0074（catch 削除）と同一関数を対象とする。0074 を先に実装し、本 issue は 0074 の変更を含む develop 上で返り値型（`Future<int?>` 化）と external 分岐を変更する。

## 完了条件

- [x] external video track で `SoraConnection.localVideo` Stream に `-1` が emit されない。
- [x] `SoraLocalVideoWidget` が `-1` を受け取っても黒画面ではなく placeholder を描画する。
- [x] `localVideo` Stream の emit スキップを `@visibleForTesting` ラッパーで検証する（モックやスタブは使わない）。`SoraLocalVideoWidget` は widget テストで検証する。
- [ ] ~~external / camera / screen それぞれ~~ の unit テスト網羅は見送り、camera / screen は既存 e2e で継続カバーする（native FFI 起動を伴うため unit test 化できない）。
- [ ] ~~`textureId` の `int` → `int?` に伴う `e2e_test_app` 更新~~ は不要（下記「## 解決方法」で公開 API の型変更を撤回したため）。
- [ ] ~~CHANGELOG に `[CHANGE]` と `[FIX]` の別エントリ~~ は記載しない（`CODEBASE.md` の「正式リリース前は変更履歴を残さない」運用と、直近 4 件のバグ修正（0073 / 0074 / 0076 / 0077）が CHANGELOG を触っていない実運用に合わせる）。
- [x] `flutter analyze` と関連テストが成功する。

## 解決方法

`lib/src/sora_connection.dart` の `_applyVideoCaptureBackend` を `Future<int?>` に変更し、
external capture では `null` を返すようにした。3 caller の `_emitLocalVideo` 呼び出しは
`_emitLocalVideo(int? textureId)` に集約し、helper 内部で `null` の場合は emit 自体を
スキップする。これにより公開 `SoraConnection.localVideo` Stream に内部 sentinel
（旧実装の `-1`）や無効値が漏れる経路を根絶した。

`lib/src/sora_video_widget.dart` の `SoraLocalVideoWidget.build` に負値ガードを追加し、
呼び出し側から誤って負値が渡っても Flutter Texture ウィジェットに無効な id を渡して
黒画面にならないよう防御した。設計方針では `textureId <= 0` を placeholder としていたが、
Flutter engine の `TextureRegistry` は `0` を有効な texture id として発行する
（本リポジトリの e2e でも `expect(textureId, greaterThanOrEqualTo(0))` で受容している）
ため、実装は `< 0` を採用して `0` は Texture に渡す。

設計方針では公開型 `SoraLocalVideoHandle.textureId` を `int` から `int?` に変更する
案も併記していたが、`_emitLocalVideo(int?)` 側で `null` を emit しないため subscriber は
実行時に `null` を絶対に観測しない。型を `int?` に広げると型と実行時契約が食い違い、
下流の消費者（devtools / 3rd-party）に不要な null 検査を強いる公開 API の破壊的変更に
なるため、`SoraLocalVideoHandle.textureId` の型は `int` のまま維持した。`SoraLocalVideoHandle`
の class docstring に「external の場合は Stream 自体が emit されない」旨と Stream 到達時の
非負保証を明記して契約を確定させた。

`SoraConnection.localVideo` および `SoraConnection.replaceVideoTrack` の docstring に
external track を扱う場合の silent-drop 契約（emit されない、消費者は自力で texture id を
破棄する責任がある）を追記した。

テストは `SoraConnection` に `@visibleForTesting` の `emitLocalVideoForTest(int?)` を追加し、
`null` で emit スキップ、`0` で `textureId=0` のハンドル 1 件が流れることを直接検証する
2 件を `test/sora_connection_test.dart` に追加した（モックやスタブは使わない）。
`SoraLocalVideoWidget` は `test/sora_video_widget_test.dart` に `textureId=-1` で
placeholder、`textureId=0` で Texture が描画されることを widget テストで追加した。

camera / screen 経路の `_applyVideoCaptureBackend` は `startCaptureForConnection` を経由し
実 platform ハンドラを呼び出すため unit test 化が困難で、既存の `e2e_test_app` でカバーする。
`CHANGELOG.md` は `CODEBASE.md` の「正式リリース前は変更履歴を残さない」運用と直近 4 件
（0073 / 0074 / 0076 / 0077）の実運用に合わせて触っていない。
