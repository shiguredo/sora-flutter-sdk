# devtools: 非対応コーデックで answer が拒否されたリモート映像が切断後も残り続けるバグを修正する

- Created: 2026-09-14
- Completed: {YYYY-MM-DD}
- Branch: feature/fix-devtools-destroyed-remote-track-cleanup
- Polished: 2026-09-14

## 目的

受信側が対応していないコーデック（例: Linux + H.264）の m-line を Sora が送信側から受けた場合、devtools の Video タブに黒画面のセルが現れ、相手端末が切断しても消えないバグを修正する。対策は devtools 側で行い、SDK（`lib/`）と libwebrtc / ネイティブ側は変更しない。

## 現状

再現環境は Linux の devtools（recvonly、多人数チャネル接続）と、H.264 を送信する sendrecv クライアントの組み合わせ。`README.md` の対応コーデック表のとおり、ソフトウェアバックエンドは全プラットフォームで VP8 / VP9 / AV1 のみであり、ハードウェアアクセラレータに該当しない Linux は H.264 をデコードできない。実ログでのイベントの流れは次のとおり。

1. Sora から re-offer が届き、相手の video m-line に H.264 のみが含まれる（sendonly）。
2. libwebrtc が OnTrack を発火し、SDK が onDebugMessage 経由で `remote_track_attached`（renderer / texture 生成）を出力する。これが黒画面の実体（フレームは届かないため黒表示になる）。
3. CreateAnswer では H.264 非対応のため該当 video m-line が port 0 として拒否されるが、libwebrtc は answer 拒否に起因する track 除去を OnRemoveTrack として発火しない（リモート SDP 由来の除去のみ報告する仕様。ブラウザの `removetrack` も同様の関係になる）。実ログでも相手切断時の再ネゴシエーションで `native: onremovetrack kind=audio` だけが発火している。
4. そのため SDK の `SoraRemoveTrackEvent` は発生せず、devtools の `remoteVideos` にトラックが残り続ける。

devtools 側の現状は次のとおり。

- リモートトラックの表示管理: `devtools/lib/src/devtools_event_handler.dart` は `SoraRemoveTrackEvent` を受けて `DevToolsPageNotifier.removeRemoteTrack`（`devtools/lib/src/devtools_models.dart`）で track 単位に削除する。`notify` の `connection.destroyed` は `DevToolsPageNotifier.remoteClients` の掃除にのみ使われており（`devtools/lib/main.dart` の `_updateRemoteClients`）、`remoteVideos` / `remoteAudios` は削除していない。
- SDK は `notify` を `SoraNotifyEvent` として公開しており、`connection.destroyed` の `event_type` は `SoraNotifyEvent` の `message` から参照できる。

参考として、ブラウザ版の sora-devtools（別リポジトリ）は相手切断時の UI 掃除を `notify` の `connection.destroyed` で駆動しており、WebRTC の `removetrack` に依存していない。iOS サンプル（sora-ios-sdk samples）は audio + video を 1 つの RTCMediaStream 単位で扱うため、音声 m-line の除去で映像も一緒に外れる。

## 設計方針

- **libwebrtc は変更しない**。本 issue では「answer 拒否で消えた m-line の track について OnRemoveTrack が発火しない」ことを、libwebrtc の仕様として扱う。SDK（`lib/`）のイベント契約も変更しない。
- **devtools 側で `connection.destroyed` に対処する**。`SoraNotifyEvent` の `event_type == 'connection.destroyed'` を受けたら、該当 `connection_id` に属するリモートトラックを接続単位で削除し、`remoteClients` の既存の削除と合わせて保存状態を整合させる。
  - 削除対象: `DevToolsPageNotifier.remoteVideos` / `remoteAudios`（`connectionId` が一致する要素）。
  - 実装場所: `devtools/lib/main.dart` の `_updateRemoteClients`（`connection.destroyed` 分岐）と、`devtools/lib/src/devtools_models.dart` の接続単位削除ヘルパ。
  - `SoraRemoveTrackEvent`（track 単位）による既存の削除はそのまま維持する。両経路が同じ track を削除しても `removeWhere` は冪等で、接続単位の削除は後から同じ track を消しても表示に影響しない。Video タブ (`devtools_video_panel.dart`) は `remoteVideos` の `List` を直接参照するため、削除後の再描画に特別な対応は不要。
- `remoteClients`（接続情報ラベル）の削除は現状の実装を維持し、削除順序や既存動作は変えない。

## 完了条件

- [ ] Linux + H.264 のシナリオ（多人数チャネル、recvonly）で、相手端末の切断後に devtools の Video タブから黒画面セルが消える（`native: onremovetrack` が発火しない場合でも消える）。
- [ ] `connection.destroyed` 通知で、該当 `connection_id` の `remoteVideos` / `remoteAudios` / `remoteClients` が同時に削除され状態が整合する。
- [ ] 対応コーデック（VP8 / VP9 / AV1）の通常受信・切断では従来と挙動が変わらない。`SoraRemoveTrackEvent` が先に届く正常系では従来どおり track 単位で消え、`connection.destroyed` 経由と競合しても二重削除エラーにならない。
- [ ] `connection.destroyed` を受けて接続単位でトラックを消す処理のユニットテストが `devtools/test/` に追加され、`flutter analyze --fatal-infos` が成功する。

## 解決方法

- `devtools/lib/src/devtools_models.dart`: 接続単位で `remoteVideos` / `remoteAudios` を削除するヘルパ（例: `removeRemoteTracksByConnectionId(String connectionId)`）を追加し、`removeRemoteTrack` と同様に `notifyListeners` 周りは `_mutateView` 経由の規約に従う。
- `devtools/lib/main.dart`: `_updateRemoteClients` の `connection.destroyed` 分岐で、該当 `connection_id` に対して上記ヘルパを呼ぶ。
- `devtools/test/devtools_models_test.dart`: `connection.destroyed` 相当の削除（接続単位）と、track 単位 / 接続単位の二重削除が冪等であることを検証するユニットテストを追加する。
- `CHANGELOG.md` への記載は正式リリース前のため行わない（`CODEBASE.md` の「正式リリース前」節に従う）。正式リリース確定時に `[FIX]` として追記する。

## 関連

- `issues/closed/0012-test-add-remote-media-streams-e2e-coverage.md`（相手切断時の `RemoteMediaStream` 除去の既存 E2E。SDK 側契約の確認として参照）
- ブラウザ版 sora-devtools の実装（別リポジトリ。`connection.destroyed` notify 駆動の参考実装）
