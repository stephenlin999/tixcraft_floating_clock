# Tixcraft Floating Time

一個非常輕量的 macOS 浮動時間視窗，時間來源是 `https://tixcraft.com/activity` 回應標頭。

> 非官方工具，與拓元售票沒有隸屬或合作關係。

## 系統需求

- macOS 12 或更新版本
- Xcode Command Line Tools（需提供 `swiftc`）

## 使用

```zsh
git clone https://github.com/stephenlin999/tixcraft_floating_clock.git
cd tixcraft_floating_clock
./build_app.sh
open TixcraftTime.app
```

或直接：

```zsh
./run.sh
```

## 行為

- 視窗固定在最前方，且會出現在所有 Space。
- 可拖曳移動。
- 顯示格式為 `HH:mm:ss.SS`，後兩位是百分之一秒。
- 每 15 秒重新向 `tixcraft.com/activity` 校時。
- 優先使用 tixcraft 回應標頭中的 `X-Timer` 小數秒時間戳；若沒有，才退回 HTTP `Date`。
- 退回 `Date` 時會短暫追蹤換秒邊界，讓小數秒比單次讀 header 更穩。
- 校時後使用 macOS 單調時鐘推進，不依賴系統時鐘每秒更新。
- 顯示時間為 Asia/Taipei。
- 關閉視窗時會停止更新 Timer、取消同步中的網路請求並結束程序。

## 建置產物

`build_app.sh` 會直接以 `swiftc` 編譯 AppKit 程式，建立標準的 `TixcraftTime.app` Bundle，加入圖示後進行 ad-hoc code signing。輸出的 App 會使用執行建置之 Mac 的原生架構。

若要建立可分享的壓縮 DMG：

```zsh
hdiutil create \
  -volname TixcraftTime \
  -srcfolder TixcraftTime.app \
  -ov \
  -format UDZO \
  TixcraftTime.dmg
```

ad-hoc 簽章未包含 Apple Developer ID 與 notarization，其他 Mac 第一次開啟時仍可能顯示 Gatekeeper 提示。

## 時間來源說明

tixcraft /activity 內 HTTP response header 會包含同網域的 `X-Timer` 與 `Date`，因此目前用它作為 tixcraft 網域時間錨點。

HTTP `Date` 標準只提供到秒，不提供毫秒。`X-Timer` 有小數秒，但它看起來是 Varnish/CDN 層時間，不一定是 tixcraft 應用程式內部售票判斷用的時鐘；若 tixcraft 之後提供毫秒級 server time API，才能做到真正毫秒級完全一致。
