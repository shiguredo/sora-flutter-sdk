# Android

## 対応アーキテクチャ

| アーキテクチャ | 状態 |
| --- | --- |
| arm64-v8a | 対応 |

## システム要件

- Flutter 3.44.0 以上
- Android SDK
- Android NDK 28.2.13676358
- Android API level 29 以上

## 依存関係

Android 向けビルドでは、Gradle の `fetchNativeDeps` task が libwebrtc-c と WebRTC の配布物を自動取得します。

取得対象のバージョン、URL、SHA-256 は [`../scripts/native_deps.json`](../scripts/native_deps.json) で管理しています。

## 通常ビルド

アプリケーションディレクトリで依存パッケージを解決してから APK をビルドします。

```bash
flutter pub get
flutter build apk --debug
flutter build apk --release
```

サニタイザは既定で無効です。
通常ビルドとリリースビルドにはサニタイザのコンパイルオプションと実行設定が入りません。

## HWAddressSanitizer

**HWAddressSanitizer（HWASan）** は use-after-free、二重解放、ヒープとスタックの境界外アクセスを検出します。

検証には Android 14（API level 34）以降の arm64-v8a 端末を使用します。
Android 13 以前の端末では HWASan 対応システムイメージが必要です。

DevTools の HWASan ビルドは次のコマンドで作成します。

```bash
cd devtools
flutter pub get
cd android
./gradlew -Psora.hwasan=true app:assembleDebug
```

`sora.hwasan=true` は `libsora_sdk.so` に `-fsanitize=hwaddress` を付けます。
同じ設定は DevTools の debug APK に `wrap.sh` を組み込み、アプリ起動時に `LD_HWASAN=1` を設定します。
HWASan の C++ 実行時ライブラリには `c++_shared` を使用し、`libc++_shared.so` を APK に同梱します。
`sora.hwasan=true` は debug ビルド専用で、release / profile ビルドではエラーになります。

生成した APK を端末へインストールして起動します。

```bash
adb install -r ../build/app/outputs/flutter-apk/app-debug.apk
adb logcat -c
adb shell am force-stop com.example.devtools
adb shell monkey -p com.example.devtools 1
```

HWASan がメモリーエラーを検出すると、アプリは `SIGABRT` で終了し、`logcat` にレポートを出力します。

```bash
adb logcat | grep HWAddressSanitizer
```

ビルド済み `libsora_sdk.so` に HWASan の計装が入ったことは、NDK の `llvm-readelf` で確認できます。

```bash
llvm-readelf --symbols <libsora_sdk.so のパス> | grep __hwasan
```

## UndefinedBehaviorSanitizer

**UndefinedBehaviorSanitizer（UBSan）** は signed integer overflow を検出します。

UBSan は trap モードで動作するため、検出時は Android arm64-v8a で `SIGTRAP` により終了します。
追加のランタイムライブラリと `wrap.sh` は使用しません。

DevTools の UBSan ビルドは次のコマンドで作成します。

```bash
cd devtools
flutter pub get
cd android
# 既存の Debug 用 CMake cache を削除し、今回の計装だけを検査する。
rm -rf ../../android/.cxx/Debug
./gradlew -Psora.ubsan=true app:assembleDebug
```

UBSan の trap モードは追加ランタイムのシンボルを生成しません。
計装の有無は CMake が生成したコンパイルコマンドで確認します。

```bash
grep -E -- '-fsanitize=(signed-integer-overflow)|-fsanitize-trap=signed-integer-overflow' \
  ../../android/.cxx/Debug/*/arm64-v8a/compile_commands.json
```

## 参考資料

- [Android NDK の HWAddressSanitizer](https://developer.android.com/ndk/guides/hwasan)
- [Android NDK の wrap shell script](https://developer.android.com/ndk/guides/wrap-script)
- [Clang の UndefinedBehaviorSanitizer](https://clang.llvm.org/docs/UndefinedBehaviorSanitizer.html)
