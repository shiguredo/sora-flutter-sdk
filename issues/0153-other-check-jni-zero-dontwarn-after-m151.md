# libwebrtc M151 以降で R8 の jni_zero dontwarn が不要か確認する

- Created: 2026-09-02
- Completed: {YYYY-MM-DD}
- Branch: feature/remove-jni-zero-dontwarn-after-m151
- Polished: 2026-09-07

## 目的

libwebrtc を M151 以降へ更新した際に、R8 の `-dontwarn org.jni_zero.**` が不要になるかを確認し、不要であれば削除する。

[指定コミット](https://github.com/shiguredo-webrtc-build/webrtc-build/commit/a36e66ced18c0215b81d121c8ecd22a065ebb92c) では、Android の `libwebrtc.jar` に生成 JNI Java ターゲットと JNI 登録を含める `android_jni_zero_generated_java.patch` が追加されている。主目的は別 (`generated_swcodecs_jni_java` 等の `NoClassDefFoundError` 解消) であり、`GEN_JNI.class` の収録を保証する変更は含まれていないため、解消の有無は実物で検証する。

## 現状

- `scripts/native_deps.json` の `webrtc.version` は `m150.7871.3.1` である (`0154` で更新済み)。
- `android/build.gradle` は `_deps/webrtc/jar/webrtc.jar` を依存として利用している。
- `devtools/android/app/build.gradle.kts` は Android release build で R8 を有効にしている。
- `devtools/android/app/proguard-rules.pro` に `-dontwarn org.jni_zero.**` が設定されている (1-5 行目の説明コメント付き)。
- `android/consumer-rules.pro` は `org.jni_zero.**` を keep している (本 issue では変更しない)。
- `issues/pending/0040-fix-webrtc-jar-missing-jnizeronji-class.md` は、生成 JNI クラスが `webrtc.jar` に含まれない問題を扱っている。同 issue の提案パッチ (`include_gen_jni` 追加等) と指定コミットのパッチは名称・内容ともに別物である。
- M151 以降への更新を扱う issue は本 issue 以外に存在しないため、M151 配布物が利用可能になるまで本 issue に着手しない。

## 設計方針

M151 以降の Android 向け WebRTC 配布物へ更新したうえで、実際の `webrtc.jar` と R8 の release build を確認する。

1. `jar tf` で配布物の `webrtc.jar` に `org/jni_zero/JniZeroJni.class` と `org/jni_zero/GEN_JNI.class` が含まれることを確認する (判定基準は `0040` の対象 4 クラス)。
2. `devtools/android/app/proguard-rules.pro` から `-dontwarn org.jni_zero.**` と古い説明コメントを削除した状態で、R8 を有効にした release APK / AAB をビルドする。
3. 実機で DevTools を起動し、Sora 接続 (音声・映像・再接続) 時に JNI Zero のクラス不足によるエラーが発生しないことを確認する。
4. `GEN_JNI.class` が含まれない等で不要と判断できない場合は、必要性の根拠と不足しているクラスを記録し、回避設定を維持する。この場合は `0040` の `include_gen_jni` 案が依然必要なため、`0040` を維持する。不要と判断できた場合は `0040` を closed にする。

## 完了条件

- [ ] M151 以降の WebRTC 配布物の `webrtc.jar` に `JniZeroJni.class` と `GEN_JNI.class` が含まれることを `jar tf` で確認した。
- [ ] `-dontwarn org.jni_zero.**` の要否を R8 release build と実機動作 (音声・映像・再接続でエラーなし) で判断した。
- [ ] 不要と判断した場合は `devtools/android/app/proguard-rules.pro` から設定と古い説明コメントを削除した。
- [ ] 判断結果を記録し、`0040` を維持 / closed のいずれかにした。
- [ ] `flutter analyze` と関連テストが成功する。

## 関連 issue

- [0040: webrtc.jar に JniZeroJni クラスが欠落している問題の修正](pending/0040-fix-webrtc-jar-missing-jnizeronji-class.md)

M151 以降の配布物で生成 JNI クラスの欠落が解消され、`dontwarn` が不要と判断できた場合は、0040 を closed にする。解消されない場合は 0040 を維持する。
