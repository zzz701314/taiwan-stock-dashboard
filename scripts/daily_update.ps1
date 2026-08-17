# Daily update orchestrator, meant to be run by Windows Task Scheduler.
# Fetches fresh TWSE/TAIFEX data, rebuilds index.html, and pushes it to GitHub
# so GitHub Pages serves the updated dashboard automatically.
#
# Runs from two triggers: the daily 21:00 weekday time trigger, and an
# at-logon trigger that catches up if the PC was off/asleep at 21:00.
# The guards below make repeated invocations on the same day a cheap no-op.
#
# Logs each run to D:\台股分析 claude\logs\update_YYYY-MM-DD_HHmmss.log

$ErrorActionPreference = "Stop"
$root = "D:\台股分析 claude"
$logDir = "$root\logs"

if ($(Get-Date).DayOfWeek -in @('Saturday', 'Sunday')) {
    Write-Host "Weekend, no trading day to update. Skipping."
    exit 0
}

if (Test-Path $logDir) {
    $todaysLogs = Get-ChildItem -Path $logDir -Filter "update_$(Get-Date -Format 'yyyy-MM-dd')_*.log" -ErrorAction SilentlyContinue
    $completedToday = $todaysLogs | Where-Object {
        $tail = Get-Content $_.FullName -Tail 3 -ErrorAction SilentlyContinue
        $tail -match 'Daily update finished OK|Daily update FAILED'
    }
    if ($completedToday) {
        Write-Host "Already completed today ($($completedToday.Count) finished log(s) found), skipping duplicate run."
        exit 0
    }
}

if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$logFile = "$logDir\update_$(Get-Date -Format 'yyyy-MM-dd_HHmmss').log"

Start-Transcript -Path $logFile -Append | Out-Null
try {
    Write-Host "=== Daily update started: $(Get-Date) ==="

    & "$root\scripts\fetch_data.ps1"
    & "$root\scripts\build_html.ps1"

    Set-Location $root
    git add index.html
    $status = git status --porcelain index.html
    if ($status) {
        git commit -m "Daily update $(Get-Date -Format 'yyyy-MM-dd')"
        git push origin master
        Write-Host "Pushed updated index.html to GitHub."
    } else {
        Write-Host "No changes to index.html (already up to date), skipping commit."
    }

    Write-Host "=== Daily update finished OK: $(Get-Date) ==="
}
catch {
    Write-Host "=== Daily update FAILED: $($_.Exception.Message) ==="
    throw
}
finally {
    Stop-Transcript | Out-Null
}
