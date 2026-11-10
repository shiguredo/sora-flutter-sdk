# Android JNI に HWAddressSanitizer / UndefinedBehaviorSanitizer ビルドオプションを追加する

- Priority: Low
- Created: 2026-06-02
- Completed: 2026-07-14
- Model: Opus 4.8
- Branch: feature/update-android-jni-sanitizers
- Polished: 2026-06-05

## 目的

`android/src/main/cpp/jni_onload.c` は、手動の参照カウント、`malloc` / `free`、JNI 参照管理を多用する。

Android JNI の use-after-free、二重解放、境界外アクセス、signed integer overflow を実機で検出できるように、HWAddressSanitizer（HWASan）と UndefinedBehaviorSanitizer（UBSan）をオプトインで有効化する。

## 優先度根拠

- Low。通常機能には影響しない開発支援だが、JNI ブリッジのメモリー安全性を実機で検証できる

## 対応前の状態

- CMake と Gradle には ASan / UBSan のビルドオプションだけが実装済みだった
- ASan は Android ではサポートを終了しており、Android NDK は HWASan を推奨している
- サニタイザを有効化した CMake cache が次のビルドへ残り、通常ビルドへ計装が混入する可能性があった
- DevTools にサニタイザの実行時設定がなく、実機で起動できることを確認していなかった
- Android のビルド手順とサニタイザの検証手順を記載する `docs/ANDROID.md` が存在しなかった

## 設計方針

1. Android NDK がサポートを終了した ASan を HWASan に置き換える
2. Gradle から CMake へ HWASan / UBSan の `ON` と `OFF` を毎回明示し、CMake cache の状態に依存させない
3. `-Psora.hwasan=true` の debug ビルドだけ DevTools APK に `wrap.sh` を組み込み、`LD_HWASAN=1` を設定する
4. UBSan は追加ランタイムが不要な signed integer overflow の trap モードを使用する
5. 既定では両方を無効にし、通常ビルドとリリースビルドへ影響させない
6. Android の通常ビルド、HWASan、UBSan の手順と制約を `docs/ANDROID.md` に記載する

## 完了条件

- `-Psora.hwasan=true` で HWASan を計装した `libsora_sdk.so` をビルドできる
- HWASan 版 DevTools APK が Android 14 以降の arm64-v8a 端末で起動する
- 意図的な use-after-free を HWASan が検出する
- `-Psora.ubsan=true` で signed integer overflow の trap を計装した `libsora_sdk.so` をビルドできる
- 意図的な signed integer overflow を UBSan が検出する
- サニタイザを指定しない通常ビルドに計装と `wrap.sh` が混入しない
- Android のビルド手順とサニタイザの検証手順が `docs/ANDROID.md` に記載されている
- `CHANGES.md` の `## develop` に変更内容が記載されている

## 検証結果

- HWASan、UBSan、通常版の DevTools debug APK がすべてビルドに成功した
- Pixel 7（Android 16、arm64-v8a）で HWASan 版 DevTools を起動し、HWASan ランタイムの読み込みを確認した
- 一時的に挿入した use-after-free に対して `HWAddressSanitizer: tag-mismatch` と `SIGABRT` が出力された
- 一時的に挿入した signed integer overflow に対して UBSan trap の `SIGTRAP` が出力された
- 検証用に挿入した不具合は検証直後に除去した
- 通常版 APK に HWASan の計装シンボルと `wrap.sh` が存在しないことを確認した
- 通常版・release 版の CMake コンパイルコマンドに HWASan / UBSan のフラグが存在しないことを確認した
- 通常版 DevTools が Pixel 7 で fatal log なしに起動し続けることを確認した
- リポジトリ直下と `devtools/` で `flutter analyze` と `flutter test` が成功した

## 解決方法

1. ASan の CMake option と Gradle property を HWASan 用へ置き換えた
2. HWASan / UBSan の `ON` と `OFF` を Gradle から CMake へ常に渡すようにした
3. HWASan 検証時だけ DevTools debug APK に `wrap.sh` を組み込むようにした
4. Android のビルド要件、通常ビルド、HWASan、UBSan の手順を `docs/ANDROID.md` に記載した
5. HWASan と UBSan の検出、および通常ビルドへの非混入を実機で確認した

## 参考資料

- [Android NDK の HWAddressSanitizer](https://developer.android.com/ndk/guides/hwasan)
- [Android NDK のメモリーエラーのデバッグと緩和](https://developer.android.com/ndk/guides/memory-debug)
- [Clang の UndefinedBehaviorSanitizer](https://clang.llvm.org/docs/UndefinedBehaviorSanitizer.html)
