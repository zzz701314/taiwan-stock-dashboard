# Fetches TWSE / TAIFEX data needed for the dashboard.
# Outputs JSON snapshot files into the given -OutDir, plus a summary object as JSON (data.json)
# that build_html.ps1 consumes. Designed to be re-run daily; auto-detects the latest 3 trading days.

param(
    [string]$OutDir = "$PSScriptRoot\..\data"
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }

$headers = @{ "User-Agent" = "Mozilla/5.0"; "Accept" = "application/json" }

function Roc-ToDate($rocStr) {
    # rocStr like "1150814" -> 2026-08-14
    $y = [int]$rocStr.Substring(0,3) + 1911
    $m = [int]$rocStr.Substring(3,2)
    $d = [int]$rocStr.Substring(5,2)
    return Get-Date -Year $y -Month $m -Day $d
}

Write-Host "== Fetching latest stock day data (auto-detects most recent trading day) =="
$stockDayAll = Invoke-RestMethod -Uri "https://openapi.twse.com.tw/v1/exchangeReport/STOCK_DAY_ALL" -Headers $headers -TimeoutSec 30
$stockDayAll | ConvertTo-Json -Depth 5 | Out-File "$OutDir\stock_day_all.json" -Encoding utf8

$latestRoc = $stockDayAll[0].Date
$latestDate = Roc-ToDate $latestRoc
Write-Host "Latest trading day detected: $($latestDate.ToString('yyyy-MM-dd'))"

Write-Host "== Fetching TAIEX close/change =="
$miIndex = Invoke-RestMethod -Uri "https://openapi.twse.com.tw/v1/exchangeReport/MI_INDEX" -Headers $headers -TimeoutSec 30
$miIndex | ConvertTo-Json -Depth 5 | Out-File "$OutDir\mi_index.json" -Encoding utf8

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

Write-Host "== Fetching market-wide institutional NT`$ totals (BFI82U) =="
$bfi = Invoke-RestMethod -Uri "https://www.twse.com.tw/rwd/zh/fund/BFI82U?response=json&dayDate=$($foundDates[0].DateStr)&type=day" -Headers $headers -TimeoutSec 30
$bfi | ConvertTo-Json -Depth 5 | Out-File "$OutDir\bfi82u.json" -Encoding utf8

Write-Host "== Fetching TAIFEX TX futures (market expectation term structure) =="
$fut = Invoke-RestMethod -Uri "https://openapi.taifex.com.tw/v1/DailyMarketReportFut" -Headers $headers -TimeoutSec 60
$txRows = $fut | Where-Object { $_.Contract -eq "TX" -and $_.Date -eq $foundDates[0].DateStr -and $_.TradingSession -eq "一般" }
$txRows | ConvertTo-Json -Depth 5 | Out-File "$OutDir\tx_futures.json" -Encoding utf8

Write-Host "`nAll raw data fetched into $OutDir"
Write-Host "Latest date: $($foundDates[0].DateStr) | Prior: $($foundDates[1].DateStr) | Prior-2: $($foundDates[2].DateStr)"
