# Windows VideoFormat 重複除去ロジックを改善する

- Priority: Low
- Created: 2026-06-19
- Completed: 2026-06-19
- Model: DeepSeek V4 Pro
- Branch: feature/fix-windows-video-format-dedup
- Polished: 2026-06-19

## 目的

`SoraCameraCapturer::GetFormats()` の重複除去ロジックが 640x480、1280x720、1920x1080 の 3 解像度にしか対応しておらず、それ以外の解像度では同一解像度のメディアタイプが重複して返される。結果として Dart 側のフォーマット一覧 UI に重複した解像度が表示される可能性がある。

## 優先度根拠

- Low: 多くの一般的な Web カメラは 640x480 / 1280x720 / 1920x1080 のいずれかの解像度をサポートしており、実用上の影響は限定的。ただしバグとしての性質は明確で、修正も容易。

## 現状

`windows/sora_camera_capturer.cpp:143-195` の重複除去は 3 つの bool フラグによるハードコードで実装されている:

```cpp
bool seen_640x480 = false;
bool seen_1280x720 = false;
bool seen_1920x1080 = false;

for (DWORD type_index = 0;; ++type_index) {
  // ...
  if (width == 640 && height == 480) {
    if (seen_640x480) duplicate = true;
    seen_640x480 = true;
  } else if (width == 1280 && height == 720) {
    if (seen_1280x720) duplicate = true;
    seen_1280x720 = true;
  } else if (width == 1920 && height == 1080) {
    if (seen_1920x1080) duplicate = true;
    seen_1920x1080 = true;
  }
  // 上記 3 解像度以外は duplicate = false のまま
```

現状の重複除去は同一解像度の初出のみを保持し、2 回目以降をスキップする（コードコメントには「最大 FPS のみ保持する」とあるが、実際には FPS の大小比較は行っていない）。

## 設計方針

### ハードコードを `std::set` による汎用重複除去に置き換える

固定の 3 解像度をハードコードする代わりに、`std::set<std::pair<UINT32, UINT32>>` で処理済みの解像度を追跡する。ループの各イテレーションで解像度ペアの `set` に対する `emplace()` を試行し、既存要素と重複する場合はスキップする。

```cpp
#include <set>

std::set<std::pair<UINT32, UINT32>> seen_resolutions;

for (DWORD type_index = 0;; ++type_index) {
  // ...
  auto [it, inserted] = seen_resolutions.emplace(width, height);
  if (!inserted) {
    media_type->Release();
    continue;
  }
  // 結果に追加（ループ末尾の media_type->Release() に到達する）
```

### サブタイプの扱い

同一解像度でもサブタイプ（NV12 / YUY2 / MJPG 等）が異なるメディアタイプは別フォーマットとして扱うべきだが、現行コードも解釈度のみで重複判定しており、本変更でも同一の基準を維持する。これは現行動作と同等であり、退行ではない。

### ループ末尾の解放

既存のループ末尾の `media_type->Release()` は維持する。重複時は `continue` によりこの行に到達しないため、二重解放は発生しない。

## 完了条件

- `GetFormats()` の重複除去が任意の解像度（640x480、1280x720、1920x1080 以外を含む）で正しく機能すること
- `flutter build windows --release` が成功すること
- 変更内容が `CHANGES.md` に追記されること

## 解決方法

### 変更対象

- `windows/sora_camera_capturer.cpp` — `GetFormats()` の重複除去ロジックと include 追加

### 変更内容

1. `sora_camera_capturer.cpp` の include 一覧に `#include <set>` を追加する
2. `bool seen_640x480 / seen_1280x720 / seen_1920x1080` の 3 変数と if-else チェーンを削除する
3. 代わりに `std::set<std::pair<UINT32, UINT32>> seen_resolutions` をループ前に宣言する
4. `emplace()` の戻り値で重複判定を行う
5. 重複時は `media_type->Release()` を呼んで `continue`、非重複時は既存の結果追加処理を実行する
6. 既存のループ末尾 `media_type->Release()` はそのまま維持する

### テスト戦略

AGENTS.md の「モックやスタブは絶対に利用しないこと」に従い、以下の方法で動作確認する:
- e2e_test_app の Windows ビルドで実際のカメラデバイスを使用し、`enumerateVideoInputDevices` / `getVideoInputFormats` が正常動作することを確認
- 複数の解像度をサポートするカメラでフォーマット一覧に重複が含まれないことを目視確認
- カメラが存在しない環境では CI のビルド成功のみで代替（`GetFormats` はカメラ未接続時は空リストを返すため、クラッシュしないことの確認は可能）
