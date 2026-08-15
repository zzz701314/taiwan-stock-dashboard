# 台股盤後戰情室 — 每日自動更新

**已發布網址（固定不變）**：https://claude.ai/code/artifact/8110dce4-6b03-418b-bba9-6443f4848a6c

## 這是什麼

一個台股盤後資料儀表板：加權指數、市場期望值（台指期近月/次月）、漲跌幅前10大、
外資/投信連續3日買超與賣超排行、自製恐懼貪婪指數。資料來源為台灣證交所（TWSE）
OpenAPI 與台灣期貨交易所（TAIFEX）OpenAPI，皆為公開資料，免金鑰。

## 每日更新怎麼跑（給排程 agent 看）

在專案目錄（`D:\台股分析 claude`）下依序執行：

```powershell
& ".\scripts\fetch_data.ps1"
& ".\scripts\build_html.ps1"
```

- `fetch_data.ps1`：自動抓取「最近一個交易日」的資料（不需要手動指定日期，會自動往回找
  最近 3 個有效交易日給三大法人連續買賣超統計用，遇到假日/非交易日會自動跳過）。
  輸出到 `data\` 目錄。
- `build_html.ps1`：讀取 `data\*.json`，計算所有排行榜與恐懼貪婪指數，套用
  `scripts\template\` 下的樣板，輸出 `dashboard.html`。

跑完之後，用 Artifact 工具把 `dashboard.html` 發布回**同一個網址**（一定要帶
`url` 參數＝上面那個固定網址，否則會變成建立一個新的 artifact）：

```
Artifact({
  file_path: "D:\\台股分析 claude\\dashboard.html",
  url: "https://claude.ai/code/artifact/8110dce4-6b03-418b-bba9-6443f4848a6c",
  favicon: "📈"
})
```

## 失敗時怎麼辦

- 若 `fetch_data.ps1` 找不到 3 個交易日（連續假期太長）會拋出例外，屬於正常保護機制，
  不需要重跑，等下一個排定時間即可。
- 若 TWSE/TAIFEX 網站暫時無回應，直接重試整個流程一次即可，不需修改程式。
- 若真的需要修改樣板／版面，改 `scripts\template\tmpl_part3.html` 裡的 `{{TOKEN}}`
  即可，`build_html.ps1` 會自動代入資料。字型（Consolas 用於數字）已內嵌於
  `scripts\template\consola.b64` / `consolab.b64`，不需要每次重新產生。

## 已知限制 / 設計取捨

- 「漲停/跌停」係以當日漲跌幅 ≥9.5%（跌停 ≤-9.5%）判定，因跳動點制可能與交易所
  實際鎖漲跌停價格有些微誤差，僅供參考。
- 恐懼貪婪指數為自製簡化版（市場寬度、大盤動能、漲跌停家數比、法人資金流向四項
  平均），非 CNN 或 MacroMicro 官方數值，頁面內有清楚標示與官方連結。
- 三大法人買賣超僅計算一般上市普通股（4碼代號），排除 ETF、權證、TDR、債券。
