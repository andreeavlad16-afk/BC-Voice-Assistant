# BC Voice Assistant - Infrastructure Migration Guide

**Date:** January 16, 2026  
**Migration:** East US → UK South  
**Reason:** Whisper model availability

---

## Overview

This guide walks through migrating the BC Voice Assistant infrastructure from East US (where Whisper is not available) to UK South (where Whisper is supported).

**What's included:**
- ✅ Azure OpenAI with GPT-4o-mini + Whisper deployments
- ✅ Function App with auto-configured settings
- ✅ Storage Account
- ✅ SignalR Service
- ✅ Application Insights
- ✅ Infrastructure as Code (Bicep)
- ✅ Automated deployment scripts
- ✅ Configuration update scripts
- ✅ Cleanup scripts

---

## Prerequisites

1. **Azure CLI installed**
   ```powershell
   # Check if installed
   az version
   
   # Install if needed
   # Download from: https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-windows
   ```

2. **Azure subscription access**
   - Must have Contributor or Owner role
   - Subscription must have quota for Azure OpenAI

3. **Logged in to Azure**
   ```powershell
   az login
   ```

---

## Step 1: Deploy New Infrastructure (UK South)

Run the deployment script:

```powershell
cd c:\Users\44321157\OneDrive\VOICEACTIVATED-BC\infrastructure
.\deploy.ps1
```

**What it does:**
- Creates resource group `rg-bcvoice-prod` (UK South)
- Deploys all Azure resources using Bicep template
- Configures Function App with all required settings
- Deploys GPT-4o-mini model (capacity: 50)
- Deploys Whisper model (capacity: 1)
- Saves configuration to `deployment-config.json`

**Duration:** ~5-10 minutes

**Expected output:**
```
========================================
 Deployment Complete!
========================================

Configuration saved to: deployment-config.json

Next steps:
  1. Deploy Function App code: npm run deploy
  2. Update Business Central Setup with new values
  3. Run cleanup script to delete old resources
```

---

## Step 2: Deploy Function App Code

Navigate to the Azure relay folder and deploy:

```powershell
cd c:\Users\44321157\OneDrive\VOICEACTIVATED-BC\azure-relay

# Install dependencies (if not already done)
npm install

# Deploy to new Function App
func azure functionapp publish <function-app-name>
```

**Get Function App name from deployment-config.json:**
```powershell
$config = Get-Content ..\infrastructure\deployment-config.json | ConvertFrom-Json
Write-Host $config.FunctionApp.Name
```

**Alternative: Deploy via Azure Portal**
1. Go to Function App in Azure Portal
2. Deployment Center → Manual Deployment
3. Select Local Git or GitHub
4. Push code

---

## Step 3: Update Business Central Configuration

Run the configuration update script:

```powershell
cd c:\Users\44321157\OneDrive\VOICEACTIVATED-BC\infrastructure
.\update-bc-config.ps1
```

**What it does:**
- Reads `deployment-config.json`
- Displays all values to update in BC
- Creates `bc-setup-values.csv` for reference

**Manual steps in Business Central:**

1. Open Business Central
2. Search for "Voice Assistant Setup"
3. Update these fields:

| Field | New Value |
|-------|-----------|
| Azure OpenAI Endpoint | `https://openai-<uniqueid>.openai.azure.com/` |
| Azure OpenAI Deployment Name | `gpt-4o-mini` |
| Azure OpenAI API Version | `2024-08-06` |
| Transcription Proxy URL | `https://func-<uniqueid>.azurewebsites.net/api/transcribe` |

4. Click **"Set Azure OpenAI Key"** action
   - Paste the key from `deployment-config.json` → `OpenAI.Key`

5. Click **"Set SignalR Connection"** action (if applicable)
   - Paste connection string from `deployment-config.json` → `SignalR.ConnectionString`

6. Click **"Test Connection"**
   - Should return: ✅ **200 OK** (instead of 404)

---

## Step 4: Test Everything

### Test 1: Test Connection
- Business Central → Voice Assistant Setup → Test Connection
- **Expected:** 200 OK with model info

### Test 2: Voice Query
- Use the voice assistant UI or mobile app
- Record audio: "Show me all customers"
- **Expected:** Transcription works, query executes

### Test 3: Transcription Endpoint
```powershell
# Get transcribe URL
$config = Get-Content infrastructure\deployment-config.json | ConvertFrom-Json
$transcribeUrl = $config.FunctionApp.TranscribeURL

# Test with sample audio (requires base64 audio data)
Invoke-RestMethod -Uri $transcribeUrl -Method POST -ContentType "application/json" -Body @"
{
    "audioData": "base64-encoded-audio-here",
    "mimeType": "audio/webm"
}
"@
```

---

## Step 5: Cleanup Old Resources (Optional)

⚠️ **Only do this AFTER verifying everything works!**

```powershell
cd c:\Users\44321157\OneDrive\VOICEACTIVATED-BC\infrastructure

# Preview what will be deleted
.\cleanup-old-resources.ps1 -WhatIf

# Actually delete (requires typing "DELETE")
.\cleanup-old-resources.ps1
```

**What gets deleted:**
- Old Azure OpenAI resource (openai-bcvoice-2025 in East US)
- Old Function App (func-bcvoice-8939)
- Old Storage Account (stbcvoice9149)
- Old SignalR (signalr-bcvoice-1656)
- Entire resource group: `rg-bcvoice-prod` (East US)

**Duration:** ~5-10 minutes (async)

---

## Rollback Plan

If something goes wrong with the new deployment:

1. **Keep old resources running** - Don't run cleanup script
2. **Revert BC configuration** - Change back to old endpoints
3. **Old endpoints (backup):**
   - Azure OpenAI: `https://openai-bcvoice-2025.openai.azure.com/`
   - Function App: `https://func-bcvoice-8939.azurewebsites.net`
   - Transcribe: `https://func-bcvoice-8939.azurewebsites.net/api/transcribe`

---

## Troubleshooting

### Issue: "Azure CLI not found"
**Solution:** Install Azure CLI from https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-windows

### Issue: "Not logged in"
**Solution:** Run `az login` and authenticate

### Issue: "Deployment failed - quota exceeded"
**Solution:** Request quota increase in Azure Portal:
1. Go to Azure OpenAI resource
2. Quotas → Request increase
3. Wait for approval (usually 1-2 business days)

### Issue: "Test Connection still returns 404"
**Solution:**
1. Verify Azure OpenAI Endpoint is correct (no trailing slash)
2. Verify Deployment Name is exactly `gpt-4o-mini`
3. Verify API Version is `2024-08-06`
4. Re-enter API Key via "Set Azure OpenAI Key" action

### Issue: "Whisper transcription fails"
**Solution:**
1. Check Function App logs in Azure Portal
2. Verify `AZURE_OPENAI_WHISPER_DEPLOYMENT` is set to `whisper`
3. Verify Whisper model is deployed: Azure Portal → Azure OpenAI → Deployments

---

## Files Created

| File | Purpose |
|------|---------|
| `infrastructure/main.bicep` | Bicep template for all Azure resources |
| `infrastructure/deploy.ps1` | Deployment script |
| `infrastructure/cleanup-old-resources.ps1` | Cleanup script |
| `infrastructure/update-bc-config.ps1` | BC configuration helper |
| `deployment-config.json` | Deployment output (auto-generated) |
| `bc-setup-values.csv` | BC setup values (auto-generated) |

---

## Cost Estimate

**New infrastructure (UK South):**
- Azure OpenAI: ~$0.15 per 1K tokens (GPT-4o-mini), ~$0.006/minute (Whisper)
- Function App: Consumption plan (~free for low usage)
- Storage: ~$0.01/month
- SignalR: Free tier
- Application Insights: ~$2.30/GB ingested

**Total estimated cost:** ~$10-50/month depending on usage

---

## Next Steps After Migration

1. ✅ Monitor logs in Application Insights
2. ✅ Set up alerts for failures
3. ✅ Update documentation with new endpoints
4. ✅ Inform users of any downtime (if applicable)
5. ✅ Delete old resources after 30 days of stable operation

---

## Support

- Azure OpenAI: https://learn.microsoft.com/en-us/azure/ai-services/openai/
- Bicep: https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/
- Function Apps: https://learn.microsoft.com/en-us/azure/azure-functions/

