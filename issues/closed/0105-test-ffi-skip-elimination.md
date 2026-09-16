# FFI 依存テストの silent pass を廃止する

- Created: 2026-08-27
- Completed: 2026-08-28
- Branch: feature/fix-ffi-test-silent-pass
- Polished: 2026-08-27

## 解決方法

- `test/support/ffi_test_environment.dart` に `prepareFfiTestEnvironment()` を追加し、テスト登録前に FFI 実行環境を同期判定する共通 helper とした。
- `SORA_FFI_TEST_LIBRARY_PATH` が未指定の場合は理由付きで skip し、指定された場合は指定ファイルの欠落・ロード失敗・シンボル解決失敗・factory 生成失敗・`nullptr` を `TestFailure` とした。
- 対象 4 ファイルから 28 箇所の早期 return（`if (!ffiAvailable) return;` / `if (inner == nullptr) return;`）を削除し、23 件の FFI 依存テストへ共通 helper の判定結果（`skip:`）を適用した。
- `.github/workflows/ci.yml` の `build-linux` job で devtools の Linux build 後に `SORA_FFI_TEST_LIBRARY_PATH` と `LD_LIBRARY_PATH` を設定して対象 4 ファイルの `flutter test` を実行し、FFI 依存テストの実行を CI で保証した。
- CI に早期 return パターンの再混入を検出する検査ステップを追加した。
- 検証コマンド: `flutter analyze --fatal-infos lib test`（成功）、`flutter test`（92 件成功、13 件は環境変数未指定による理由付き skip）。


## 目的

libwebrtc-c を利用できない場合に FFI 依存テストが成功扱いになる問題を解消し、CI では全件の実行を必須にする。

## 現状

以下の 4 ファイルに `if (!ffiAvailable) return;` が 25 箇所ある。

- `test/webrtc_client_test.dart`: 12 箇所
- `test/sdp_negotiation_test.dart`: 8 箇所
- `test/sora_data_channel_controller_test.dart`: 2 箇所
- `test/simulcast_video_encoder_factory_test.dart`: 3 箇所

25 箇所の内訳は、テスト本体の 23 箇所と `setUpAll` の 2 箇所である。

さらに `test/simulcast_video_encoder_factory_test.dart` には `if (inner == nullptr) return;` が 3 箇所あり、合計 28 箇所の早期 return 経路がある。

CI の `build-android` job は Linux 用 `libsora_sdk.so` を生成する前に `flutter test` を実行する。`build-linux` job は共有ライブラリを生成するが、package test は実行しない。そのため、現行 CI では FFI 依存テストの実行を保証できない。

## 設計方針

- FFI テスト環境をテスト登録前に同期判定する共通 helper を `test/support/` に追加する。
- `SORA_FFI_TEST_LIBRARY_PATH` が未指定なら、対象テストを理由付きで skip する。
- `SORA_FFI_TEST_LIBRARY_PATH` が指定された場合は skip を許可しない。指定ファイルの欠落、ロード失敗、シンボル解決失敗、factory 生成失敗、`nullptr` は `TestFailure` とする。
- 対象 4 ファイルから 28 箇所の早期 return を削除し、23 件の FFI 依存テストへ共通 helper の判定結果を適用する。
- `build-linux` job で devtools の Linux build 後に以下を設定し、対象 4 ファイルを `flutter test` で実行する。
  - `SORA_FFI_TEST_LIBRARY_PATH`: build 済み `libsora_sdk.so` の絶対パス
  - `LD_LIBRARY_PATH`: `libsora_sdk.so` と依存共有ライブラリを含むディレクトリ
- 対象 4 ファイルに FFI 前提不成立を理由とするテスト本体からの早期 return がないことを CI で検査する。
- 同じテストファイルを変更する 0106、0135 より先に対応する。

## 完了条件

- [ ] 対象 4 ファイルから 28 箇所の早期 return が削除されている。
- [ ] 環境変数未指定時は FFI 依存テストが理由付きで skip される。
- [ ] 環境変数指定時は 23 件の FFI 依存テストが実行され、FFI の準備または初期化に失敗するとテストが失敗する。
- [ ] `build-linux` job が build 済み `libsora_sdk.so` を使って対象 4 ファイルを実行する。
- [ ] FFI 前提不成立による早期 return の再混入を CI で検出できる。
- [ ] `flutter analyze` と全テストが成功する。
