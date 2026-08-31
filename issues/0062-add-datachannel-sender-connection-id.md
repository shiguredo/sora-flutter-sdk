# DataChannel メッセージの送信元 connection ID を解析する

- Created: 2026-08-03
- Completed: {YYYY-MM-DD}
- Branch: feature/add-datachannel-sender-connection-id
- Polished: 2026-08-03

## 目的

リアルタイムメッセージングで `sender_connection_id` ヘッダーが指定された場合に、Sora Flutter SDK が送信元 connection ID とメッセージ本体を分離して利用者へ通知できるようにする。

[Sora のリアルタイムメッセージング機能](https://sora-doc.shiguredo.jp/MESSAGING) では、`header: [{"type": "sender_connection_id"}]` を指定すると、Sora から受信するデータの先頭へ 26 バイトの送信元 connection ID が付加される。offer の `data_channels[].header` にはヘッダーの `length` も含まれる。Sora の connection ID は Base32(UUIDv4) の 26 文字の文字列のため、26 バイト = 26 文字であり、先頭 26 バイトが送信元 connection ID 全体と一致する。

## 現状

- `SoraConnectionConfig.dataChannels` は `header` を含む設定を Sora へ送信できる
- `SoraDataChannelEvent.header` は offer に含まれるヘッダー設定をそのまま通知する
- `SoraDataChannelController._handleCustomDataChannelMessage` は、展開後の受信データ全体を `SoraDataChannelMessage.data` として通知する
- `SoraDataChannelMessage` には `label` と `data` しかなく、送信元 connection ID を取得する API がない
- 利用者が offer のヘッダー長を管理し、受信データを自分で分割する必要がある

## 設計方針

- 変更対象ファイル: `lib/src/sora_data_channel_controller.dart`、`lib/src/sora_data_channel_message.dart`、`lib/src/sora_connection_config.dart`（DartDoc のみ）、`README.md`、`test/sora_data_channel_controller_test.dart`、`e2e_test_app/integration_test/custom_data_channel_e2e_test.dart`
- offer の `data_channels[].header` をラベル単位で解析し、ヘッダーの種類、順序、長さを保持する。解析対象は `#` プレフィックス付きのカスタムラベルのみとする（組み込みラベルには Sora 仕様上 header が付かない）。複数ヘッダーが並ぶ場合は順序に従い、先行ヘッダーの長さ合計から `sender_connection_id` のオフセットを計算する。offer の `header` キーの値が List 以外の型の場合は無視して既存値を維持する
- 解析結果は `customChannelCompress` と同様のラベルキーのキャッシュで保持し、再 offer で対象ラベルが省略されたり `header` キーが欠落した場合は維持する。`header` が明示的に変更・`header: []` に変更された場合は更新する（既存の `updateCompressFlagIfPresent` と同じ更新ルール）。`header: null` は `header` キー欠落と同様に扱い、既存値を維持する。キャッシュは `clear()` で他の内部状態とともにクリアする（既存の `customChannelCompress` と同じ扱い）
- キャッシュ未設定時は `_lastOfferMessage` からヘッダー情報を取得するフォールバックを設ける（既存の `_findDataChannelCompressFlag` と同様）
- `SoraDataChannelEvent.header`（生値の `Object?`）は現状のまま変更せず、解析は `DataChannelController` 内部のキャッシュで行う
- 圧縮された DataChannel では、既存の展開処理後にヘッダーを解析する。Sora 仕様の文面（`[sender_connection_id (26 bytes)][message]`）からは圧縮時のバイトレイアウトが確定できないため、実装時に実サーバーとの E2E でバイトレイアウトを検証して確定する。なお、deflate 展開に失敗した場合は既存どおりメッセージを破棄して通知しない（展開できないデータにヘッダー解析は適用できない）
- `sender_connection_id` は offer の `length` を使用して切り出し、UTF-8 文字列へ変換する。`length` が欠落している場合は 26 バイト固定で切り出す
- `SoraDataChannelMessage` に次の情報を追加する
  - `String? senderConnectionId`
  - ヘッダーを除いたメッセージ本体を表す `Uint8List payload`
  - `payload` はオプショナルとし、既存の `SoraDataChannelMessage(label:data:)` による構築を後方互換で維持する
  - DartDoc には、`senderConnectionId` が `null` になる条件（ヘッダー未指定・解析失敗）と、`payload` が `data` の sublist (view) であり片方の変更が他方へ波及することを記載する
- 後方互換性を維持するため、既存の `data` はヘッダーを含む展開後の受信データを引き続き返す
- ヘッダーがない場合は `senderConnectionId` を `null` とし、`payload` は `data` と同じ内容にする
- データがヘッダー長より短い場合や connection ID をデコードできない場合は、受信処理を停止せず `senderConnectionId` を `null`、`payload` を `data` と同じ内容にして通知し、デバッグログへ理由を記録する（ヘッダー未指定の場合と区別できないことを許容する）
- `payload` は `data` の `sublist`（view）で生成し、不要なデータコピーを避ける。`data` の可変所有権は変更しない
- `README.md` に設定例と受信例を追加する。設定例には `length` を含めない（`length` は offer 時にのみ Sora 側が付与し、connect 時には指定できない）

## 完了条件

- [ ] offer の `data_channels[].header` からラベルごとのヘッダー長を取得できる
- [ ] `sender_connection_id` が `SoraDataChannelMessage.senderConnectionId` として通知される
- [ ] `payload` にヘッダーを除いたメッセージ本体が格納される
- [ ] 既存の `data` は従来どおりヘッダーを含む受信データを返す
- [ ] ヘッダーを指定していない DataChannel の動作が変わらない
- [ ] 圧縮あり、圧縮なしの両方で正しく解析できる
- [ ] 再 offer 後も既存ラベルのヘッダー情報が維持される
- [ ] 不正または短すぎるデータで例外や接続切断が発生しない
- [ ] ヘッダー解析のユニットテストが `test/sora_data_channel_controller_test.dart` に追加されている（短すぎるデータ・デコード失敗・再 offer 維持・`header` 欠落・`header: null`・`header` が List 以外の型・`length` 欠落時の 26 バイト固定切り出し・複数ヘッダー時のオフセット計算を含む）
- [ ] 2 接続を利用し、受信した `senderConnectionId` が送信側の `SoraConnection.connectionId` と一致する E2E テストが `custom_data_channel_e2e_test.dart` に追加されている（`direction: 'sendrecv'` のカスタムラベルに `'header': [{'type': 'sender_connection_id'}]` を指定し、compress あり / なしの両方で検証する）。`header` はヘッダーを付与する受信側の接続に指定する。既存テストの `data` の期待値はヘッダー付きの値へ更新し、必要に応じて `payload` での検証へ変更する
- [ ] `README.md` に `header` の指定方法と受信方法が記載されている
- [ ] `SoraConnectionConfig.dataChannels` の DartDoc に `header` キーが記載されている
- [ ] モックやスタブを使用していない
- [ ] `flutter analyze` と関連するテストが成功する
