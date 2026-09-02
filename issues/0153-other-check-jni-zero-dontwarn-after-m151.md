# libwebrtc M151 以降で R8 の jni_zero dontwarn が不要か確認する

- Created: 2026-09-02
- Completed: {YYYY-MM-DD}
- Branch: feature/debug-check-jni-zero-dontwarn-after-m151
- Polished: {YYYY-MM-DD}

## 目的

libwebrtc を M151 以降へ更新した際に、R8 の `-dontwarn org.jni_zero.**` が不要になるかを確認する。

[指定コミット](https://github.com/shiguredo-webrtc-build/webrtc-build/commit/a36e66ced18c0215b81d121c8ecd22a065ebb92c) では、Android の `libwebrtc.jar` に生成 JNI Java ターゲットと JNI 登録を含める `android_jni_zero_generated_java.patch` が追加されている。

この変更によって JNI Zero の不足クラスが解消されるなら、DevTools に残っている回避設定を削除する。

## 現状

- `scripts/native_deps.json` の `webrtc.version` は `m150.7871.0.0` である。
- `android/build.gradle` は `_deps/webrtc/jar/webrtc.jar` を依存として利用している。
- `devtools/android/app/build.gradle.kts` は Android release build で R8 を有効にしている。
- `devtools/android/app/proguard-rules.pro` に `-dontwarn org.jni_zero.**` が設定されている。
- `android/consumer-rules.pro` は `org.jni_zero.**` を keep している。
- `issues/pending/0040-fix-webrtc-jar-missing-jnizeronji-class.md` は、生成 JNI クラスが `webrtc.jar` に含まれない問題を扱っている。

## 設計方針

M151 以降の Android 向け WebRTC 配布物へ更新したうえで、実際の `webrtc.jar` と R8 の release build を確認する。

1. 配布物に `org/jni_zero/JniZeroJni.class`、`org/jni_zero/GEN_JNI.class`、その他の必要な生成 JNI クラスが含まれることを確認する。
2. `devtools/android/app/proguard-rules.pro` から `-dontwarn org.jni_zero.**` を削除した状態で、R8 を有効にした release APK / AAB をビルドする。
3. 実機で DevTools を起動し、Sora 接続時に JNI Zero のクラス不足によるエラーが発生しないことを確認する。
4. 不要と判断できない場合は、必要性の根拠と不足しているクラスを記録し、回避設定を維持する。

## 完了条件

- [ ] M151 以降の WebRTC 配布物に `android_jni_zero_generated_java.patch` の効果が反映されていることを確認した。
- [ ] `webrtc.jar` に必要な JNI Zero の生成クラスが含まれていることを確認した。
- [ ] `-dontwarn org.jni_zero.**` の要否を R8 release build と実機動作で判断した。
- [ ] 不要と判断した場合は `devtools/android/app/proguard-rules.pro` から設定と古い説明コメントを削除した。
- [ ] 判断結果を記録し、関連する pending issue の扱いを決定した。

## 関連 issue

- [0040: webrtc.jar に JniZeroJni クラスが欠落している問題の修正](pending/0040-fix-webrtc-jar-missing-jnizeronji-class.md)

M151 以降の配布物で生成 JNI クラスの欠落が解消され、`dontwarn` が不要と判断できた場合は、0040 の必要性も見直す。
