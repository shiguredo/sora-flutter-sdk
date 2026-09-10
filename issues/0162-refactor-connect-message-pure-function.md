# connect メッセージ構築を純関数へ切り出して FFI 非依存でテストする

- Created: 2026-09-10
- Completed: {YYYY-MM-DD}
- Branch: feature/refactor-connect-message-pure-function
- Polished: {YYYY-MM-DD}

## 目的

connect メッセージの構築ロジックを FFI 非依存でテストできるようにし、`SORA_FFI_TEST_LIBRARY_PATH` を設定しない通常の `flutter test` でも回帰を検出できるようにする。

## 現状

- connect メッセージの構築は `lib/src/sora_connection_signaling.dart` の `_SoraConnectionSignaling._buildConnectMessage` が担う。`SoraConnection` の private extension メソッドであり、テストから直接呼べない。
- `lib/src/sora_connection.dart` の `SoraConnection.buildConnectMessageForTest` が `@visibleForTesting` で `_buildConnectMessage` を公開しているが、`SoraConnection` の生成には FFI の共有 factory が必要である。
- そのため connect メッセージを検証するテストは `test/sora_connection_test.dart` の FFI 依存 group に置かれ、`SORA_FFI_TEST_LIBRARY_PATH` 未指定の `flutter test` では skip される。実行されるのは `.github/workflows/ci.yml` の Linux FFI job のみである。
- 一方、connect メッセージの `audio` / `video` 値の構築は `lib/src/sora_connect_message.dart` の `buildOptionalAudioConnectValue` / `buildOptionalVideoConnectValue` として純関数に切り出され、`test/sora_connect_message_test.dart` で FFI 非依存にテストされている。

## 設計方針

- `lib/src/sora_connect_message.dart` に connect メッセージ全体を構築する純関数を追加する。環境名（`macos` / `ios` 等）は引数で受け取り、`Platform` に依存させない。
- `_buildConnectMessage` はその純関数へ委譲する。通常接続と redirect が同じ関数を使い続けるようにする。
- 対応するテストを `test/sora_connect_message_test.dart` へ追加し、FFI 非依存にする。
- `SoraConnection.buildConnectMessageForTest` と `test/sora_connection_test.dart` の FFI 依存 connect メッセージ group は、純関数テストへ置き換えたうえで削除する。
- connect メッセージの出力内容は変更しない。既存のキー・値を維持する。
- ソースコード本体・コメント・テスト名に issue 番号を持ち込まない。

## 完了条件

- [ ] `lib/src/sora_connect_message.dart` に connect メッセージ構築の純関数が追加されている。
- [ ] `_buildConnectMessage` がその純関数へ委譲している。
- [ ] `test/sora_connect_message_test.dart` に FFI 非依存の connect メッセージ検証テストが追加されている。
- [ ] `SoraConnection.buildConnectMessageForTest` が削除されている。
- [ ] `test/sora_connection_test.dart` の FFI 依存 connect メッセージ group が削除されている。
- [ ] `SORA_FFI_TEST_LIBRARY_PATH` を指定しない `flutter test` で新しいテストが実行され成功する。
- [ ] connect メッセージの出力内容が変更前と一致する。
- [ ] モックやスタブを使用していない。
- [ ] `flutter analyze` と関連するテストが成功する。
