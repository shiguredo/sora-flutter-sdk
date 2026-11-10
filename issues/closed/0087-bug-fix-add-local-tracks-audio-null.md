# `_addLocalTracks` が `_config['audio']` の `null` と `true` を同一扱いしている

- Created: 2026-08-27
- Completed: 2026-08-27
- Branch: feature/fix-add-local-tracks-audio-null
- Polished: {YYYY-MM-DD}

## 目的

`WebrtcClient._addLocalTracks` の `_config['audio'] != false` 判定が `null`（未指定）と `true`（明示的に有効）を同一扱いしているため、Sora 側の「audio 未指定 → デフォルト適用」との意図の食い違いを解消する。動作結果としては現状の挙動でも成立するが、Dart 側の意図が読み取れず将来の回帰の温床になる。

## 現状

`lib/src/ffi/webrtc_client.dart` の `WebrtcClient._addLocalTracks` は `_config['audio'] != false` の場合に pending audio track を sender へ追加する。

- `SoraConnection._validateConnectStream`（`lib/src/sora_connection.dart`）側は `audio` が `null` の場合に track 1 本以下を許容しているため、実質的な動作は成立する。
- しかし「audio 未指定」と「audio 明示 true」を Dart 側で unconditional に同一扱いする挙動は、Sora の connect メッセージ仕様で `audio` を送らない場合（サーバー側デフォルト適用）と送る場合の意図と一致しない。
- 意図をコード上で明示していないため、将来 config semantics が変わったときの回帰の原因になる。

## 設計方針

- `_addLocalTracks` の条件を `_config['audio'] == true` に絞る、あるいは現状挙動を保つ場合は「audio 未指定でも pending audio track があれば追加する」意図をコメントで明示する。
- Sora 側仕様との対応関係を明記し、`_validateConnectStream` の許容ルールとの整合を dartdoc に残す。
- 動作変更となる場合は、テストで pending audio track と `audio` 指定の全組み合わせ（`null` / `true` / `false`）を検証する。

## 完了条件

- [ ] `_addLocalTracks` の `audio` 判定が `null` / `true` / `false` の各ケースで意図通り動く。
- [ ] 意図がコード / dartdoc に明示されている。
- [ ] 上記全組み合わせを exercise するユニットテストを追加する。
- [ ] `flutter analyze` と関連テストが成功する。

## 解決方法

polish-issue の本審で、前提となる「意図の食い違い」が成立しないことが判明したため、closed にする。

- Sora のシグナリング仕様（WEBSOCKET_SIGNALING の「配信または視聴メディアの選択」）では「この設定が未指定の場合は、`true` がデフォルトで指定され」ると定義されており、`audio` 未指定と明示 `true` はサーバー側の意図が同一である。
- `WebrtcClient._addLocalTracks` の `_config['audio'] != false` 判定（webrtc_client.dart:1494 行）は、未指定（null）を Sora のデフォルト（true）として扱っており、仕様と整合する。
- 0070（closed）が「audio / video 未指定時のローカル Stream 拒否を修正する」として同一の前提（未指定 = true）で解決済みであり、本 issue の前提は 0070 の解決内容と矛盾する。
- したがってバグは実在せず、実装しても誤った変更（audio 未指定 + ローカル audio track の接続で音声が送信されなくなる）を導入するだけである。
