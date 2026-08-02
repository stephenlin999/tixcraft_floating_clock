# Tixcraft Floating Time

<table>
<tr>
<th width="50%">繁體中文</th>
<th width="50%">English</th>
</tr>
<tr>
<td valign="top">

<p>一個輕量的 macOS 浮動時間視窗，使用 <code>https://tixcraft.com/activity</code> 的 HTTP 回應標頭估算拓元網域時間。</p>

<p><strong>非官方工具</strong>：本專案與拓元售票沒有隸屬或合作關係。</p>

<h3>功能</h3>
<ul>
<li>視窗固定在最前方，可出現在所有 Space。</li>
<li>支援拖曳移動。</li>
<li>顯示 <code>HH:mm:ss.SS</code>，後兩位為百分之一秒。</li>
<li>每 15 秒重新校時。</li>
<li>優先使用 <code>X-Timer</code>，退回 HTTP <code>Date</code>。</li>
<li>關閉時停止 Timer、取消網路請求並結束程序。</li>
</ul>

<h3>系統需求</h3>
<ul>
<li>macOS 12 或更新版本</li>
<li>Xcode Command Line Tools，需提供 <code>swiftc</code></li>
</ul>

</td>
<td valign="top">

<p>A lightweight macOS floating clock that estimates the time of the Tixcraft domain from HTTP response headers at <code>https://tixcraft.com/activity</code>.</p>

<p><strong>Unofficial tool</strong>: this project is not affiliated with or endorsed by Tixcraft.</p>

<h3>Features</h3>
<ul>
<li>Always-on-top floating window across Spaces.</li>
<li>Draggable window.</li>
<li>Displays <code>HH:mm:ss.SS</code> with hundredths of a second.</li>
<li>Resynchronizes every 15 seconds.</li>
<li>Uses <code>X-Timer</code> first and falls back to HTTP <code>Date</code>.</li>
<li>Stops timers, cancels requests, and exits cleanly on close.</li>
</ul>

<h3>Requirements</h3>
<ul>
<li>macOS 12 or later</li>
<li>Xcode Command Line Tools with <code>swiftc</code></li>
</ul>

</td>
</tr>
<tr>
<td valign="top">

<h3>快速開始</h3>
<pre><code>git clone https://github.com/stephenlin999/tixcraft_floating_clock.git
cd tixcraft_floating_clock
./build_app.sh
open TixcraftTime.app</code></pre>

<p>也可以直接執行 <code>./run.sh</code>。</p>

</td>
<td valign="top">

<h3>Quick Start</h3>
<pre><code>git clone https://github.com/stephenlin999/tixcraft_floating_clock.git
cd tixcraft_floating_clock
./build_app.sh
open TixcraftTime.app</code></pre>

<p>You can also run <code>./run.sh</code> directly.</p>

</td>
</tr>
<tr>
<td valign="top">

<h3>技術方式</h3>
<p>程式以 Swift/AppKit 建置，對目標網址發送 HEAD request。它使用 RTT 中點補償網路延遲，校時後以 macOS 單調時鐘推進，避免依賴系統時鐘每秒更新。</p>

<p>HTTP <code>Date</code> 只精確到秒；<code>X-Timer</code> 帶有小數秒，但通常代表 CDN/edge 時間，不一定是售票應用程式的 origin 時鐘。因此本工具不能保證與售票判斷時鐘完全一致。</p>

<p>tixcraft <code>/activity</code> 的 HTTP response header 會包含同網域的 <code>X-Timer</code> 與 <code>Date</code>，因此目前用它作為 tixcraft 網域時間錨點。</p>

</td>
<td valign="top">

<h3>Technical Approach</h3>
<p>The app is written in Swift/AppKit and sends a HEAD request to the target URL. It uses the RTT midpoint to compensate for network delay, then advances the synchronized time with macOS monotonic uptime instead of relying on per-second system-clock updates.</p>

<p>HTTP <code>Date</code> has only second-level precision. <code>X-Timer</code> includes fractional seconds but usually represents CDN/edge time rather than the ticketing application's origin clock, so the displayed time is not guaranteed to exactly match the ticketing decision clock.</p>

<p>The <code>/activity</code> response exposes both <code>X-Timer</code> and <code>Date</code> headers, which are used as the current time anchor for the Tixcraft domain.</p>

</td>
</tr>
<tr>
<td valign="top">

<h3>未來開發（規劃中）</h3>
<p>目標是從單一網站時鐘，演進成可驗證、可擴充、尊重隱私的 edge-time toolkit。</p>
<ul>
<li><strong>多來源時間設定檔</strong>：支援自訂網址與不同售票平台的時間來源。</li>
<li><strong>同步信心視覺化</strong>：把 offset、RTT、jitter 與估計誤差整理成可讀的信心狀態。</li>
<li><strong>開賣倒數與提示</strong>：倒數、音效與可調提前量，但不自動購票或執行結帳。</li>
<li><strong>可重播的網路測試</strong>：模擬延遲、封包抖動、錯誤標頭與斷線情境。</li>
<li><strong>正式發佈流程</strong>：Universal Binary、CI 建置、簽章與 notarization。</li>
</ul>

</td>
<td valign="top">

<h3>Proposed Roadmap</h3>
<p>The goal is to evolve from a single-site clock into a verifiable, extensible, privacy-conscious edge-time toolkit.</p>
<ul>
<li><strong>Multi-source profiles</strong>: support custom endpoints and time-source profiles for different ticketing platforms.</li>
<li><strong>Synchronization confidence</strong>: make offset, RTT, jitter, and estimated error understandable at a glance.</li>
<li><strong>Sale countdown and alerts</strong>: countdowns, sound cues, and configurable lead time without automating purchases or checkout.</li>
<li><strong>Replayable network tests</strong>: simulate latency, jitter, malformed headers, and connection failures.</li>
<li><strong>Release-grade distribution</strong>: Universal Binary builds, CI packaging, signing, and notarization.</li>
</ul>

</td>
</tr>
<tr>
<td valign="top">

<h3>安全與限制</h3>
<p>本程式不要求帳號、不處理憑證或付款資料，也不自動購票或執行結帳流程。它只讀取目標 HTTP 回應標頭，並在關閉時取消 Timer 與 URLSession 工作。</p>

</td>
<td valign="top">

<h3>Security and Scope</h3>
<p>The app requires no account, credentials, or payment data. It does not automate ticket purchases or checkout. It only reads HTTP response headers from the target and cancels its timers and URLSession work during shutdown.</p>

</td>
</tr>
</table>

## Repository / 儲存庫

<p><a href="https://github.com/stephenlin999/tixcraft_floating_clock">GitHub: stephenlin999/tixcraft_floating_clock</a></p>
