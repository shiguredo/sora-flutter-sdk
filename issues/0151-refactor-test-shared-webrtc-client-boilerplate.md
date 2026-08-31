# FFI 依存テスト group の `late WebrtcClient wc;` 実効ゼロパターンを整理する

- Created: 2026-08-31
- Completed: {YYYY-MM-DD}
- Branch: feature/refactor-test-shared-webrtc-client-boilerplate
- Polished: {YYYY-MM-DD}

## 目的

FFI 依存テスト group が繰り返している `late WebrtcClient wc; setUpAll(() {
wc = WebrtcClient.create(...); }); tearDownAll(() { wc.dispose(); });`
パターンが実質的に何もしていない (`WebrtcClient.dispose()` は共有 factory
を解放しない、`wc` はテスト本体で参照されない) 状態を整理し、意図が
コードで正しく伝わるようにする。

## 現状

以下の複数 group で同じ boilerplate が繰り返されている。

- `test/sora_media_stream_test.dart` の複数 group (LocalMediaStream の cache
  検証 group 群、`LocalVideoTrack.dispose の非同期契約 (FFI)` group)
- `test/sora_connection_test.dart` の複数 group

各 group で:

- `WebrtcClient.create(...)` は per-client の native client を生成する
  だけで、共有 factory の lazy 初期化 (`WebrtcClient.sharedFactory` getter
  経由) は行わない (`lib/src/ffi/webrtc_client.dart` の `create` と
  `_ensureSharedFactory` を参照)。
- `late WebrtcClient wc;` の `wc` はどの test 本体でも参照されていない。
- `tearDownAll` の `wc.dispose()` は per-client のみ解放し、共有 factory /
  ADM / thread は残る (`issues/0150-...md` 参照)。

つまり `wc = WebrtcClient.create(...)` は「共有 factory を事前に用意する」
意図で書かれているが、実際にはその効果はなく、共有 factory は
`MediaDevices.createExternalVideoTrack()` などの初回呼び出しで lazy 生成
される。setUpAll のコメントも実装と食い違っており、読者が混乱する。

## 設計方針

以下から採用する方針を判断する。

- (a) `late WebrtcClient wc;` パターンを削除し、共有 factory が lazy 生成
  される事実を setUp コメントに 1 行残す。テスト本体の意図が変わらないこと
  を確認する。
- (b) `wc = WebrtcClient.create(...)` の代わりに `WebrtcClient.sharedFactory;`
  を叩いて共有 factory を事前初期化する形に統一する (元々の意図がこれ
  だった可能性)。
- (c) test/support/ 配下に `setupSharedWebrtcForTest()` のような helper を
  用意して、group 側の boilerplate を 1 行に減らす。

0150 で `WebrtcClient.dispose()` の設計方針が確定した後に着手すると整合性が
取りやすい。

## 完了条件

- [ ] FFI 依存テスト group から実効ゼロの boilerplate が整理されている
      (削除 / 意図に合った初期化への差し替え / helper 抽出 のいずれか)。
- [ ] setUpAll / tearDownAll のコメントが実装と一致している。
- [ ] 既存テストの挙動が変わらないことを確認する (skip 条件と実行結果が
      unchanged)。
- [ ] `flutter analyze` と関連テストが成功する。

## 関連

- `issues/0150-refactor-webrtc-client-test-teardown-shared-factory-leak.md`
  (先に方針決定するのが望ましい)
- `issues/closed/0080-bug-fix-local-video-track-dispose-sync-throw.md`
  (本 issue の起点)
