# Fetches TWSE / TAIFEX data needed for the dashboard.
# Outputs JSON snapshot files into the given -OutDir, plus a summary object as JSON (data.json)
# that build_html.ps1 consumes. Designed to be re-run daily; auto-detects the latest 3 trading days.
#
# Uses TWSE's classic www.twse.com.tw/rwd endpoints for the TAIEX index and
# all-stock daily quotes. The newer openapi.twse.com.tw REST feeds
# (STOCK_DAY_ALL / MI_INDEX) were tried first but lag same-day publication
# by many hours (sometimes a full day), while the classic endpoints are
# already live shortly after market close.

param(
    [string]$OutDir = "$PSScriptRoot\..\data"
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }

$headers = @{ "User-Agent" = "Mozilla/5.0"; "Accept" = "application/json" }

function Get-ChangeSign($cellHtml) {
    if ($cellHtml -match 'red') { return 1 }
    elseif ($cellHtml -match 'green') { return -1 }
    else { return 0 }
}

function Get-MiIndexIND([string]$dateStr) {
    try {
        $uri = "https://www.twse.com.tw/rwd/zh/afterTrading/MI_INDEX?response=json&date=$dateStr&type=IND"
        $resp = Invoke-RestMethod -Uri $uri -Headers $headers -TimeoutSec 30
        if ($resp.stat -eq "OK" -and $resp.tables -and $resp.tables[0].data -and $resp.tables[0].data.Count -gt 0) { return $resp }
        return $null
    } catch { return $null }
}

Write-Host "== Finding latest trading day (via TAIEX index) =="
$cursor = Get-Date
$latestDate = $null
$miResp = $null
$attempts = 0
while (-not $latestDate -and $attempts -lt 10) {
    $dateStr = $cursor.ToString("yyyyMMdd")
    $resp = Get-MiIndexIND $dateStr
    if ($resp) {
        $latestDate = $cursor
        $miResp = $resp
    } else {
        $cursor = $cursor.AddDays(-1)
    }
    $attempts++
}
if (-not $latestDate) { throw "Could not find a recent trading day via MI_INDEX" }
Write-Host "Latest trading day detected: $($latestDate.ToString('yyyy-MM-dd'))"
$latestDateStr = $latestDate.ToString("yyyyMMdd")

Write-Host "== Fetching TAIEX close/change =="
$indexRows = $miResp.tables[0].data | ForEach-Object {
    [PSCustomObject]@{
        指數     = $_[0]
        收盤指數   = $_[1]
        漲跌     = if ($_[2] -match 'red') { '+' } elseif ($_[2] -match 'green') { '-' } else { '' }
        漲跌點數   = $_[3]
        漲跌百分比  = $_[4]
    }
}
$indexRows | ConvertTo-Json -Depth 5 | Out-File "$OutDir\mi_index.json" -Encoding utf8

function Get-AllBut0999Stocks([string]$dateStr) {
    $allBut = Invoke-RestMethod -Uri "https://www.twse.com.tw/rwd/zh/afterTrading/MI_INDEX?response=json&date=$dateStr&type=ALLBUT0999" -Headers $headers -TimeoutSec 30
    $stockTable = $allBut.tables[8]
    return $stockTable.data | ForEach-Object {
        $closingRaw = $_[8]
        if ($closingRaw -match '^[\d,\.]+$') {
            $sign = Get-ChangeSign $_[9]
            $diff = [double](($_[10] -replace ',', ''))
            [PSCustomObject]@{ Code = $_[0]; Name = $_[1]; ClosingPrice = ($closingRaw -replace ',', ''); Change = [string]($sign * $diff) }
        } else {
            [PSCustomObject]@{ Code = $_[0]; Name = $_[1]; ClosingPrice = ''; Change = '' }
        }
    }
}

Write-Host "== Fetching all-stock daily quotes (gainers/losers, breadth) =="
$stockDayAll = Get-AllBut0999Stocks $latestDateStr
$stockDayAll | ConvertTo-Json -Depth 5 | Out-File "$OutDir\stock_day_all.json" -Encoding utf8

function Test-T86Date([string]$dateStr) {
    try {
        $uri = "https://www.twse.com.tw/rwd/zh/fund/T86?response=json&date=$dateStr&selectType=ALL"
        $resp = Invoke-RestMethod -Uri $uri -Headers $headers -TimeoutSec 30
        if ($resp.stat -eq "OK" -and $resp.data -and $resp.data.Count -gt 0) { return $resp }
        return $null
    } catch { return $null }
}

Write-Host "== Walking backward to find 3 consecutive trading days for T86 =="
$foundDates = @()
$cursor = $latestDate
$attempts = 0
while ($foundDates.Count -lt 3 -and $attempts -lt 15) {
    $dateStr = $cursor.ToString("yyyyMMdd")
    $result = Test-T86Date $dateStr
    if ($result) {
        $foundDates += [PSCustomObject]@{ Date = $cursor; DateStr = $dateStr; Data = $result }
        Write-Host "  found trading day: $dateStr"
    } else {
        Write-Host "  skip (not a trading day / no data): $dateStr"
    }
    $cursor = $cursor.AddDays(-1)
    $attempts++
}

if ($foundDates.Count -lt 3) { throw "Could not find 3 trading days of T86 data" }

# foundDates[0] = most recent (D3), [1] = D2, [2] = D1
for ($i = 0; $i -lt 3; $i++) {
    $foundDates[$i].Data | ConvertTo-Json -Depth 5 | Out-File "$OutDir\t86_day$i.json" -Encoding utf8
}
$foundDates | ForEach-Object { $_.DateStr } | Out-File "$OutDir\t86_dates.txt" -Encoding utf8

Write-Host "== Fetching per-stock quotes for the same 3 trading days (for consecutive limit-up/down streaks) =="
for ($i = 0; $i -lt 3; $i++) {
    $dayStocks = if ($foundDates[$i].DateStr -eq $latestDateStr) { $stockDayAll } else { Get-AllBut0999Stocks $foundDates[$i].DateStr }
    $dayStocks | ConvertTo-Json -Depth 5 | Out-File "$OutDir\stock_day$i.json" -Encoding utf8
}

Write-Host "== Fetching market-wide institutional NT`$ totals (BFI82U) =="
$bfi = Invoke-RestMethod -Uri "https://www.twse.com.tw/rwd/zh/fund/BFI82U?response=json&dayDate=$($foundDates[0].DateStr)&type=day" -Headers $headers -TimeoutSec 30
$bfi | ConvertTo-Json -Depth 5 | Out-File "$OutDir\bfi82u.json" -Encoding utf8

Write-Host "== Fetching TAIFEX TX futures (market expectation term structure) =="
$fut = Invoke-RestMethod -Uri "https://openapi.taifex.com.tw/v1/DailyMarketReportFut" -Headers $headers -TimeoutSec 60
$txAll = $fut | Where-Object { $_.Contract -eq "TX" -and $_.TradingSession -eq "一般" }
# TAIFEX's open-data feed can lag the TWSE data by its own margin, so use
# its own latest available date rather than forcing an exact match to the
# stock-market date above.
$txLatestDate = $txAll | Select-Object -ExpandProperty Date -Unique | Sort-Object -Descending | Select-Object -First 1
$txRows = $txAll | Where-Object { $_.Date -eq $txLatestDate }
Write-Host "  TX futures as of: $txLatestDate"
$txRows | ConvertTo-Json -Depth 5 | Out-File "$OutDir\tx_futures.json" -Encoding utf8

Write-Host "`nAll raw data fetched into $OutDir"
Write-Host "Latest date: $($foundDates[0].DateStr) | Prior: $($foundDates[1].DateStr) | Prior-2: $($foundDates[2].DateStr)"
