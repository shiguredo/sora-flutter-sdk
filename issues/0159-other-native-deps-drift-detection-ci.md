# `native_deps.json` と `Package.swift` のドリフト検出を CI に追加する

- Created: 2026-09-07
- Completed: {YYYY-MM-DD}
- Branch: feature/add-native-deps-drift-detection-ci
- Polished: {YYYY-MM-DD}

## 目的

ネイティブ依存の更新忘れによる全プラットフォームのビルド破壊を防ぐこと。

## 現状

`scripts/native_deps.json` の `libwebrtc_c.version` と `libwebrtc_c.apple_xcframework` の `checksum` を正本とし、`scripts/update_apple_native_binary.dart` で `ios/sora_sdk/Package.swift` と `macos/sora_sdk/Package.swift` の URL と checksum へ手動同期する運用である。CI にドリフト検出がなく、スクリプト実行忘れが起こる。また同ファイルに `linux_ubuntu_22_04_x86_64` が残存する一方、CI と `docs/LINUX.md` は 24.04 のみであり、旧配布物の保持方針が不明である。

## 設計方針

- `native_deps.json` を正本とし、`Package.swift` との一致を検査する CI ジョブを追加する。
- 旧配布物の要否を決定し、不要なら定義と `third_party/libwebrtc-c` の cache 対象から外す。
- 取得失敗時と checksum 不一致時の切り分け手順を文書化する範囲に絞り、取得方式自体は変えない。

## 完了条件

- [ ] `native_deps.json` と `Package.swift` の不一致が CI で検出される。
- [ ] `linux_ubuntu_22_04` 残存の要否が決定し、定義が現状と一致する。
- [ ] `flutter analyze` と関連テストが成功する。
