# Builds index.html from the data fetched by fetch_data.ps1.
# Reads D:\台股分析 claude\data\*.json and D:\台股分析 claude\scripts\template\*
# Outputs D:\台股分析 claude\index.html (index.html so GitHub Pages serves it at the site root)

param(
    [string]$DataDir = "$PSScriptRoot\..\data",
    [string]$TemplateDir = "$PSScriptRoot\template",
    [string]$OutFile = "$PSScriptRoot\..\index.html"
)

$ErrorActionPreference = "Stop"

function N0($x) { "{0:N0}" -f $x }
function Pct($x, [int]$decimals=2) {
    $s = "{0:N$decimals}" -f [math]::Abs($x)
    if ($x -lt 0) { return "－$s%" } else { return "+$s%" }
}
function Signed($x) {
    $s = "{0:N2}" -f [math]::Abs($x)
    if ($x -lt 0) { return "－$s" } else { return "+$s" }
}
function SignedInt($x) {
    $s = "{0:N0}" -f [math]::Abs($x)
    if ($x -lt 0) { return "－$s" } else { return "+$s" }
}
function HtmlEnc($s) { [System.Net.WebUtility]::HtmlEncode($s) }

# ---------- Load raw data ----------
$stockDayAll = Get-Content "$DataDir\stock_day_all.json" -Raw | ConvertFrom-Json
$miIndex     = Get-Content "$DataDir\mi_index.json" -Raw | ConvertFrom-Json
$bfi         = Get-Content "$DataDir\bfi82u.json" -Raw | ConvertFrom-Json
$txFut       = Get-Content "$DataDir\tx_futures.json" -Raw | ConvertFrom-Json
$t86Dates    = Get-Content "$DataDir\t86_dates.txt"
$t86_0       = Get-Content "$DataDir\t86_day0.json" -Raw | ConvertFrom-Json  # latest (D3)
$t86_1       = Get-Content "$DataDir\t86_day1.json" -Raw | ConvertFrom-Json  # D2
$t86_2       = Get-Content "$DataDir\t86_day2.json" -Raw | ConvertFrom-Json  # D1 (oldest)

$dateD3 = $t86Dates[0]; $dateD2 = $t86Dates[1]; $dateD1 = $t86Dates[2]
function FmtDate($yyyymmdd) {
    $d = [datetime]::ParseExact($yyyymmdd, "yyyyMMdd", $null)
    $wk = @("日","一","二","三","四","五","六")[[int]$d.DayOfWeek]
    return "$($d.ToString('yyyy/MM/dd'))（週$wk）"
}
$dataDateLabel = FmtDate $dateD3
$titleDate = ([datetime]::ParseExact($dateD3,"yyyyMMdd",$null)).ToString("yyyy.MM.dd")
$rangeLabel = "$($dateD1.Substring(4,2))/$($dateD1.Substring(6,2)) → $($dateD3.Substring(4,2))/$($dateD3.Substring(6,2))"
$rangeLabelShort = "D1=$($dateD1.Substring(4,2))/$($dateD1.Substring(6,2))　D2=$($dateD2.Substring(4,2))/$($dateD2.Substring(6,2))　D3=$($dateD3.Substring(4,2))/$($dateD3.Substring(6,2))"

$today = Get-Date
$latestDt = [datetime]::ParseExact($dateD3,"yyyyMMdd",$null)
$closedPill = ""
$holidayNote = ""
if ($today.Date -ne $latestDt.Date) {
    if ($today.DayOfWeek -eq [System.DayOfWeek]::Saturday -or $today.DayOfWeek -eq [System.DayOfWeek]::Sunday) {
        $closedPill = "<span class=`"closed-pill`">$($today.ToString('MM/dd'))休市或非交易日</span>"
    } else {
        $closedPill = "<span class=`"closed-pill`">$($today.ToString('MM/dd'))資料尚未發布，顯示最近交易日</span>"
    }
    $holidayNote = "（最近交易日）"
}

# ---------- TAIEX index ----------
$taiexRow = $miIndex | Where-Object { $_.指數-eq "發行量加權股價指數" } | Select-Object -First 1
$taiexClose = [double]$taiexRow.收盤指數
$taiexChangePts = [double]$taiexRow.漲跌點數
$taiexDir = $taiexRow.漲跌
if ($taiexDir -eq "-") { $taiexChangePts = -[math]::Abs($taiexChangePts) } else { $taiexChangePts = [math]::Abs($taiexChangePts) }
$taiexPctVal = [double]$taiexRow.漲跌百分比
$taiexDirClass = if ($taiexChangePts -lt 0) { "down" } else { "up" }
$taiexArrow = if ($taiexChangePts -lt 0) { "▼" } else { "▲" }

# ---------- TX futures term structure ----------
$txByMonth = $txFut | Where-Object { $_.'ContractMonth(Week)' -match '^\d{6}$' } | Sort-Object { $_.'ContractMonth(Week)' }
$txNear = $txByMonth[0]
$txNext = if ($txByMonth.Count -gt 1) { $txByMonth[1] } else { $txByMonth[0] }
$txNearSettle = [double]$txNear.SettlementPrice
$txNextSettle = [double]$txNext.SettlementPrice
$txNearBasis = $txNearSettle - $taiexClose
$txNextBasis = $txNextSettle - $taiexClose
$txNearMonth = $txNear.'ContractMonth(Week)'.Substring(4,2)
$txNextMonth = $txNext.'ContractMonth(Week)'.Substring(4,2)
$txNextDirClass = if ($txNextBasis -lt 0) { "down" } else { "up" }

# ---------- Equities: gainers / losers / breadth ----------
$equities = $stockDayAll | Where-Object { $_.Code -match '^[1-9]\d{3}$' -and $_.ClosingPrice -ne '' -and $_.Change -ne '' }
$calc = $equities | ForEach-Object {
    $close = [double]$_.ClosingPrice
    $chg = [double]$_.Change
    $prevClose = $close - $chg
    $pct = if ($prevClose -gt 0) { [math]::Round(($chg / $prevClose) * 100, 2) } else { 0 }
    [PSCustomObject]@{ Code=$_.Code; Name=($_.Name -replace '\s+$',''); Close=$close; Change=$chg; Pct=$pct }
}
$up = ($calc | Where-Object { $_.Change -gt 0 }).Count
$down = ($calc | Where-Object { $_.Change -lt 0 }).Count
$flat = ($calc | Where-Object { $_.Change -eq 0 }).Count
$limitUpCount = ($calc | Where-Object { $_.Pct -ge 9.5 }).Count
$limitDownCount = ($calc | Where-Object { $_.Pct -le -9.5 }).Count

$gainers = $calc | Sort-Object Pct -Descending | Select-Object -First 10
$losers  = $calc | Sort-Object Pct | Select-Object -First 10

function Build-MoveRows($rows, [bool]$isGain) {
    $sb = New-Object System.Text.StringBuilder
    foreach ($r in $rows) {
        $dirClass = if ($isGain) { "up" } else { "down" }
        $badge = ""
        if ($isGain -and $r.Pct -ge 9.9) { $badge = "<span class=`"limit-badge up`">漲停</span>" }
        elseif ((-not $isGain) -and $r.Pct -le -9.5) { $badge = "<span class=`"limit-badge down`">近跌停</span>" }
        $chgStr = Signed $r.Change
        $pctStr = Pct $r.Pct
        [void]$sb.AppendLine("            <tr><td>$($r.Code)</td><td>$(HtmlEnc $r.Name)$badge</td><td class=`"num`">$('{0:N2}' -f $r.Close)</td><td class=`"num $dirClass`">$chgStr</td><td class=`"num $dirClass`">$pctStr</td></tr>")
    }
    return $sb.ToString().TrimEnd()
}
$gainersRows = Build-MoveRows $gainers $true
$losersRows  = Build-MoveRows $losers $false

$limitNote = if ($limitUpCount -gt $limitDownCount * 2) { "漲停家數遠多於跌停，強勢股集中" }
             elseif ($limitDownCount -gt $limitUpCount * 2) { "跌停家數遠多於漲停，弱勢股集中" }
             else { "漲跌停家數大致平衡" }

# ---------- Limit-up / limit-down 3-day consecutive streaks ----------
$stockDay0 = Get-Content "$DataDir\stock_day0.json" -Raw | ConvertFrom-Json  # latest (D3)
$stockDay1 = Get-Content "$DataDir\stock_day1.json" -Raw | ConvertFrom-Json  # D2
$stockDay2 = Get-Content "$DataDir\stock_day2.json" -Raw | ConvertFrom-Json  # D1 (oldest)

function Load-PctMap($dayStocks) {
    $map = @{}
    foreach ($s in $dayStocks) {
        if ($s.Code -notmatch '^[1-9]\d{3}$' -or $s.ClosingPrice -eq '' -or $s.Change -eq '') { continue }
        $close = [double]$s.ClosingPrice
        $chg = [double]$s.Change
        $prevClose = $close - $chg
        $pct = if ($prevClose -gt 0) { [math]::Round(($chg / $prevClose) * 100, 2) } else { 0 }
        $map[$s.Code] = [PSCustomObject]@{ Name=($s.Name -replace '\s+$',''); Close=$close; Pct=$pct }
    }
    return $map
}
$sOld = Load-PctMap $stockDay2   # D1 oldest
$sMid = Load-PctMap $stockDay1   # D2
$sNew = Load-PctMap $stockDay0   # D3 latest

$streakCodes = $sNew.Keys | Where-Object { $sMid.ContainsKey($_) -and $sOld.ContainsKey($_) }
$streak3 = foreach ($c in $streakCodes) {
    [PSCustomObject]@{
        Code=$c; Name=$sNew[$c].Name
        P1=$sOld[$c].Pct; P2=$sMid[$c].Pct; P3=$sNew[$c].Pct
        Close=$sNew[$c].Close
    }
}
$limitUpStreak = $streak3 | Where-Object { $_.P1 -ge 9.5 -and $_.P2 -ge 9.5 -and $_.P3 -ge 9.5 } | Sort-Object { $_.P1 + $_.P2 + $_.P3 } -Descending
$limitDownStreak = $streak3 | Where-Object { $_.P1 -le -9.5 -and $_.P2 -le -9.5 -and $_.P3 -le -9.5 } | Sort-Object { $_.P1 + $_.P2 + $_.P3 }
$limitUpStreakCount = $limitUpStreak.Count
$limitDownStreakCount = $limitDownStreak.Count
$limitUpStreakTop = $limitUpStreak | Select-Object -First 10
$limitDownStreakTop = $limitDownStreak | Select-Object -First 10

function Build-LimitStreakRows($rows, [bool]$isUp) {
    if ($rows.Count -eq 0) {
        return "            <tr><td colspan=`"6`" style=`"text-align:center;color:var(--text-faint);`">目前無符合條件個股</td></tr>"
    }
    $dirClass = if ($isUp) { "up" } else { "down" }
    $sb = New-Object System.Text.StringBuilder
    foreach ($r in $rows) {
        [void]$sb.AppendLine("            <tr><td>$($r.Code)</td><td>$(HtmlEnc $r.Name)</td><td class=`"num $dirClass`">$(Pct $r.P1)</td><td class=`"num $dirClass`">$(Pct $r.P2)</td><td class=`"num $dirClass`">$(Pct $r.P3)</td><td class=`"num`">$('{0:N2}' -f $r.Close)</td></tr>")
    }
    return $sb.ToString().TrimEnd()
}
$limitUpStreakRows = Build-LimitStreakRows $limitUpStreakTop $true
$limitDownStreakRows = Build-LimitStreakRows $limitDownStreakTop $false

# ---------- Institutional 3-day consecutive flow ----------
function Load-T86Map($t86obj) {
    $map = @{}
    foreach ($row in $t86obj.data) {
        $code = ($row[0]).Trim()
        if ($code -notmatch '^[1-9]\d{3}$') { continue }
        $name = ($row[1]).Trim()
        $foreign = [double](($row[4] -replace ',','')) + [double](($row[7] -replace ',',''))
        $trust = [double](($row[10] -replace ',',''))
        $map[$code] = [PSCustomObject]@{ Name=$name; Foreign=$foreign; Trust=$trust }
    }
    return $map
}
$dOld = Load-T86Map $t86_2   # D1 oldest
$dMid = Load-T86Map $t86_1   # D2
$dNew = Load-T86Map $t86_0   # D3 latest

$codes = $dNew.Keys | Where-Object { $dMid.ContainsKey($_) -and $dOld.ContainsKey($_) }
$merged3 = foreach ($c in $codes) {
    [PSCustomObject]@{
        Code=$c; Name=$dNew[$c].Name
        F1=$dOld[$c].Foreign; F2=$dMid[$c].Foreign; F3=$dNew[$c].Foreign
        T1=$dOld[$c].Trust;   T2=$dMid[$c].Trust;   T3=$dNew[$c].Trust
    }
}

function Build-FlowRows($rows, [string]$field1, [string]$field2, [string]$field3, [bool]$isBuy) {
    $sb = New-Object System.Text.StringBuilder
    $dirClass = if ($isBuy) { "up" } else { "down" }
    foreach ($r in $rows) {
        $v1 = $r.$field1; $v2 = $r.$field2; $v3 = $r.$field3
        $maxAbs = [math]::Max([math]::Max([math]::Abs($v1),[math]::Abs($v2)),[math]::Abs($v3))
        if ($maxAbs -eq 0) { $maxAbs = 1 }
        $h1 = [math]::Max(4,[math]::Round([math]::Abs($v1)/$maxAbs*100))
        $h2 = [math]::Max(4,[math]::Round([math]::Abs($v2)/$maxAbs*100))
        $h3 = [math]::Max(4,[math]::Round([math]::Abs($v3)/$maxAbs*100))
        $total = $r.Total
        $totalStr = SignedInt ([math]::Round($total/1000))
        [void]$sb.AppendLine("            <tr><td>$($r.Code)</td><td>$(HtmlEnc $r.Name)</td><td><span class=`"spark`"><i class=`"$dirClass`" style=`"height:$h1%`"></i><i class=`"$dirClass`" style=`"height:$h2%`"></i><i class=`"$dirClass`" style=`"height:$h3%`"></i></span></td><td class=`"num $dirClass`">$totalStr</td></tr>")
    }
    return $sb.ToString().TrimEnd()
}

function CloneWithTotal($obj, $total) {
    [PSCustomObject]@{ Code=$obj.Code; Name=$obj.Name; F1=$obj.F1; F2=$obj.F2; F3=$obj.F3; T1=$obj.T1; T2=$obj.T2; T3=$obj.T3; Total=$total }
}
$foreignBuyAll = $merged3 | Where-Object { $_.F1 -gt 0 -and $_.F2 -gt 0 -and $_.F3 -gt 0 } | ForEach-Object { CloneWithTotal $_ ($_.F1+$_.F2+$_.F3) }
$foreignSellAll = $merged3 | Where-Object { $_.F1 -lt 0 -and $_.F2 -lt 0 -and $_.F3 -lt 0 } | ForEach-Object { CloneWithTotal $_ ($_.F1+$_.F2+$_.F3) }
$trustBuyAll = $merged3 | Where-Object { $_.T1 -gt 0 -and $_.T2 -gt 0 -and $_.T3 -gt 0 } | ForEach-Object { CloneWithTotal $_ ($_.T1+$_.T2+$_.T3) }
$trustSellAll = $merged3 | Where-Object { $_.T1 -lt 0 -and $_.T2 -lt 0 -and $_.T3 -lt 0 } | ForEach-Object { CloneWithTotal $_ ($_.T1+$_.T2+$_.T3) }

$foreignBuyCount = $foreignBuyAll.Count; $foreignSellCount = $foreignSellAll.Count
$trustBuyCount = $trustBuyAll.Count; $trustSellCount = $trustSellAll.Count

$foreignBuyTop = $foreignBuyAll | Sort-Object Total -Descending | Select-Object -First 10
$foreignSellTop = $foreignSellAll | Sort-Object Total | Select-Object -First 10
$trustBuyTop = $trustBuyAll | Sort-Object Total -Descending | Select-Object -First 10
$trustSellTop = $trustSellAll | Sort-Object Total | Select-Object -First 10

$foreignBuyRows = Build-FlowRows $foreignBuyTop "F1" "F2" "F3" $true
$foreignSellRows = Build-FlowRows $foreignSellTop "F1" "F2" "F3" $false
$trustBuyRows = Build-FlowRows $trustBuyTop "T1" "T2" "T3" $true
$trustSellRows = Build-FlowRows $trustSellTop "T1" "T2" "T3" $false

# ---------- Institutional NT$ totals (BFI82U) ----------
function BfiVal($name) {
    $row = $bfi.data | Where-Object { $_[0] -eq $name }
    return [double](($row[3]) -replace ',','')
}
$foreignNt = BfiVal "外資及陸資(不含外資自營商)"
$foreignDealerNt = BfiVal "外資自營商"
$trustNt = BfiVal "投信"
$dealerSelfNt = BfiVal "自營商(自行買賣)"
$dealerHedgeNt = BfiVal "自營商(避險)"
$dealerNt = $dealerSelfNt + $dealerHedgeNt
$instiTotalNt = ($foreignNt + $foreignDealerNt) + $trustNt + $dealerNt

function NtLabel($v) {
    $yi = $v / 100000000
    $s = "{0:N1}" -f [math]::Abs($yi)
    if ($v -lt 0) { return "－$s`億" } else { return "＋$s`億" }
}
$instiTotal = NtLabel $instiTotalNt
$instiTotalDirClass = if ($instiTotalNt -lt 0) { "down" } else { "up" }
$instiBreakdown = "外資$(NtLabel ($foreignNt+$foreignDealerNt))・投信$(NtLabel $trustNt)・自營$(NtLabel $dealerNt)"
$instiTotalLabel = if ($instiTotalNt -lt 0) { "淨賣超$('{0:N1}' -f ([math]::Abs($instiTotalNt)/100000000))億元" } else { "淨買超$('{0:N1}' -f ($instiTotalNt/100000000))億元" }
$instiTrendNote = if ($foreignNt -gt 0 -and $trustNt -gt 0) { "外資、投信同步買超" }
                  elseif ($foreignNt -lt 0 -and $trustNt -lt 0) { "外資、投信同步賣超" }
                  else { "外資與投信方向分歧" }

# ---------- Gainers/losers callout ----------
$gainersLosersCallout = "今日共 <b>$limitUpCount 檔</b>個股觸及或貼近漲停（漲幅≥9.5%），<b>$limitDownCount 檔</b>觸及或貼近跌停（跌幅≥9.5%）。以下榜單依實際漲跌幅排序，若某一方家數不足10檔，第 3～10 名可能非真正漲跌停，僅為當日最大漲跌幅個股。"

# ---------- Fear & Greed composite ----------
$advDecTotal = $up + $down
$c1 = if ($advDecTotal -gt 0) { [math]::Round($up / $advDecTotal * 100, 1) } else { 50 }
$c2 = [math]::Round((50 + ($taiexPctVal/3)*50), 1)
if ($c2 -lt 0) { $c2 = 0 }; if ($c2 -gt 100) { $c2 = 100 }
$limitTotal = $limitUpCount + $limitDownCount
$c3 = if ($limitTotal -gt 0) { [math]::Round($limitUpCount / $limitTotal * 100, 1) } else { 50 }
$cap = 50000000000  # 500億 cap for full-swing normalization
$c4raw = 50 + ($instiTotalNt / $cap) * 50
$c4 = [math]::Round([math]::Min(100,[math]::Max(0,$c4raw)), 1)
$fgScore = [math]::Round(($c1+$c2+$c3+$c4)/4, 0)
$fgBand = if ($fgScore -ge 75) { "極度貪婪 Extreme Greed" }
          elseif ($fgScore -ge 55) { "貪婪 Greed" }
          elseif ($fgScore -ge 45) { "中性 Neutral" }
          elseif ($fgScore -ge 25) { "恐懼 Fear" }
          else { "極度恐懼 Extreme Fear" }
$fgColor = if ($fgScore -ge 55) { "var(--up)" } elseif ($fgScore -le 45) { "var(--down)" } else { "var(--gold)" }

$taiexPctAbsLabel = if ($taiexPctVal -lt 0) { "跌幅$('{0:N2}' -f [math]::Abs($taiexPctVal))%" } else { "漲幅$('{0:N2}' -f $taiexPctVal)%" }

# ---------- Assemble template ----------
$tmpl = Get-Content "$TemplateDir\tmpl_part3.html" -Raw

$replacements = @{
    "{{DATA_DATE_LABEL}}" = $dataDateLabel
    "{{CLOSED_PILL}}" = $closedPill
    "{{HOLIDAY_NOTE}}" = $holidayNote
    "{{RANGE_LABEL}}" = $rangeLabel
    "{{RANGE_LABEL_SHORT}}" = $rangeLabelShort
    "{{TAIEX_CLOSE}}" = "{0:N2}" -f $taiexClose
    "{{TAIEX_DIR_CLASS}}" = $taiexDirClass
    "{{TAIEX_ARROW}}" = $taiexArrow
    "{{TAIEX_CHANGE_ABS}}" = "{0:N2}" -f [math]::Abs($taiexChangePts)
    "{{TAIEX_PCT}}" = Pct $taiexPctVal
    "{{TX_NEAR_SETTLE}}" = "{0:N0}" -f $txNearSettle
    "{{TX_NEAR_LABEL}}" = "$txNearMonth 月合約・貼水$(Signed $txNearBasis)點"
    "{{TX_NEXT_SETTLE}}" = "{0:N0}" -f $txNextSettle
    "{{TX_NEXT_DIR_CLASS}}" = $txNextDirClass
    "{{TX_NEXT_LABEL}}" = "$txNextMonth 月合約・較現貨$(Signed $txNextBasis)點"
    "{{INSTI_TOTAL}}" = $instiTotal
    "{{INSTI_TOTAL_DIR_CLASS}}" = $instiTotalDirClass
    "{{INSTI_BREAKDOWN}}" = $instiBreakdown
    "{{INSTI_TOTAL_LABEL}}" = $instiTotalLabel
    "{{INSTI_TREND_NOTE}}" = $instiTrendNote
    "{{FG_SCORE}}" = "$fgScore"
    "{{FG_BAND}}" = $fgBand
    "{{FG_COLOR}}" = $fgColor
    "{{FG_C1}}" = "$c1"; "{{FG_C2}}" = "$c2"; "{{FG_C3}}" = "$c3"; "{{FG_C4}}" = "$c4"
    "{{ADV_COUNT}}" = "$up"; "{{DEC_COUNT}}" = "$down"; "{{FLAT_COUNT}}" = "$flat"
    "{{LIMIT_UP_COUNT}}" = "$limitUpCount"; "{{LIMIT_DOWN_COUNT}}" = "$limitDownCount"
    "{{LIMIT_NOTE}}" = $limitNote
    "{{LIMITUP_STREAK_COUNT}}" = "$limitUpStreakCount"; "{{LIMITDOWN_STREAK_COUNT}}" = "$limitDownStreakCount"
    "{{LIMITUP_STREAK_ROWS}}" = $limitUpStreakRows
    "{{LIMITDOWN_STREAK_ROWS}}" = $limitDownStreakRows
    "{{GAINERS_LOSERS_CALLOUT}}" = $gainersLosersCallout
    "{{GAINERS_ROWS}}" = $gainersRows
    "{{LOSERS_ROWS}}" = $losersRows
    "{{FOREIGN_BUY_COUNT}}" = "$foreignBuyCount"; "{{FOREIGN_SELL_COUNT}}" = "$foreignSellCount"
    "{{TRUST_BUY_COUNT}}" = "$trustBuyCount"; "{{TRUST_SELL_COUNT}}" = "$trustSellCount"
    "{{FOREIGN_BUY_ROWS}}" = $foreignBuyRows
    "{{FOREIGN_SELL_ROWS}}" = $foreignSellRows
    "{{TRUST_BUY_ROWS}}" = $trustBuyRows
    "{{TRUST_SELL_ROWS}}" = $trustSellRows
    "{{TAIEX_PCT_ABS_LABEL}}" = $taiexPctAbsLabel
}
foreach ($k in $replacements.Keys) { $tmpl = $tmpl.Replace($k, $replacements[$k]) }

$part1 = (Get-Content "$TemplateDir\tmpl_part1.html" -Raw).Replace("{{TITLE_DATE}}", $titleDate)
$part2 = Get-Content "$TemplateDir\tmpl_part2.html" -Raw
$consolaB64 = (Get-Content "$TemplateDir\consola.b64" -Raw).Trim()
$consolabB64 = (Get-Content "$TemplateDir\consolab.b64" -Raw).Trim()

$final = $part1 + $consolaB64 + $part2 + $consolabB64 + $tmpl
[System.IO.File]::WriteAllText($OutFile, $final, (New-Object System.Text.UTF8Encoding($false)))

Write-Host "Built dashboard: $OutFile"
Write-Host "TAIEX: $taiexClose ($(Pct $taiexPctVal)) | FG Score: $fgScore ($fgBand)"
Write-Host "Gainers/Losers rows: $($gainers.Count)/$($losers.Count) | Foreign buy/sell candidates: $foreignBuyCount/$foreignSellCount | Trust buy/sell candidates: $trustBuyCount/$trustSellCount"
Write-Host "Limit-up/down 3-day streaks: $limitUpStreakCount/$limitDownStreakCount"
