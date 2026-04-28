$env:PATH += ";$env:LOCALAPPDATA\Google\Cloud SDK\google-cloud-sdk\bin"
$base = "https://arion-ai-backend-239614749485.asia-south1.run.app"

Write-Host ""
Write-Host "===== ARION AI - LIVE BACKEND MONITOR =====" -ForegroundColor Cyan
Write-Host ""

# Health check
Write-Host "Checking server health..." -ForegroundColor Yellow
try {
    $h = Invoke-RestMethod -Uri "$base/" -TimeoutSec 10
    Write-Host "OK  Server: $($h.status)  |  Version: $($h.version)" -ForegroundColor Green
} catch {
    Write-Host "FAIL  Server unreachable!" -ForegroundColor Red
    exit
}

# Incident count
Write-Host "Checking incident count..." -ForegroundColor Yellow
try {
    $url = "${base}/incidents/nearby?lat=12.9716&lng=77.5946&radius=5000"
    $n = Invoke-RestMethod -Uri $url
    Write-Host "OK  Incidents in DB: $($n.count)" -ForegroundColor Green
} catch {
    Write-Host "WARN  Could not fetch incidents" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Streaming live Cloud Run logs (Ctrl+C to stop)..." -ForegroundColor Cyan
Write-Host "----------------------------------------" -ForegroundColor DarkGray
Write-Host ""

# Stream logs
gcloud.cmd beta run services logs tail arion-ai-backend --region=asia-south1 --project=aegis-crisis-response-493911 2>&1
