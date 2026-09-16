# audio / video 未指定時のローカル Stream 拒否を修正する

- Created: 2026-08-25
- Completed: 2026-08-26
- Branch: feature/fix-allow-stream-when-media-unspecified
- Polished: 2026-08-25

## 目的

Sora のシグナリング仕様では、`audio` / `video` を未指定にした場合は `true` として扱われる。

そのため、`audio == null && video == null` の場合でも、送信役割の `connect` でローカル `Stream` を渡せるようにする。

参考: [Sora のシグナリング仕様](https://sora-doc.shiguredo.jp/SIGNALING)

## 現状

`SoraConnection._validateConnectStream` は、以下の 2 つを同じ「メディア無効」状態として扱っている。

- `audio == false && video == false`
- `audio == null && video == null`

このため、`audio` / `video` 未指定で `connect(stream)` を呼び出すと、ローカル `Stream` が拒否される。

一方で、以下の実装は `null` を未指定、つまり Sora のデフォルトを適用する値として扱っている。

- `buildOptionalAudioConnectValue` / `buildOptionalVideoConnectValue` は、追加オプションがなければ `null` を返し、`lib/src/sora_connection_signaling.dart` の `_buildConnectMessage` はキーを追加しない
- `WebrtcClient._addLocalTracks` は、`audio` / `video` が `false` でない場合にローカルトラックを追加する

つまり、ローカル `Stream` の検証だけが Sora のデフォルト仕様と一致していない。

また、README の `sendonly` / `sendrecv` の例は `audio` / `video` を設定せずに `connect(stream)` を呼び出しているため、現在の実装では接続前に失敗する。

`issues/closed/0010-test-add-sendrecv-e2e-coverage.md` で記録された回避策が、現在の `e2e_test_app/integration_test/sendrecv_smoke_e2e_test.dart` に残っており、`video: true` と `audio: false` を明示している。

## 設計方針

- `recvonly` では、従来どおりローカル `Stream` を拒否する
- `audio == false && video == false` では、従来どおりローカル `Stream` を拒否する
- `sendonly` / `sendrecv` で `audio == null && video == null` の場合は、ローカル `Stream` が `null` なら従来どおり受け入れ、ローカル `Stream` が渡された場合も許可して既存のトラック検証へ進める
- `audio == false && video == false` を除き、`audio` / `video` のいずれかを明示した場合の既存の `Stream` 必須判定は維持する
- `audio` / `video` が未指定の場合の既存のトラック検証は維持する
- `connect` のドキュメントコメントを、未指定時は Sora のデフォルトが適用され、ローカル `Stream` の省略と指定の両方が可能である内容へ更新する
- モックやスタブを使わず、実際のメディアと接続を使った回帰テストを追加する

## 完了条件

- `sendonly` / `sendrecv` で `audio` / `video` 未指定の `SoraConnectionConfig` とローカル `Stream` を使って接続できる
- 未指定時に `audio` / `video` が Sora のデフォルト仕様どおりに扱われる
- `audio == null && video == null` でローカル `Stream` を渡さない既存の接続開始も、ローカル `Stream` の妥当性検証で拒否されない
- `audio == false && video == false` の場合は、ローカル `Stream` が従来どおり拒否される
- `recvonly` のローカル `Stream` 拒否が維持される
- `e2e_test_app/integration_test/sendrecv_smoke_e2e_test.dart` がメディア設定を未指定にした状態で、ローカル `Stream` の接続と映像送信を検証する
- 既存のテストおよび E2E テストが成功する

## 解決方法

1. `SoraConnection._validateConnectStream` で、明示的な `false / false` と未指定の `null / null` を分離する
2. `SoraConnection.connect` のドキュメントコメントを更新する
3. `e2e_test_app/integration_test/sendrecv_smoke_e2e_test.dart` の `audio` / `video` を未指定に変更し、実際のローカル `Stream` を使って接続と映像送信を検証する
