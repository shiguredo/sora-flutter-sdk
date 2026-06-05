# Sora DevTools

Sora Flutter SDK を利用した WebRTC SFU Sora の開発者ツールです。

Sora の配信、視聴機能が一通り確認できるようになっています。
また何か問題あった場合の切り分けのための調査にも利用できるよう、レポート機能やデバッグ機能を搭載しています。

## 初期設定

environment.dart を作成し、Sora への接続情報を設定してください。
ここで設定したシグナリング URL とチャネル ID が DevTools 内でのそれぞれの初期値となります。

```bash
cp lib/configs/environment.example.dart lib/configs/environment.dart
```

## 起動方法

1. 依存パッケージを解決します

```bash
cd devtools/lib
flutter pub get
```

1. devtools を起動します

端末の device_id を指定して起動します。利用可能な端末は `flutter devices` 等で確認できます。
初回ビルド時は iOS / macOS では Swift Package Manager が `libwebrtc_c.xcframework.zip` を自動取得し、Android では Gradle の `fetchNativeDeps` task が必要な `libwebrtc-c` / `libwebrtc` を自動取得します。

```bash
flutter run -d <device_id>
```
