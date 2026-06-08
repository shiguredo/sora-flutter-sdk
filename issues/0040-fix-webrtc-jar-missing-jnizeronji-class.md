# webrtc.jar に JniZeroJni クラスが欠落している問題の修正

- Priority: High
- Created: 2026-06-08
- Model: DeepSeek V4 Flash
- Branch: feature/fix-webrtc-jar-missing-jnizeronji-class

## 目的

`flutter build apk` 実行時に発生する R8 Missing class エラー (`org.jni_zero.JniZeroJni`) を修正する。

## 優先度根拠

現在 `flutter build apk --release` が成功せず、リリースビルドが行えない。これは sora-flutter-sdk の開発・テストフローに直接影響するため High。

## 現状

### エラー内容

```
ERROR: Missing class org.jni_zero.JniZeroJni (referenced from: void org.jni_zero.JniZero.setJniClassLoader(java.lang.ClassLoader))
```

### 原因

libwebrtc-c を 0.149.0 (WebRTC M149) に更新した際に導入された問題。

#### WebRTC M148 (正常) と M149 (異常) の差分

Chromium の commit `d75bfa0b3cbc` ("JNI Zero: Revamp how class loading works", 2026-04-07) で以下の変更が入った:

| ファイル | M148 (`m148.7778.7.0`) | M149 (`m149.7827.5.0`) |
|---------|-----------------------|-----------------------|
| `JniInit.java` | あり | なし (JniZero.java に統合) |
| `JniUtil.java` | あり | なし (JniZero.java に統合) |
| `JniZero.java` | なし | あり |
| `JniZeroJni.java` (生成) | なし (不要) | あり (必要) |

M148 では `JniInit.setJniClassLoader()` は生成クラスを参照していなかったため問題なかった。M149 の `JniZero.setJniClassLoader()` は `JniZeroJni.get()` を呼び出すため、`JniZeroJni.class` が必要。

#### M150 以降でも改善されていない

最新の WebRTC HEAD (2026-06-08 時点) まで確認したが、本問題は改善されていない。

| 確認対象 | 結果 |
|---------|------|
| Chromium `third_party/jni_zero/JniZero.java` (HEAD, `d6efb5793a55`) | `JniZeroJni` への参照が依然として存在 |
| `jni_zero/BUILD.gn` の最終更新 | 2024-06-14 (変更なし) |
| WebRTC `sdk/android/BUILD.gn` の `dist_jar("libwebrtc")` | `direct_deps_only = true` のまま、`generate_jni_java` なし |
| WebRTC の chromium `src/third_party` 参照 revision | `7c92732938de0ef7e28f5da231994723f938f407` (変更なし) |

本家 Chromium では APK ビルド時に全推移的依存 jar がマージされるため問題が顕在化しない。一方 WebRTC の `libwebrtc` はライブラリ jar として `direct_deps_only = true` で生成されるため、本家で修正される見込みは低い。従って webrtc-build 側でのパッチ対応が唯一の解決策となる。

#### なぜ JniZeroJni.class が欠落するか

- `third_party/jni_zero/BUILD.gn` の `generate_jni("generate_jni")` が `JniZero.java` から `JniZeroJni.java` を生成し、`generate_jni_java` ターゲットの jar に含める
- `sdk/android/BUILD.gn` の `dist_jar("libwebrtc")` は `direct_deps_only = true` だが、`generate_jni_java` を依存に含めていない
- そのため `libwebrtc.jar` (→ `webrtc.jar`) に `JniZeroJni.class` が含まれない
- R8 が `JniZero.class` のバイトコード中にある `JniZeroJni` への参照を解決できずエラーになる

## 設計方針

webrtc-build リポジトリのパッチワークフローに従い、パッチファイルを作成して対応する。

### 方針 A (推奨): `JniZero.java` をパッチして JniZeroJni 依存を除去

`third_party/jni_zero/java/src/org/jni_zero/JniZero.java` を修正し、`JniZeroJni` への参照と `@NativeMethods` インターフェースを削除する。

**理由:**
- ソースコードのみの変更でビルドシステムに手を入れない
- ClassLoader は `init()` 経由でネイティブ側に渡されるため、`setJniClassLoader()` の動作は変わらない
- 既存のパッチ (android_proxy.patch 等) と同じワークフローで対応可能

### 方針 B (非推奨): BUILD.gn をパッチ

`dist_jar("libwebrtc")` の依存に `generate_jni_java` を追加する。ただし visibility の変更も必要で複雑。

## 完了条件

- `flutter build apk --release` が R8 エラーなく完了すること
- クラスローディングの動作に影響がないこと

## 解決方法

1. `webrtc-build` リポジトリの `patches/` に `fix_jni_zero_jni_class_reference.patch` を追加する
2. `run.py` の `PATCHES` リスト (android ターゲット) に上記パッチファイル名を追加する
3. libwebrtc-c を再ビルドし、生成された `webrtc.jar` で `flutter build apk --release` が成功することを確認する

### パッチの内容

`third_party/jni_zero/java/src/org/jni_zero/JniZero.java` に対して:

- `setJniClassLoader()` メソッド内の `JniZeroJni.get().setJniClassLoader(classLoader)` 呼び出しを削除し、常に `sPendingJniClassLoader = classLoader` とする
- `@NativeMethods interface Natives { ... }` を削除する

`init()` メソッドは変更せず、`sPendingJniClassLoader` を従来通りネイティブ側に渡す。
