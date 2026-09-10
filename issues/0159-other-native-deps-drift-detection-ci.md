# `native_deps.json` と `Package.swift` のドリフト検出を CI に追加する

- Created: 2026-09-07
- Completed: {YYYY-MM-DD}
- Branch: feature/add-native-deps-drift-detection-ci
- Polished: 2026-09-10

## 目的

ネイティブ依存の更新忘れによる全プラットフォームのビルド破壊を防ぐこと。

## 現状

- `scripts/native_deps.json` の `libwebrtc_c.version` と `libwebrtc_c.apple_xcframework.checksum` を正本とし、`scripts/update_apple_native_binary.dart` が `ios/sora_sdk/Package.swift` と `macos/sora_sdk/Package.swift` の `libwebrtcCXCFrameworkURL` と `libwebrtcCXCFrameworkChecksum` を書き換える
- このスクリプトは `hook/build.dart` からビルド時に自動実行されるが、書き換え結果はコミットされないため、正本を更新して生成物をコミットし忘れると乖離が残る
- CI にドリフト検出が無い。`.github/workflows/ci.yml` の `build-apple` ジョブ内で検出しようとすると build hook が `Package.swift` を書き換えてしまうため機能しない

## 設計方針

- ドリフト検出は build hook の影響を受けない独立した CI ジョブで行う。
- `scripts/update_apple_native_binary.dart` を実行したうえで `git diff --exit-code -- ios/sora_sdk/Package.swift macos/sora_sdk/Package.swift` により差分の有無を判定し、差分があれば失敗させる。
- 比較対象は `Package.swift` のみとする。`lib/src/sora_sdk_version.g.dart` は別の正本から生成されるため対象外とする。
- 取得方式・`native_deps.json` の内容自体は変えない。

## 完了条件

- [ ] build hook の影響を受けない独立した CI ジョブが追加されている。
- [ ] `native_deps.json` と `Package.swift` の不一致があると CI ジョブが失敗する。
- [ ] 一致している状態では CI ジョブが成功する。
- [ ] `flutter analyze` と関連テストが成功する。

## 対象外

- `linux_ubuntu_22_04_x86_64` の定義削除（`scripts/native_deps.json` の `archives` と `scripts/fetch_native_deps.dart` の `platformConfig`。削除するか保持するかの設計判断が必要なため別 issue とする）。
- 取得失敗時と checksum 不一致時の切り分け手順の文書化（ドキュメントは別途扱う）。
- `third_party/libwebrtc-c` の CI cache の個別除外（cache キーは `scripts/native_deps.json` のハッシュのため、定義変更で自動的に更新され個別操作は不要）。
