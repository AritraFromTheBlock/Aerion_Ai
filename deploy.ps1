# deploy.ps1 — Arion AI One-Click Deployment Script
# Usage: .\deploy.ps1 [backend|flutter|all]
param([string]$Target = "all")

$PROJECT   = "aegis-crisis-response-493911"
$REGION    = "asia-south1"
$SERVICE   = "arion-ai-backend"
$BACKEND   = "arion-ai-backend"
$API_URL   = "https://arion-ai-backend-239614749485.asia-south1.run.app"

Write-Host ""
Write-Host "╔══════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   🤖  ARION AI — DEPLOYMENT SCRIPT       ║" -ForegroundColor Cyan
Write-Host "║   Google Cloud Run + Firebase            ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# ── FUNCTION: Deploy Backend ────────────────────────────────
function Deploy-Backend {
    Write-Host "🚀 [Backend] Starting Cloud Run deployment..." -ForegroundColor Yellow

    Push-Location $BACKEND

    # Type-check before deploying
    Write-Host "   Checking TypeScript..." -ForegroundColor Gray
    npx tsc --noEmit
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ TypeScript errors found. Fix before deploying." -ForegroundColor Red
        Pop-Location
        return
    }

    # Deploy via Cloud Build (builds Docker image → Artifact Registry → Cloud Run)
    Write-Host "   Submitting to Cloud Build..." -ForegroundColor Gray
    $TAG = "deploy-$(Get-Date -Format 'yyyyMMdd-HHmm')"
    gcloud builds submit . `
        --config=cloudbuild.yaml `
        --project=$PROJECT `
        --region=$REGION `
        --substitutions="_TAG=$TAG" `
        2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ [Backend] Deployed successfully!" -ForegroundColor Green
        Write-Host "   URL: $API_URL" -ForegroundColor Cyan
    } else {
        Write-Host "❌ [Backend] Deployment failed. Check Cloud Build logs." -ForegroundColor Red
    }

    Pop-Location
}

# ── FUNCTION: Build Flutter APK ─────────────────────────────
function Build-FlutterApk {
    Write-Host "📱 [Flutter] Building release APK..." -ForegroundColor Yellow

    # Try to find Flutter
    $FLUTTER = $null
    $candidates = @(
        "flutter",
        "$env:USERPROFILE\flutter\bin\flutter.bat",
        "$env:LOCALAPPDATA\flutter\bin\flutter.bat",
        "C:\flutter\bin\flutter.bat",
        "C:\src\flutter\bin\flutter.bat",
        "C:\tools\flutter\bin\flutter.bat"
    )
    foreach ($c in $candidates) {
        if (Get-Command $c -ErrorAction SilentlyContinue) { $FLUTTER = $c; break }
    }

    if (-not $FLUTTER) {
        Write-Host "❌ Flutter not found in PATH. To build the APK:" -ForegroundColor Red
        Write-Host "   1. Install Flutter: https://docs.flutter.dev/get-started/install/windows" -ForegroundColor Yellow
        Write-Host "   2. Add Flutter to PATH and re-run: .\deploy.ps1 flutter" -ForegroundColor Yellow
        Write-Host "   OR: gcloud builds submit . --config=cloudbuild-flutter.yaml (builds in cloud)" -ForegroundColor Yellow
        return
    }

    Write-Host "   Found Flutter: $FLUTTER" -ForegroundColor Gray
    & $FLUTTER pub get
    & $FLUTTER build apk --release --split-per-abi

    if ($LASTEXITCODE -eq 0) {
        $APK = "build\app\outputs\flutter-apk\app-arm64-v8a-release.apk"
        $SIZE = [math]::Round((Get-Item $APK).Length / 1MB, 1)
        Write-Host "✅ [Flutter] APK built: $APK ($SIZE MB)" -ForegroundColor Green

        # Upload to Cloud Storage
        Write-Host "   Uploading to Cloud Storage..." -ForegroundColor Gray
        $TAG = "build-$(Get-Date -Format 'yyyyMMdd-HHmm')"
        gsutil cp $APK "gs://$($PROJECT)-apk-builds/$TAG/arion-ai-$TAG.apk" 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "   APK archived: gs://$($PROJECT)-apk-builds/$TAG/" -ForegroundColor Cyan
        }
    } else {
        Write-Host "❌ [Flutter] Build failed." -ForegroundColor Red
    }
}

# ── FUNCTION: Verify Deployment ─────────────────────────────
function Verify-Deployment {
    Write-Host ""
    Write-Host "🔍 [Verify] Testing live endpoints..." -ForegroundColor Yellow
    $H = @{"Content-Type"="application/json";"X-Api-Key"="arion-flutter-dev-key-change-in-production"}

    # Health check
    try {
        $r = Invoke-WebRequest -Uri "$API_URL/" -UseBasicParsing -TimeoutSec 10
        $json = $r.Content | ConvertFrom-Json
        Write-Host "   ✅ Health: $($json.status)" -ForegroundColor Green
    } catch { Write-Host "   ❌ Health check failed" -ForegroundColor Red }

    # SOS quick
    try {
        $body = '{"lat":12.9716,"lng":77.5946,"message":"Deploy verify SOS","deviceId":"deploy-verify"}'
        $r = Invoke-WebRequest -Method POST -Uri "$API_URL/sos/quick" -Headers $H -Body $body -UseBasicParsing -TimeoutSec 15
        $json = $r.Content | ConvertFrom-Json
        Write-Host "   ✅ SOS: $($json.message) (id: $($json.sosAlert.id.Substring(0,8))...)" -ForegroundColor Green
    } catch { Write-Host "   ❌ SOS endpoint failed: $_" -ForegroundColor Red }

    # Nearby incidents
    try {
        $r = Invoke-WebRequest -Uri "$API_URL/incidents/nearby?lat=12.9716&lng=77.5946&radius=20" -UseBasicParsing -TimeoutSec 15
        $json = $r.Content | ConvertFrom-Json
        Write-Host "   ✅ Incidents: $($json.incidents.Count) nearby" -ForegroundColor Green
    } catch { Write-Host "   ❌ Incidents endpoint failed" -ForegroundColor Red }

    Write-Host ""
    Write-Host "📋 Backend URL: $API_URL" -ForegroundColor Cyan
    Write-Host "📊 Cloud Run:   https://console.cloud.google.com/run/detail/$REGION/$SERVICE/metrics?project=$PROJECT" -ForegroundColor Cyan
    Write-Host "🔧 Cloud Build: https://console.cloud.google.com/cloud-build/builds?project=$PROJECT" -ForegroundColor Cyan
    Write-Host ""
}

# ── MAIN ────────────────────────────────────────────────────
switch ($Target.ToLower()) {
    "backend" { Deploy-Backend; Verify-Deployment }
    "flutter" { Build-FlutterApk }
    "verify"  { Verify-Deployment }
    "all"     { Deploy-Backend; Build-FlutterApk; Verify-Deployment }
    default   {
        Write-Host "Usage: .\deploy.ps1 [backend|flutter|verify|all]" -ForegroundColor Yellow
        Write-Host "  backend — Deploy Cloud Run backend via Cloud Build"
        Write-Host "  flutter — Build Flutter release APK and upload to GCS"
        Write-Host "  verify  — Test all live endpoints"
        Write-Host "  all     — Do everything"
    }
}
