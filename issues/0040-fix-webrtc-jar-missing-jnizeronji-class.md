# webrtc.jar に JniZeroJni クラスが欠落している問題の修正

- Priority: High
- Created: 2026-06-08
- Model: DeepSeek V4 Flash
- Branch: feature/fix-webrtc-jar-missing-jnizeronji-class
- Polished: 2026-06-08

## 目的

`flutter build apk --release` 実行時に発生する R8 Missing class エラー (`org.jni_zero.JniZeroJni`) を修正する。

## 優先度根拠

現在 `flutter build apk --release` が成功せず、リリースビルドが行えない。これは sora-flutter-sdk の開発・テストフローに直接影響するため High。

### 既存の対応

`android/consumer-rules.pro` には既に `-keep class org.jni_zero.** { *; }` が定義されている。このルールは R8 に対して `org.jni_zero` パッケージのクラスを保持するよう指示するが、`JniZeroJni.class` 自体が `webrtc.jar` に含まれていないため効果がない。今回のパッチで `JniZero$Natives.class` が生成されなくなることによる consumer-rules.pro の変更は不要。

## 現状

### エラー内容

```
ERROR: Missing class org.jni_zero.JniZeroJni (referenced from: void org.jni_zero.JniZero.setJniClassLoader(java.lang.ClassLoader))
```

### 原因

libwebrtc-c を 0.149.0 (WebRTC M149) に更新した際に導入された問題。

#### WebRTC M148 (正常) と M149 (異常) の差分

Chromium の commit `d75bfa0b3cbc` ("JNI Zero: Revamp how class loading works", 2026-04-07) で以下の変更が入った。このコミットが WebRTC M149 で採用された chromium 参照 revision (`7c92732938de0ef7e28f5da231994723f938f407`) の範囲に含まれる:

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

#### `init()` と `JniZeroJni` の依存関係

方針 A のパッチでは `JniZero.java` の `setJniClassLoader()` のみを修正し、`init()` は変更しない。この前提を検証するため、Chromium のソースコード (`third_party/jni_zero/java/src/org/jni_zero/JniZero.java`) を確認した結果:

- `init()` メソッドは `sPendingJniClassLoader` を読み取り、`nativeSetJniClassLoader(ClassLoader)`（JNI 直接呼び出し）に渡すのみ。`JniZeroJni` を経由しない
- `@NativeMethods interface Natives` は `setJniClassLoader()` 内の `JniZeroJni.get().setJniClassLoader(classLoader)` 呼び出しでのみ使用される。他のメソッドからの参照はない
- 従って `@NativeMethods interface Natives` の削除は `init()` を含む他のメソッドに影響しない

#### `setJniClassLoader()` と `init()` の呼び出し順序

パッチ適用後、`setJniClassLoader()` は `sPendingJniClassLoader = classLoader` のみ行い、JNI 即時呼び出しは行わない。この変更が安全であることを確認するため、WebRTC Android の初期化シーケンスを分析した:

- WebRTC Android では `PeerConnectionFactory.initialize()` → `JniZero.init()` の順で初期化が行われる
- `setJniClassLoader()` が呼ばれるのは `init()` よりも前（PeerConnectionFactory.initialize() 内初期化の一部）
- その後 `init()` が `sPendingJniClassLoader` を読み取りネイティブ側に渡す
- 従って `init()` 後に `setJniClassLoader()` が呼ばれるパスは存在しない
- 仮に将来そのようなパスが追加された場合も、`sPendingJniClassLoader` に保持されるため `init()` の再実行 or 拡張で対応可能

#### なぜ JniZeroJni.class が欠落するか

- `third_party/jni_zero/BUILD.gn` の `generate_jni("generate_jni")` が `JniZero.java` から `JniZeroJni.java` を生成し、`generate_jni_java` ターゲットの jar に含める
- `sdk/android/BUILD.gn` の `dist_jar("libwebrtc")` は `direct_deps_only = true` だが、`generate_jni_java` を依存に含めていない
- そのため `libwebrtc.jar` (→ `webrtc.jar`) に `JniZeroJni.class` が含まれない
- R8 が `JniZero.class` のバイトコード中にある `JniZeroJni` への参照を解決できずエラーになる

## 設計方針

`webrtc-build` リポジトリ (`shiguredo-webrtc-build/webrtc-build`) のパッチワークフローに従い、パッチファイルを作成して対応する。`patches/` ディレクトリや `run.py` は本リポジトリには存在せず、`webrtc-build` リポジトリの資産である。実装者は `webrtc-build` のパッチワークフローに習熟していることを前提とする。

### 方針 A (推奨): `JniZero.java` をパッチして JniZeroJni 依存を除去

`third_party/jni_zero/java/src/org/jni_zero/JniZero.java` を修正し、`JniZeroJni` への参照と `@NativeMethods` インターフェースを削除する。

パッチの変更内容（概念的な例示。実際のソースは `webrtc-build` でチェックアウトした WebRTC ソースの該当ファイルを確認すること）:

```java
// Before (概念例)
static void setJniClassLoader(ClassLoader classLoader) {
    JniZeroJni.get().setJniClassLoader(classLoader);
    sPendingJniClassLoader = classLoader;
}

@NativeMethods
interface Natives {
    void setJniClassLoader(ClassLoader classLoader);
}
```

```java
// After
static void setJniClassLoader(ClassLoader classLoader) {
    sPendingJniClassLoader = classLoader;
}
```

`@NativeMethods interface Natives` には `setJniClassLoader()` のみが定義されており、他のメソッドからの参照はないため、丸ごと削除して安全。`init()` メソッドは変更せず、`sPendingJniClassLoader` を従来通りネイティブ側に渡す。ただし実装着手時には、`webrtc-build` でチェックアウトした WebRTC ソースの `JniZero.java` で `init()` が `sPendingJniClassLoader` を参照していることを確認すること。もし `sPendingJniClassLoader` が存在しない場合は `init()` のパッチも追加で必要になる。

**理由:**
- ソースコードのみの変更でビルドシステムに手を入れない
- ClassLoader は `init()` 経由でネイティブ側に渡されるため、`setJniClassLoader()` の動作は変わらない
- 既存のパッチ (android_proxy.patch 等) と同じワークフローで対応可能
- `@NativeMethods interface Natives` 削除の影響範囲は `setJniClassLoader()` に限定される（前述の `init()` 依存関係の検証結果参照）

### 方針 B (非推奨): BUILD.gn をパッチ

`dist_jar("libwebrtc")` の依存に `generate_jni_java` を追加する。ただし:
- `generate_jni_java` ターゲットへの visibility が `sdk/android/BUILD.gn` からは通っていないため、`third_party/jni_zero/BUILD.gn` の visibility 設定変更が必要
- `third_party/jni_zero` は Chromium 管理下のコードであり、WebRTC 側からの過剰な依存追加は推奨されない
- 方針 A より変更量が大きく、パッチの保守コストが高い

## 完了条件

- `flutter build apk --release` が R8 エラーなく完了すること
- `flutter build appbundle --release` でも同様のエラーが発生しないことを確認すること
- 注意: 現在の CI は `flutter build apk --debug` のみ実行しており、`--release` ビルドは含まれていない。本 issue の修正後、CI に `--release` ビルドを追加するか否かは別途判断する（本 issue のスコープ外）
- クラスローディングの動作に影響がないこと（以下の手順で検証する）
  - パッチ適用後の `webrtc.jar` で SDK の接続テスト（E2E テスト相当）を実施し、`ClassNotFoundException` や `NoClassDefFoundError` が発生しないことを確認する（現時点で Android 向け E2E テスト基盤は未整備のため、手動検証となる）
  - E2E テストで異常が発生した場合、`ClassLoader.getResource()` やリフレクションで `org.jni_zero.JniZero` が正常にロードされることを確認する

## 解決方法

1. `webrtc-build` リポジトリ (`shiguredo-webrtc-build/webrtc-build`) の該当リリースタグ (`webrtc-build` の `m149.7827.5.0` 対応リビジョン) をベースに作業用ブランチを作成する
2. `patches/` に `fix_jni_zero_jni_class_reference.patch` を追加する（パッチ形式は既存の `android_proxy.patch` 等に合わせる）
3. `run.py` の `PATCHES` リスト (android ターゲット) に上記パッチファイル名を追加する（追加位置は既存パッチとの整合性を確認する）
4. `webrtc-build` で再ビルドし、新しいリリースを作成する
5. `native_deps.json` の `webrtc.version` と SHA256 を新しいリリースに更新する
6. パッチ適用後の `JniZero.class` のバイトコード中に `JniZeroJni` への参照が存在しないことを `javap -c -p org.jni_zero.JniZero` 等で確認する（`JniZeroJni` はパッチ前後とも `webrtc.jar` に含まれていないため、`jar tf` ではパッチの効果を検証できない）
7. 更新後の依存で `flutter build apk --release` が R8 エラーなく成功することを確認する
