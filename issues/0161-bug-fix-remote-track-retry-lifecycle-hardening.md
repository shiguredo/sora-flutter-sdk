# `RemoteTrackManager` の retry 機構と世代・並行制御の相互作用を硬化する

- Created: 2026-09-07
- Completed: {YYYY-MM-DD}
- Branch: feature/fix-remote-track-retry-lifecycle-hardening
- Polished: {YYYY-MM-DD}

## 目的

破棄再試行待ち entry が世代切り替えや並行処理と組み合わさったときに漏れる経路をなくすこと。

## 現状

`lib/src/sora_remote_track_manager.dart` の `RemoteTrackManager._disposeRetryEntries` は破棄失敗時に entry を保持し、次回 `RemoteTrackManager.detachAllRemoteVideoTracks` で回収する。次の相互作用が未定義である。

- 同一 `trackAddress` の再利用時に `_RemoteTrackEntry` が新旧で併存し、集合の重複排除で新 entry が残置される。`trackAddress` はネイティブポインタ由来で再利用され得る。
- `_removedBeforeAttach` の残留条件が `detachAll` と `invalidateGeneration` の順序で非対称になる。
- 並行 `detachAll` は初回の完了を待つだけで再走査しないため、初回が退避した retry を回収しない。
- `_removeSinkFromTrack` の失敗時は entry がどちらの map にも残らず再試行不能になる。
- `clear` 後の再試行が古い `connectionId` に対する remove イベントを遅延発火する意味づけが未定義である。

## 設計方針

- retry entry に世代タグを付けるか、`clear` と `invalidateGeneration` での破棄方針を決める。
- 並行 `detachAll` の再走査可否を決める。
- 振る舞い変更と文書化に絞り、0156 で確定した参照収支は変えない。

## 完了条件

- [ ] 上記 5 件の相互作用が定義され、漏れなく回収されるか文書化される。
- [ ] 上記シナリオを exercise するユニットテストを追加する。
- [ ] `flutter analyze` と関連テストが成功する。

## 関連

- `issues/closed/0156-bug-fix-remote-track-manager-clear-leak.md` (retry 機構の導入)
