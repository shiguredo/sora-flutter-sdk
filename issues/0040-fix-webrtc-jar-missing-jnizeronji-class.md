# webrtc.jar に JniZeroJni クラスが欠落している問題の修正

- Priority: High
- Created: 2026-06-08
- Model: DeepSeek V4 Flash
- Branch: feature/fix-jni-zero-jar
- Polished: 2026-06-08

## 目的

`flutter build apk --release` 実行時に発生する R8 Missing class エラーを解消する。

WebRTC の Android 向け Java 成果物に、実行時に必要な jni_zero の生成クラスを含める。

## 優先度根拠

修正前の WebRTC 成果物では、 Sora Flutter SDK の release build が R8 の Missing class エラーで失敗する。

リリースビルドを実行できないため、 SDK の開発と配布を直接妨げる。

## 調査結果

### M149 から生成 JNI クラスが必要になった

WebRTC M149 には、 JNI Zero の class loader 初期化を変更する Chromium の reland commit [d3c7cd15e366abf83461e9c407368227bbe57168](https://chromium.googlesource.com/chromium/src/third_party/jni_zero/%2B/d3c7cd15e366abf83461e9c407368227bbe57168) が含まれる。

M149 から `org.jni_zero.JniZero.setJniClassLoader()` は、 JNI ランタイム初期化後に `JniZeroJni.get().setJniClassLoader()` を呼び出す。

`JniZeroJni` は jni_zero が生成する Java クラスである。

`JniZeroJni` は `GEN_JNI` の native メソッドを呼び出すため、両方の class ファイルが必要になる。

M148 には `JniZero` とこの生成クラスへの参照が無かったため、この問題は発生しなかった。

### 配布物から生成クラスが落ちる理由

`sdk/android:libwebrtc_java` の配布 jar は直接依存だけを集める。

修正前は `third_party/jni_zero:generate_jni_java` が直接依存に含まれないため、 `JniZeroJni.class` が `libwebrtc.jar` に入らない。

jni_zero の jar 生成規則は `*Jni.class` と `*Jni$*.class` だけを含める。

そのため、 `JniZeroJni.class` を依存経由で含めても、 `GEN_JNI.class` は名前が一致せず除外される。

修正前の Android 向け Java 成果物には、次の 2 クラスだけが入っていた。

- `org.jni_zero.JniZero`
- `org.jni_zero.JniZero$Natives`

`org.jni_zero.JniZeroJni` と `org.jni_zero.GEN_JNI` は欠落していた。

### Sora Flutter SDK で R8 エラーになる理由

Sora Flutter SDK の `android/consumer-rules.pro` は `org.jni_zero.**` を keep する。

このため R8 は `JniZero` の参照先を解決し、存在しない `JniZeroJni` を検出して失敗する。

エラーは次のとおりである。

```
ERROR: Missing class org.jni_zero.JniZeroJni (referenced from: void org.jni_zero.JniZero.setJniClassLoader(java.lang.ClassLoader))
```

### Sora Android SDK で問題が表面化しない理由

WebRTC のバージョンではなく、初期化経路と R8 の keep 指定が、問題が表面化するかを決める。
ローカルで確認した M149 の `libwebrtc.aar` にも、 `JniZeroJni.class` と `GEN_JNI.class` は含まれていなかった。
したがって、 AAR 形式であることがこの問題を防いでいるわけではない。

Sora Android SDK は `PeerConnectionFactory.initialize()` による標準初期化を使い、 Flutter SDK 固有の `webrtc_InitClassLoader()` 経路を通らない。
さらに、 `org.jni_zero.**` を keep していないため、同じ欠落が R8 エラーとして表面化しない。
M149 の AAR を用いた Sora Android SDK quickstart では、 R8 を有効にした release build が成功した。

## 対応方針

`JniZero.java` の動作を変更して生成クラスへの参照を削除しない。

この方法は libwebrtc が定める class loader 初期化の動作を変えるため、配布物の欠落を直す対応として適切ではない。

`webrtc-build` の `patches/android_jni_zero_jar.patch` で、配布物に必要な生成クラスを含める。

パッチでは次を変更する。

1. `sdk/android:libwebrtc_java` の依存に `//third_party/jni_zero:generate_jni_java` を追加する。
2. `//third_party/jni_zero:jni_zero_java` から生成 Java ターゲットを参照できるよう visibility を追加する。
3. jni_zero の jar 生成規則に opt-in の `include_gen_jni` を追加する。
4. `jni_zero_java` で `include_gen_jni = true` を指定し、 `GEN_JNI.class` を jar に含める。
5. `run.py` の `android` へパッチを登録する。

パッチ適用後の Java 成果物には、次の 4 クラスが含まれる。

- `org.jni_zero.JniZero`
- `org.jni_zero.JniZero$Natives`
- `org.jni_zero.JniZeroJni`
- `org.jni_zero.GEN_JNI`

`android` の成果物では `webrtc.android.tar.gz` 内の `jar/webrtc.jar` に反映される。

公開 Java API とネイティブ ABI は変更しない。

追加するのは既存の `JniZero` が参照する生成済み Java クラスだけである。

## 実施済みの検証

- `webrtc-build` で `python3 run.py build android` が成功した。
- `python3 run.py package android` が成功した。
- 生成した `webrtc.jar` に上記 4 クラスが含まれることを確認した。
- ローカルの Sora Flutter SDK に生成した Android 向け WebRTC 成果物を配置した。
- `flutter build apk --release --target-platform android-arm64` が成功した。
- 生成した APK の dex に上記 4 クラスが含まれることを確認した。
- 修正前の `webrtc.jar` を使用し、 DevTools アプリで minify とリソース縮小を無効にした release APK を Pixel 7 で起動して、 Sora 接続できることを確認した。

## 完了条件

- `android` の `webrtc.jar` に上記 4 クラスが含まれる。
- パッチ適用済みの WebRTC を GitHub Release として公開する。
- `scripts/native_deps.json` の Android 向け WebRTC を公開済み成果物へ更新する。
- `flutter build apk --release --target-platform android-arm64` が成功する。
- `flutter build appbundle --release --target-platform android-arm64` が成功する。
- 実機で Sora 接続、音声入出力、ローカル映像、リモート映像、切断と再接続を確認し、 `ClassNotFoundException` と `NoClassDefFoundError` が発生しない。

## 解決方法

1. `webrtc-build` リポジトリ (`shiguredo-webrtc-build/webrtc-build`) の該当リリースタグ (`webrtc-build` の `m149.7827.5.0` 対応リビジョン) をベースに作業用ブランチを作成する
2. `patches/` に `fix_jni_zero_jni_class_reference.patch` を追加する（パッチ形式は既存の `android_proxy.patch` 等に合わせる）
3. `run.py` の `PATCHES` リスト (android ターゲット) に上記パッチファイル名を追加する（追加位置は既存パッチとの整合性を確認する）
4. `webrtc-build` で再ビルドし、新しいリリースを作成する
5. `native_deps.json` の `webrtc.version` と SHA256 を新しいリリースに更新する
6. パッチ適用後の `JniZero.class` のバイトコード中に `JniZeroJni` への参照が存在しないことを `javap -c -p org.jni_zero.JniZero` 等で確認する（`JniZeroJni` はパッチ前後とも `webrtc.jar` に含まれていないため、`jar tf` ではパッチの効果を検証できない）
7. 更新後の依存で `flutter build apk --release` が R8 エラーなく成功することを確認する
