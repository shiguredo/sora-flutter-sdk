# `sdp_negotiation_test.dart` の SDP race 再現テストで `createSessionDescription` が nullptr を返して失敗する

- Created: 2026-08-30
- Branch: feature/fix-sdp-negotiation-tests-null-pointer
- Polished: 2026-08-30
- Completed: 2026-08-30

## 目的

Linux CI の `Run FFI-dependent package tests` step で、`test/sdp_negotiation_test.dart` の `SdpNegotiationCallbacks` race 再現テスト 4 件が `Expected: not Pointer<Never>:<Pointer: address=0x0>` の assertion で失敗している。この失敗を解消し、Linux CI の FFI テスト step を green に近づける。

同 step で観測されている他系統は本 issue のスコープ外で、別 issue で扱う。系統 A-2（`webrtc_client_test.dart` の getStats 系 3 件、`Bad state: PeerConnection closed during getStats.` の unhandled StateError）は別 issue として起票する。系統 B（`AudioDeviceModule init failed`）は 0143、系統 C（`Binding has not yet been initialized`）は 0141 で扱う。

## 現状

`Build Linux` job の `Run FFI-dependent package tests` step で以下 4 件が失敗している（run 例: `33297433461` の Build Linux job、`gh run view 33297433461 --repo shiguredo/sora-flutter-sdk --log-failed --job 99219408228` で確認）。

- `SdpNegotiationCallbacks race 再現 offer -> offer: old emits nothing, new emits answer`
- `SdpNegotiationCallbacks race 再現 re-offer -> re-offer: old re-answer suppressed, new emits re-answer`
- `SdpNegotiationCallbacks race 再現 offer -> re-offer: late answer from offer suppressed`
- `SdpNegotiationCallbacks race 再現 re-offer -> offer: late re-answer from re-offer suppressed`

失敗メッセージ:
```
Expected: not Pointer<Never>:<Pointer: address=0x0>
  Actual: Pointer<Never>:<Pointer: address=0x0>
```

`grep -rn 'isNot(nullptr)' test/` の結果は 1 箇所のみで、発生源は `test/sdp_negotiation_test.dart:129` の `_createAnswerDescription` ヘルパ内 `expect(desc, isNot(nullptr))`。呼び出し元は同ファイル L124 の `lib.createSessionDescription(...)`。

4 テストいずれも `_CallbackHarness` を A / B の 2 つ生成し、A は `a.callbacks.cancel()` 済みにする（L153, L178, L204, L226）。`callbacks.onSetRemoteDescriptionComplete` は冒頭で `if (_cancelled) return;`（`lib/src/ffi/callback_handlers.dart:152`）と早期リターンするため、A 側の `completeSetRemoteDescriptionWithAnswer(...)` は `_CallbackHarness._createAnswer` に到達せず `createSessionDescription` を呼ばない。実際にパーサへ到達するのは B（非 cancel）側の SDP のみで、B が渡すのは:

- Test 1: `'sdp-b'`（L163）
- Test 2: `'sdp-b'`（L187）
- Test 3: `'sdp-reoffer'`（L212）
- Test 4: `'sdp-offer'`（L234）

いずれも `v=0` などの必須ヘッダを持たない短い文字列で、libwebrtc-c のパーサが不正 SDP に対して nullptr を返す仕様に該当する可能性が高い。同 group 内で `_createAnswerDescription` に有効な SDP を渡す `cancel 後の onCreateAnswerSuccess は signaling を送出しない`（L294）と `_pcRef が null の onCreateAnswerSuccess は安全に終了する`（L311）は `'v=0\r\no=- 1 1 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\n'`（L302, L318）を渡して pass しており、SDP の形式差が原因である強い手がかり。

## 経緯

これらのテスト自体は commit `d132596 0105 FFI 依存テストの silent pass を廃止する` より前から存在していたが、0105 より前は `SORA_FFI_TEST_LIBRARY_PATH` 未指定で silent pass していたため、CI では実際に走っていなかった。0105 で CI 上でも FFI ライブラリをロードして実行するようになり、初めて実行される予定だった CI（`33141722842`）は commit `d290330 0069 VideoTrackCaptureType と captureType getter を公開 API から撤回する` に起因する analyze 段階の失敗で `Run FFI-dependent package tests` step まで到達せず、この失敗は今回（`33297433461`）初めて観測された。

## 設計方針

発生源は `test/sdp_negotiation_test.dart:129` の `_createAnswerDescription` 内 `expect(desc, isNot(nullptr))` の 1 箇所に確定している。呼び出し元は `LibWebrtcC.createSessionDescription()`。実際にパーサへ到達するのは B（非 cancel）側の SDP のみで、いずれも `v=0` などの必須ヘッダを持たない短い文字列である（「## 現状」参照）。

修正候補は以下の 3 つ。同 group 内で pass している L294 / L311 のテストが有効 SDP `'v=0\r\no=- 1 1 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\n'` を使っている実例に照らすと、テスト側の SDP を有効なものに差し替える候補 1 が最短かつ副作用が小さい。

- **候補 1: テスト側で有効な SDP を渡す（推奨）**
  - 4 テストの B 側呼び出しを `'sdp-b'` / `'sdp-reoffer'` / `'sdp-offer'` から、L302 / L318 と同じ有効な最小 SDP に差し替える。
  - race 再現の意図（A / B 2 世代の callback の順序制御）を損なわず、libwebrtc-c のパーサに拒否されないため Linux / macOS 双方で通る見込み。
  - assertion で `spyB.signalings.single['sdp']` を検証している（L167, L191, L217, L239）ため、差し替え後の SDP 文字列に合わせて期待値も同じ有効 SDP に更新する。
  - 「シグナリングメッセージに載る SDP は上位で加工されず透過的にペイロードされる」という現テストの前提を維持できる。
- **候補 2: `_createAnswerDescription` の assertion を撤去する**
  - `expect(desc, isNot(nullptr))` を撤去し nullptr でも継続する。ただし race 再現テストは以降で `spyB.signalings.single['sdp']` を検証しており、nullptr のまま進めると `onCreateAnswerSuccess` 側で別の失敗（NPE 相当）になる可能性が高い。有効 SDP を用意しない限りテスト自体が成立しないため、候補 1 の代替にはならない。
- **候補 3: `createSessionDescription` の失敗を上位で握り潰す**
  - production 側の実装で nullptr を握り潰す。本番挙動を変えるためテスト起因の症状の対応としては対象外とする。

## 完了条件

- [ ] `SORA_FFI_TEST_LIBRARY_PATH` を設定した状態で 4 テストをローカル（macOS）で走らせ、Linux CI と同じく `Expected: not Pointer<Never>` で失敗することを確認する
- [ ] 候補 1 を採用してテスト側の SDP を有効な最小 SDP に差し替え、`spyB.signalings.single['sdp']` の期待値も差し替え後の SDP に同期させる。他候補を採用する場合は根拠を PR / コミットメッセージに記録する
- [ ] `SORA_FFI_TEST_LIBRARY_PATH` を設定した状態で対象 4 テストがすべて pass する
- [ ] Linux CI の `Run FFI-dependent package tests` step で `Expected: not Pointer<Never>` の 4 件失敗が消えている
- [ ] 系統 A-2（別 issue）/ 系統 B（0143）/ 系統 C（0141）に影響しないことを確認する

## 解決方法

`test/sdp_negotiation_test.dart` を候補 1 の方針で修正した。

- ファイル冒頭に `_validMinimalSdp = 'v=0\r\no=- 1 1 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\n'` を top-level private const として追加した。libwebrtc の `SdpSerialize` は `o=` 行の session_id / session_version を parsed 値のまま返し、他の要素は `kSessionOriginUsername` / `kSessionOriginNettype` / `kSessionOriginAddrtype` / `kSessionOriginAddress` / `kSessionName` / `kTimeDescription` の 6 定数で組み立て直す実装 (`webrtc/api/webrtc_sdp.cc`)。この SDP は上記 6 定数の値と一致するように選んであり、parse → serialize の round-trip がバイト一致 identity になる。負債として、6 定数のいずれかが将来変わると完全一致 assertion が破れる旨をコメントで残した。
- race 再現 4 テスト（`offer -> offer` / `re-offer -> re-offer` / `offer -> re-offer` / `re-offer -> offer`）の B 側 `completeSetRemoteDescriptionWithAnswer('sdp-b' / 'sdp-reoffer' / 'sdp-offer')` を `_validMinimalSdp` に統一し、対応する `expect(spyB.signalings.single['sdp'], ...)` の期待値も同期した。
- A 側 (`a.callbacks.cancel()` 済み) の `completeSetRemoteDescriptionWithAnswer('sdp-a' / 'sdp-offer' / 'sdp-reoffer')` はそのまま残した。cancel 済みのため `SdpNegotiationCallbacks.onSetRemoteDescriptionComplete` の `if (_cancelled) return;` で早期 return し、`_createAnswer` に到達せず parser を通らないため、不正 SDP のまま無害。scenario ラベルとしての可読性を優先した。
- 同 group 内の既存 pass テスト `cancel 後の onCreateAnswerSuccess は signaling を送出しない` と `_pcRef が null の onCreateAnswerSuccess は安全に終了する` で使われていた同一のインライン SDP リテラルも `_validMinimalSdp` に置き換え、6 箇所を単一定数へ集約した。
- 候補 2 (`_createAnswerDescription` の `expect(desc, isNot(nullptr))` 撤去) は `spyB.signalings.single['sdp']` 検証が nullptr 経路で成立しなくなるため採用しない。候補 3 (`createSessionDescription` の失敗を上位で握り潰す) は本番の SDP 生成挙動を変えるため採用しない。
