# Fix iOS Transcription Issue

## Problem
iOS app returns "transcription failed" with generic responses.

## Root Cause
The Azure Function App's transcribe function was using a custom no-dependency implementation that may have issues with multipart form data handling or API compatibility.

## Solution
Updated to use the reliable `form-data` and `node-fetch` packages which are battle-tested for handling multipart uploads to OpenAI/Azure OpenAI Whisper API.

## Deployment Steps

### Option 1: Quick Deploy (Recommended)
```powershell
cd azure-relay

# Install dependencies locally
npm install

# Deploy to Azure Function App
.\deploy-code.ps1
```

### Option 2: Manual Deployment via Azure Portal
1. Go to Azure Portal → Function App `func-bcvoice-8939`
2. Navigate to **Deployment Center** → **FTPS credentials**
3. Note your deployment credentials
4. Deploy files via FTP or use VS Code Azure Functions extension

### Option 3: Using Azure CLI
```powershell
cd azure-relay

# Ensure dependencies exist
npm install

# Create deployment package
$zipPath = "deploy.zip"
Compress-Archive -Path @("host.json", "package.json", "src") -DestinationPath $zipPath -Force

# Deploy to Function App
az functionapp deployment source config-zip `
  --resource-group rg-bcvoice-prod `
  --name func-bcvoice-8939 `
  --src $zipPath

# Clean up
Remove-Item $zipPath
```

## Verify Deployment

### Check Function App Logs
1. Go to Azure Portal → Function App → Log stream
2. From iOS app, try voice transcription
3. Look for logs:
   - ✅ "Transcription request received"
   - ✅ "Using Azure OpenAI Whisper" or "Using OpenAI Whisper"
   - ✅ "Transcription successful: [text]"
   - ❌ "Whisper API error" (if this appears, see troubleshooting below)

### Test via Postman/cURL
```bash
curl -X POST https://func-bcvoice-8939.azurewebsites.net/api/transcribe \
  -H "Content-Type: application/json" \
  -d '{
    "audioData": "BASE64_ENCODED_AUDIO_HERE",
    "mimeType": "audio/mp4"
  }'
```

## Troubleshooting

### If still getting "transcription failed":

#### 1. Check Environment Variables
Verify these are set in Function App → Configuration → Application settings:
- `AZURE_OPENAI_ENDPOINT` = `https://openai-bcvoice-2025.openai.azure.com/`
- `AZURE_OPENAI_KEY` = `[your key]`
- `AZURE_OPENAI_WHISPER_DEPLOYMENT` = `whisper`

Or if using OpenAI directly:
- `OPENAI_API_KEY` = `sk-...`

#### 2. Check Whisper Deployment Status
```powershell
az cognitiveservices account deployment show `
  --name openai-bcvoice-2025 `
  --resource-group rg-bcvoice-prod `
  --deployment-name whisper
```

Should show `provisioningState: "Succeeded"`

#### 3. Test Whisper API Directly
```bash
curl "https://openai-bcvoice-2025.openai.azure.com/openai/deployments/whisper/audio/transcriptions?api-version=2024-10-21" \
  -H "api-key: YOUR_KEY" \
  -H "Content-Type: multipart/form-data" \
  -F "file=@test-audio.m4a" \
  -F "model=whisper-1"
```

If this fails with 404 or 401:
- **404**: API version or deployment name incorrect
- **401**: API key invalid or expired
- **429**: Rate limit exceeded, wait 60 seconds

#### 4. Check Function App Dependencies
In Azure Portal → Function App → Console:
```bash
cd site/wwwroot
ls -la
cat package.json
ls -la node_modules/form-data
ls -la node_modules/node-fetch
```

If `node_modules` is empty or missing packages:
```bash
npm install
```

#### 5. Enable Detailed Logging
Add to Function App settings:
- `FUNCTIONS_WORKER_RUNTIME` = `node`
- `AzureWebJobsStorage` = `[your storage connection string]`
- `APPINSIGHTS_INSTRUMENTATIONKEY` = `[if you have Application Insights]`

## Changes Made

### Updated File
**`azure-relay/src/functions/transcribe/index.js`**

Key improvements:
1. ✅ Uses `form-data` package for reliable multipart uploads
2. ✅ Uses `node-fetch` for robust HTTP requests
3. ✅ Supports both Azure OpenAI and OpenAI Whisper
4. ✅ Better error messages with hints
5. ✅ Retry logic for rate limits (429) and network errors
6. ✅ Detailed logging for debugging
7. ✅ Stack traces on errors

### Dependencies Required
```json
{
  "form-data": "^4.0.0",
  "node-fetch": "^2.6.7"
}
```

Already listed in `package.json` ✅

## Testing Checklist

After deployment:
- [ ] iOS app can transcribe voice successfully
- [ ] Transcribed text appears in Business Central
- [ ] Error messages are clear if something fails
- [ ] Function logs show detailed activity
- [ ] No "transcription failed" generic errors

## Notes

- The function now works with **both** Azure OpenAI Whisper and OpenAI Whisper
- If Azure OpenAI is configured, it uses that first
- Falls back to OpenAI if `OPENAI_API_KEY` is set and Azure OpenAI is not configured
- Includes retry logic for transient failures
- Better error messages tell you exactly what's missing

## Next Steps

After confirming transcription works:
1. Test full voice query flow (transcription → query → response)
2. Verify follow-up suggestions generate correctly
3. Check UI updates from v2.2.0.19 are reflected
4. Consider adding Application Insights for long-term monitoring
