# Azure Function Deployment Guide

## Project Structure

**IMPORTANT**: This project uses the following structure:

```
azure-relay/
├── host.json              # Azure Functions configuration
├── package.json           # npm dependencies (main: "functions/*.js")
├── functions/             # ⚠️ ACTUAL DEPLOYMENT SOURCE
│   ├── negotiate/
│   ├── query/
│   ├── transcribe/       # Updated transcription with Azure OpenAI Whisper
│   └── voiceQuery/
└── src/
    └── functions/        # Legacy/backup - DO NOT USE FOR DEPLOYMENT
```

### Why Two Directories?

- **`functions/`**: The CORRECT directory for Azure Functions v4. Deploy this one.
- **`src/functions/`**: Legacy structure that should not be used.

## Deployment Process

### Quick Deploy (Recommended)

Use the automated deployment script that handles everything:

```powershell
cd azure-relay
.\deploy-with-build.ps1
```

This script will:
1. Create deployment ZIP from `functions/` directory
2. Deploy to Azure Function App
3. Automatically run `npm install` via Kudu API
4. Restart the Function App
5. Verify functions are discovered

### Manual Deploy (If Script Fails)

If the automated script fails, follow these steps:

#### 1. Update Local Structure (if needed)

If you've made changes to `src/functions/`, sync them:

```powershell
cd azure-relay
Copy-Item -Path "src/functions/*" -Destination "functions/" -Recurse -Force
```

#### 2. Create Deployment Package

```powershell
cd azure-relay
$zipPath = "$env:TEMP\bcvoice-deploy.zip"
Compress-Archive -Path "host.json","package.json","functions" -DestinationPath $zipPath -Force
```

#### 3. Deploy to Azure

```powershell
az webapp deployment source config-zip `
  --resource-group rg-bcvoice-prod `
  --name func-bcvoice-prod `
  --src $zipPath `
  --timeout 600
```

#### 4. Install npm Dependencies

Azure doesn't always run `npm install` automatically on Windows Consumption plans.

**Option A: Via Kudu Console** (Requires browser)
1. Go to Azure Portal → func-bcvoice-prod → Advanced Tools → Go
2. Open PowerShell console
3. Run:
```powershell
cd C:\home\site\wwwroot
npm install --production
```

**Option B: Via Kudu API** (Automated)
```powershell
$creds = az webapp deployment list-publishing-credentials --name func-bcvoice-prod --resource-group rg-bcvoice-prod | ConvertFrom-Json
$user = $creds.publishingUserName
$pass = $creds.publishingPassword
$base64Auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${user}:${pass}"))
$headers = @{ Authorization = "Basic $base64Auth"; "Content-Type" = "application/json" }
$body = @{ command = "cd site\wwwroot && npm install --production"; dir = "site\wwwroot" } | ConvertTo-Json
Invoke-RestMethod -Uri "https://func-bcvoice-prod.scm.azurewebsites.net/api/command" -Method Post -Headers $headers -Body $body -TimeoutSec 180
```

#### 5. Restart Function App

```powershell
az functionapp restart --name func-bcvoice-prod --resource-group rg-bcvoice-prod
```

#### 6. Verify Deployment

Check Azure Portal → func-bcvoice-prod → Functions. You should see:
- negotiate
- query
- transcribe
- voiceQuery

If functions don't appear after 2 minutes, check:
1. Kudu console: `ls C:\home\site\wwwroot` - should show function folders at root
2. Kudu console: `ls C:\home\site\wwwroot\node_modules` - should exist with packages
3. Log Stream for any errors

## Common Issues

### Functions Not Appearing

**Cause**: Functions in wrong directory or dependencies not installed.

**Solution**:
1. In Kudu console: `cd C:\home\site\wwwroot; ls`
2. Verify folders `negotiate`, `query`, `transcribe`, `voiceQuery` exist at root
3. If missing, run: `Copy-Item -Path "src/functions/*" -Destination "." -Recurse`
4. Check `node_modules` exists: `ls node_modules`
5. If missing, run: `npm install --production`
6. Restart Function App

### npm install Not Running Automatically

**Cause**: `SCM_DO_BUILD_DURING_DEPLOYMENT=true` doesn't always work on Windows Consumption plans.

**Solution**: Always run npm install manually after deployment (see step 4 above).

### Wrong Directory Structure Deployed

**Cause**: Deployed `src/` instead of `functions/`.

**Solution**: 
1. Update deployment script to use `functions/` directory
2. Redeploy with correct structure

## Dependencies

Required npm packages (defined in package.json):
- `@azure/functions` (^4.0.0)
- `node-fetch` (^2.6.7)
- `form-data` (^4.0.0)

These are needed for the transcription endpoint to work with Azure OpenAI Whisper API.

## Environment Variables

Required app settings:
```
AZURE_OPENAI_ENDPOINT=https://openai-bcvoice-prod-6lwg2qhbnsydo.openai.azure.com/
AZURE_OPENAI_KEY=<your-key>
AZURE_OPENAI_WHISPER_DEPLOYMENT=whisper
AZURE_OPENAI_DEPLOYMENT=gpt-4o-mini
AZURE_OPENAI_API_VERSION=2024-10-21
```

## Testing

Test transcription endpoint:
```powershell
$body = @{
    audioData = "<base64-audio>"
    mimeType = "audio/webm"
} | ConvertTo-Json

Invoke-RestMethod -Uri "https://func-bcvoice-prod.azurewebsites.net/api/transcribe" -Method Post -Body $body -ContentType "application/json"
```

## Best Practices

1. ✅ Always deploy from `functions/` directory
2. ✅ Always run npm install after deployment
3. ✅ Verify functions appear in Portal before testing
4. ✅ Use `deploy-with-build.ps1` for automated deployments
5. ❌ Never deploy from `src/` directory
6. ❌ Don't assume npm install runs automatically
