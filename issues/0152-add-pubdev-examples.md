# pub.dev 公開版を利用する Flutter example を追加する

- Created: 2026-09-01
- Completed: {YYYY-MM-DD}
- Branch: feature/add-pubdev-examples
- Polished: {YYYY-MM-DD}

## 目的

pub.dev に公開されている `sora_sdk` を利用して、利用者が Sora Flutter SDK の
代表的なユースケースを最小構成で確認できる Flutter example を提供する。

実際にビルドできるコードを SDK 本体と同じリポジトリで管理し、利用者だけでなく
LLM も公開 API の正しい利用方法を参照できる状態にする。

## 現状

- Dart / Flutter パッケージの標準位置である `example/` が存在しない。
- `README.md` には sendrecv とメッセージング専用接続のコード例があるが、
  そのまま起動できる Flutter アプリではない。
- `devtools/pubspec.yaml` と `e2e_test_app/pubspec.yaml` は `sora_sdk` を
  `path: ..` で参照するため、リポジトリ内の SDK は検証できるが、pub.dev の
  公開物を利用者と同じ条件では検証できない。
- `devtools/` と `e2e_test_app/` は `.pubignore` で公開対象から除外されており、
  pub.dev の Example タブにも表示されない。

## 設計方針

### ディレクトリ構成

単数形の `example/` を利用し、次の 2 アプリだけを追加する。

```text
example/
├── README.md
├── sendrecv/
└── messaging/
```

`basic` は `sendrecv` と役割が重複するため追加しない。

`example/README.md` は 2 アプリの目的、前提条件、起動方法を示す索引とし、
pub.dev の Example タブに表示できる構成にする。

### pub.dev 公開版への依存

各アプリの `pubspec.yaml` では、実装時点で pub.dev に公開されている
`sora_sdk` のバージョンを完全一致で指定する。

- `path` 依存を使用しない。
- `dependency_overrides` でリポジトリ内の SDK へ差し替えない。
- 未公開バージョンを指定しない。
- アプリとして `pubspec.lock` をコミットし、`sora_sdk` の取得元を
  `source: hosted` に固定する。
- 各アプリ自身には `publish_to: none` を指定する。

これにより、SDK 本体の開発中コードを確認する `devtools` / `e2e_test_app` と、
公開済みパッケージを確認する `example` の責務を分離する。

### sendrecv example

`Sora.createConnection`、`SoraConnection.connect`、`localVideo`、
`SoraLocalVideoWidget`、`SoraRemoteVideoWidget` を利用し、次を確認できる
最小アプリにする。

- シグナリング URL、チャネル ID、認証 metadata の入力
- カメラとマイクを利用した sendrecv 接続
- ローカル映像とリモート映像の表示
- 接続状態とエラーの表示
- 明示的な切断と `dispose`

### messaging example

音声と映像を無効化し、DataChannel シグナリングを利用する最小アプリにする。

- シグナリング URL、チャネル ID、認証 metadata の入力
- メッセージング専用接続
- `#` で始まるユーザー定義 DataChannel を利用した送受信
- 受信メッセージと接続状態の表示
- 明示的な切断と `dispose`

### 接続情報

シグナリング URL、認証 metadata、その他の接続情報は画面から入力し、
リポジトリへ実値を保存しない。README、ソースコード、テストにも実際の
認証情報や内部エンドポイントを含めない。

### ドキュメントと検証

- ルート `README.md` の構成とサンプル説明に `example/` を追加する。
- `.pubignore` では `example/` を除外せず、公開パッケージに含める。
- `.github/workflows/ci.yml` で両アプリの format、analyze、build を確認する。
- `dart pub publish --dry-run` で `example/` が公開対象に含まれることを確認する。
- 接続を必要とする自動テストのために認証情報を追加せず、実際の接続確認は
  利用者が入力した接続情報で行う。

## 完了条件

- [ ] `example/README.md` が sendrecv と messaging の目的、前提条件、
      起動方法を案内している。
- [ ] `example/sendrecv/` が pub.dev 公開版の `sora_sdk` を利用して起動し、
      映像音声の送受信、接続、切断を確認できる。
- [ ] `example/messaging/` が pub.dev 公開版の `sora_sdk` を利用して起動し、
      DataChannel メッセージの送受信、接続、切断を確認できる。
- [ ] 両アプリの `pubspec.lock` で `sora_sdk` が `source: hosted` になっている。
- [ ] 両アプリに `path` 依存と `dependency_overrides` が存在しない。
- [ ] 接続情報や認証情報の実値がリポジトリに含まれていない。
- [ ] ルート `README.md` から両アプリへ到達できる。
- [ ] `dart pub publish --dry-run` の公開対象に `example/` が含まれている。
- [ ] 両アプリの format、analyze、対応プラットフォームの build が CI で成功する。
