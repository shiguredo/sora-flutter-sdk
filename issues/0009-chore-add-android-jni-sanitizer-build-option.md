# Android JNI に AddressSanitizer / UndefinedBehaviorSanitizer ビルドオプションを追加する

- Priority: Low
- Created: 2026-06-02
- Model: Opus 4.8
- Branch: feature/add-android-jni-sanitizer-build-option
- Polished: 2026-06-05

## 目的

`android/src/main/cpp/jni_onload.c` は手動の参照カウント・`malloc` / `free`・JNI 参照管理を多用するが、デバッグビルドで AddressSanitizer (ASan) / UndefinedBehaviorSanitizer (UBSan) を有効化する仕組みが無い。リーク・use-after-free・境界外アクセス (ASan) と整数オーバーフロー等の未定義動作 (UBSan) をオプトインで検出できるビルドオプションを整備する。`0218` (NULL 早期 return の検証) と `0229` (映像フレーム入力の境界外読み取り・整数オーバーフロー検証) がこの仕組みを検証手段として参照している。

注: LeakSanitizer (LSan) は Android で standalone では非対応のため対象に含めない。リーク検出は ASan 経由の限定的なものとなる (Android ランタイムでのリーク検出は限定的)。整数オーバーフロー検出のため `0229` が要望する UBSan を本 issue のスコープに含める。

## 優先度根拠

- Low。機能には影響しない開発支援。本モジュールはメモリー安全性の指摘が多発する領域であり、サニタイザを切り替えられると回帰検出に効く

## 現状

- `android/src/main/cpp/CMakeLists.txt` にサニタイザ関連のフラグ・オプションが存在しない (grep でサニタイザ要素 0 件)。`sora_sdk` ターゲット (`add_library(sora_sdk SHARED ...)`) には既存の `target_link_options` で `@webrtc.ldflags` / `@libwebrtc_c_api.ldflags` が付く
- `android/build.gradle` は `externalNativeBuild.cmake.arguments` に ABI 等を直書きするのみ (`build.gradle:22-32`、`abiFilters 'arm64-v8a'`、`minSdkVersion 29`、`ndkVersion 28.2.13676358`)。debug 専用 buildType やサニタイザ引数の分岐は無い
- 本モジュールは Android library モジュール (`com.android.library`) で、成果物は `sora_sdk.so` 単体。ASan を実行時に効かせるには、これを取り込む消費側アプリ側の設定が必要 (後述)。Android APK をビルド・実機起動できるのは `devtools` (`devtools/android`、`docs/ANDROID.md:106-107` が `cd devtools && flutter build apk --debug` を案内) であり、`e2e_test_app` には Android ターゲットが無い (linux/macos のみ)
- prebuilt の `libwebrtc-c.a` / `libwebrtc.a` (`CMakeLists.txt` でリンク) は ASan 非計装のため、ASan は `jni_onload.c` (sora_sdk のコード) のみ計装する。WebRTC 内部の UAF/境界外は検出されない (本 issue の主目的は `jni_onload.c` の手動メモリ管理の検出なので整合)

## 設計方針

1. CMake オプションの追加 (`CMakeLists.txt`):
   - cache option を追加する (例: `option(SORA_SDK_ENABLE_ASAN "Enable AddressSanitizer" OFF)`、`option(SORA_SDK_ENABLE_UBSAN "Enable UndefinedBehaviorSanitizer (integer overflow 等)" OFF)`)。既定 OFF でリリースに無影響
   - ON のとき `sora_sdk` ターゲットの **compile と link の両方** に `-fsanitize=address -fno-omit-frame-pointer` (ASan) / `-fsanitize=signed-integer-overflow` (UBSan、整数オーバーフロー) を付ける (`target_compile_options` と `target_link_options` 双方。compile だけだと未定義参照でリンク失敗する)。既存の `target_link_options` (`@webrtc.ldflags` 等) と併存させる
   - UBSan はランタイム同梱を避けるため trap モード (`-fsanitize-trap=signed-integer-overflow`) を基本とする (未定義動作で SIGILL により停止し、ランタイム `.so` 不要)。診断メッセージが必要なら別途 UBSan ランタイムを検討する
   - 検出範囲の役割分担: `0229` 点 1 の DirectByteBuffer 生ポインタの境界外読み取りは ASan が担当する (UBSan の `bounds` は静的配列の境界のみで生ポインタ/`malloc` 領域は捕捉しないため UBSan には含めない)。`0229` 点 2 の整数オーバーフローは UBSan が担当する
2. gradle からのオプトイン (`build.gradle`):
   - gradle property (例: `-Psora.asan=true` / `-Psora.ubsan=true`) を見て `externalNativeBuild.cmake.arguments` に `-DSORA_SDK_ENABLE_ASAN=ON` 等を条件付きで足す。property 未指定時は付けない (リリース・通常ビルドに無影響)
3. 実行時セットアップ (消費側アプリ。ASan のみ該当):
   - ASan 計装した `sora_sdk.so` を実機で動かすには、消費側アプリ `devtools` を `android:debuggable true` にし、NDK 同梱の ASan ランタイム `libclang_rt.asan-aarch64-android.so` を `jniLibs/arm64-v8a` に同梱し、`wrap.sh` (ASan ランタイムを最初にロードする) を配置する必要がある (Android NDK の AddressSanitizer 手順)。library モジュール単体ではこのランタイム設定はできないため、検証は `devtools` の設定を含めて行う。UBSan trap モードはランタイム不要のためこのセットアップは要らない
4. 手順を `docs/ANDROID.md` に簡潔に追記する (CMake オプションの渡し方、`devtools` の wrap.sh / ランタイム同梱手順、最小再現での確認方法)。追記時に `docs/ANDROID.md:43-50` の古い `--whole-archive` リンク記述が現行 `CMakeLists.txt` (whole-archive 不使用、`@libwebrtc_c_api.ldflags` 方式) と乖離している点もあわせて整合させる

参考: 対象 ABI が `arm64-v8a` 単独のため HWASan (`-fsanitize=hwaddress`、低オーバーヘッド) も選択肢になるが、本 issue では実績のある ASan を採る (HWASan はデバイス/API 制約があるため)。

## 完了条件

- 既定 (オプション OFF) ではリリース・通常ビルドの構成・サイズに影響しない (gradle property 未指定でサニタイザフラグが一切付かないことを確認する)
- `-Psora.asan=true` 等でオプトインすると、`sora_sdk.so` が ASan / UBSan 計装でビルドできる
- 消費側アプリ `devtools` (debuggable + wrap.sh + ASan ランタイム同梱) で起動し、logcat に AddressSanitizer の初期化ログが出ること、および意図的に仕込んだ UAF / 境界外 / 整数オーバーフローを検出 (ASan レポート / UBSan trap での停止) できることを確認する
- 手順が `docs/ANDROID.md` に追記されている
- `CHANGES.md` の `## develop` の `### misc` に `[ADD]` エントリを追記する

## 検証方針

- サニタイザ有効ビルドの動作確認は上記「完了条件」のとおり、消費側アプリでの実機起動 + logcat 確認 + 意図的な不具合 (例: 解放済み領域アクセス、`width * height` のオーバーフロー) の検出で行う
- リリース無影響は「property 未指定ビルドでサニタイザフラグが付かない」ことをビルドコマンドの出力 / 生成 `.so` で確認する

## 関連 issue

- `issues/0218-bug-fix-native-on-track-null-deref.md` -- early return 追加の検証で ASan/LSan ビルドを参照 (LSan は本 issue で非対応に整理したため、ASan で代替)
- `issues/0229-bug-fix-jni-video-frame-input-validation.md` -- 境界外読み取り検出 (ASan) と整数オーバーフロー検出 (UBSan) を本 issue に要望。本 issue で UBSan をスコープに含めた

## 解決方法

1. Gradle property で ASan / UBSan を切り替えられるようにする
2. `devtools` 側の実機検証手順を整備する
3. `docs/ANDROID.md` と `CHANGES.md` を同期して更新する
