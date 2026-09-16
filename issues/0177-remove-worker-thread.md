# webrtc-rs の worker_thread 削除に追随する

- Created: 2026-09-15
- Completed: {YYYY-MM-DD}
- Branch: feature/remove-worker-thread
- Polished: {YYYY-MM-DD}

## 目的

libwebrtc の issue 558821261「Deprecate and remove PeerConnectionFactoryDependencies::worker_thread」で `PeerConnectionFactoryDependencies::worker_thread` と `PeerConnectionFactoryInterface::worker_thread()` が削除される。削除系 CL (499302 / 501640 / 501720 / 502000 / 502500 / 502860 / 502940 / 502960) はレビュー中である。

本リポジトリは libwebrtc を直接使わず、shiguredo/webrtc-rs が提供する C API (libwebrtc_c) のリリース済みバイナリを `scripts/native_deps.json` で pin して使っている。webrtc-rs が 558821261 を実装した libwebrtc に追随して C API から `set_worker_thread` を削除すると、現行のバインディングと `libwebrtc_c_api.ldflags` が解決できなくなる。`issues/0176-refactor-unify-worker-thread.md` (方針 1) で専用 worker thread は使わなくなるが、C API の参照が残るため、pin を更新するのと同じ変更で参照を全て削除する。

## 現状

- 方針 1 の後も C API の `webrtc_PeerConnectionFactoryDependencies_set_worker_thread` を参照する箇所が残る。
  - `lib/src/ffi/bindings.dart` の手書きバインディング `pcFactoryDependenciesSetWorkerThread`
  - `android/src/main/cpp/libwebrtc_c_api.ldflags` と `linux/libwebrtc_c_api.ldflags` の `-Wl,--undefined=webrtc_PeerConnectionFactoryDependencies_set_worker_thread` (dart:ffi が実行時にシンボルを解決するため、リンカから消えないように列挙している)
- 方針 1 で `pcFactoryDependenciesSetWorkerThread` に network thread を渡している `_ensureSharedFactory()` の呼び出しも本 issue で削除する。
- 前提条件: webrtc-rs が 558821261 を実装した libwebrtc に追随し、C API から `set_worker_thread` を削除してリリースしていること。現時点ではそのような `libwebrtc_c` は存在しないため着手できない。
- 現在の pin は `scripts/native_deps.json` の `libwebrtc_c` が `0.150.3`、`webrtc` が `m150.7871.3.1` である。
- iOS / macOS の `ios/sora_sdk/Package.swift` と `macos/sora_sdk/Package.swift` は `libwebrtc_c` の XCFramework を参照している。`lib/src/sora_sdk_version.g.dart` は `libwebrtc_c` のバージョンを表示している。

## 設計方針

- `scripts/native_deps.json` の `libwebrtc_c` のバージョンと checksum、`webrtc` のバージョンを更新し、Apple 側は `scripts/update_apple_native_binary.dart` で `Package.swift` を同期する。`lib/src/sora_sdk_version.g.dart` は `scripts/generate_sdk_version.dart` で更新する。
- 同じ変更で `lib/src/ffi/bindings.dart` の `pcFactoryDependenciesSetWorkerThread` と、`android/src/main/cpp/libwebrtc_c_api.ldflags` / `linux/libwebrtc_c_api.ldflags` の該当行を削除する。
- バインディングを残したまま C API が削除されると、`late final` の lookup が初回アクセス時に `Symbol not found` で失敗する。`libwebrtc_c_api.ldflags` の該当行を残したまま C API が削除されると Android / Linux のリンクが失敗する。このため pin の更新と削除は同時に行う必要がある。
- `libwebrtc_c` の更新に C API の他の変更が含まれる場合は、`lib/src/ffi/bindings.dart` とその呼び出し側を release の内容に合わせて追従する。

## 完了条件

- [ ] `webrtc_PeerConnectionFactoryDependencies_set_worker_thread` と `pcFactoryDependenciesSetWorkerThread` の参照がリポジトリ内で 0 件になっている。
- [ ] `flutter analyze` と `flutter test` が成功する。
- [ ] Android と Linux のビルドが成功する。
- [ ] macOS の E2E で接続できることを確認する。
- [ ] モックやスタブを使用していない。
- [ ] `CHANGELOG.md` への記載は正式リリース前のため行わない (`CODEBASE.md` の「正式リリース前」節に従う)。正式リリース確定時に追記する。

## 関連

- `issues/0176-refactor-unify-worker-thread.md` (方針 1。専用 worker thread をやめて network thread に統一する。先にマージされていること)
- `issues/closed/0154-update-webrtc-build-to-m150-latest.md` (native 依存の pin 更新手順)
