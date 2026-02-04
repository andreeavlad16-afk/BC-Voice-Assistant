# PWA Transcription 503 Error - Investigation & Fix Guide

## Error Description
**Error Message:** ❌ Failed to process voice query: Transcription failed: 503

## Root Cause Analysis

### What is a 503 Error?
HTTP 503 "Service Unavailable" indicates the server is temporarily unable to handle the request. In the context of Azure Functions, this typically means:

1. **Cold Start** - Function app is starting up after being idle
2. **No Deployment** - Function code hasn't been deployed yet
3. **Configuration Error** - Missing environment variables or settings
4. **Azure Service Issue** - Temporary Azure platform problem

### The Call Chain
```
PWA (Browser)
  ↓ User speaks
Web Speech API / Microphone
  ↓ Audio captured
Business Central (if configured)
  ↓ POST /api/transcribe
Azure Function App
  ↓ POST to Azure OpenAI
Azure OpenAI Whisper API
  ↓ Returns transcribed text
Response back to PWA
```

### Where the 503 Occurs
Based on the error message pattern "Transcription failed: 503", the error originates from:

**Location:** `src/codeunit/Cod50612.NXRVoiceSpeechTranscription.al` line 77
```al
if not Response.IsSuccessStatusCode() then begin
    Response.Content().ReadAs(ResponseText);
    exit('Transcription failed: ' + ResponseText);
end;
```

This means Business Central successfully called the Azure Function, but got a 503 response back.

## Common Causes & Solutions

### 1. Azure Function Not Deployed
**Symptom:** Every request returns 503  
**Cause:** Function app exists but no code has been deployed

**Solution:**
```bash
cd azure-relay
npm install
func azure functionapp publish <your-function-app-name>
```

**Verify:**
```bash
curl https://<your-function-app>.azurewebsites.net/api/transcribe
# Should return 400 (missing audio data) not 503
```

### 2. Cold Start (Most Common)
**Symptom:** First request fails with 503, subsequent requests work  
**Cause:** Function app on Consumption Plan takes 10-30 seconds to start

**Solution Options:**

**Option A: Wait and Retry (Simple)**
The Azure Function has been updated to provide a clear message:
```
"Service temporarily unavailable. This may be due to a cold start. Please try again in a moment."
```

Users should:
1. Wait 10-15 seconds
2. Try the voice command again
3. Should work on second attempt

**Option B: Keep Function Warm (Better)**
Create a timer-triggered function to ping the endpoint every 5 minutes:
```javascript
// Keep-alive function (add to azure-relay/functions/)
module.exports = async function (context, myTimer) {
    const fetch = require('node-fetch');
    const url = process.env.FUNCTION_APP_URL || 'https://your-function.azurewebsites.net';
    
    try {
        await fetch(`${url}/api/health`);
        context.log('Keep-alive ping successful');
    } catch (error) {
        context.log('Keep-alive ping failed:', error);
    }
};
```

**Option C: Upgrade to Premium Plan (Production)**
Premium plan provides:
- No cold starts
- Better performance
- VNET integration
- Cost: ~$150-300/month vs ~$10/month for Consumption

### 3. Missing Environment Variables
**Symptom:** 503 or 500 error consistently  
**Cause:** Azure Function can't find required configuration

**Required Settings:**
In Azure Portal → Function App → Configuration → Application settings:
- `AZURE_OPENAI_ENDPOINT` = `https://your-openai.openai.azure.com/`
- `AZURE_OPENAI_KEY` = Your API key
- `AZURE_OPENAI_WHISPER_DEPLOYMENT` = `whisper`
- `AzureWebJobsStorage` = Storage connection string

**Verify:**
1. Go to Azure Portal
2. Navigate to your Function App
3. Configuration → Application settings
4. Check all required variables are present

### 4. CORS Misconfiguration
**Symptom:** 503 from browser, works from cURL/Postman  
**Cause:** CORS blocking the request from PWA origin

**Solution:**
1. Azure Portal → Function App → CORS
2. Add allowed origins:
   - `https://businesscentral.dynamics.com`
   - Your PWA domain
   - `http://localhost:*` (for testing)

### 5. Azure OpenAI Endpoint Issue
**Symptom:** Function works but Whisper API returns 503  
**Cause:** Azure OpenAI service is having issues or not deployed

**Check:**
```bash
# Verify Whisper deployment exists
az cognitiveservices account deployment show \
  --name <your-openai-name> \
  --resource-group <your-rg> \
  --deployment-name whisper
```

**Should show:**
```json
{
  "properties": {
    "provisioningState": "Succeeded"
  }
}
```

If not found or failed, redeploy:
```bash
az cognitiveservices account deployment create \
  --name <your-openai-name> \
  --resource-group <your-rg> \
  --deployment-name whisper \
  --model-name whisper \
  --model-version "001" \
  --model-format OpenAI
```

## Diagnostic Steps

### Step 1: Check Function App Status
```bash
# Check if function app is running
az functionapp show \
  --name <function-app-name> \
  --resource-group <resource-group> \
  --query "state"

# Should return: "Running"
```

### Step 2: Test Function Directly
```bash
# Create test audio file (or use existing)
echo "UklGRiQAAABXQVZFZm10IBAAAAABAAEA..." | base64 -d > test.wav

# Test transcribe endpoint
curl -X POST https://<function-app>.azurewebsites.net/api/transcribe \
  -H "Content-Type: application/json" \
  -d '{
    "audioData": "UklGRiQAAABXQVZFZm10IBAAAAABAAEA...",
    "mimeType": "audio/wav"
  }'
```

**Expected responses:**
- 200: Success (with transcription)
- 400: Bad request (missing audio data)
- 401: Authentication failed
- 500: Internal error (check logs)
- 503: Service unavailable (cold start or not deployed)

### Step 3: Check Function Logs
Azure Portal → Function App → Log stream

Look for:
- ✅ "Transcription request received"
- ✅ "Using Azure OpenAI Whisper"
- ❌ "Whisper API error (503)"
- ❌ "AZURE_OPENAI_ENDPOINT not configured"

### Step 4: Test from PWA
1. Open PWA in browser
2. Open DevTools → Console
3. Try voice command
4. Look for error details in console

### Step 5: Check Business Central Setup
1. Search: "NXR Voice Assistant Setup"
2. Verify "Transcription Proxy URL" is set
3. Should be: `https://<function-app>.azurewebsites.net/api/transcribe`
4. Click "Test Connection"

## Quick Fix Checklist

If you're seeing 503 errors, work through this checklist:

- [ ] Azure Function App is deployed and running
- [ ] Function code has been published (`func azure functionapp publish`)
- [ ] All environment variables are configured
- [ ] Waited 30 seconds and tried again (cold start)
- [ ] CORS is configured to allow your PWA origin
- [ ] Azure OpenAI Whisper deployment exists and is "Succeeded"
- [ ] Transcription Proxy URL is configured in BC setup
- [ ] No Azure service outages (check Azure status page)

## Workarounds

### Temporary: Use Browser Speech Recognition
If Azure Functions transcription isn't working, the PWA can use browser's built-in Web Speech API:

1. PWA detects Speech Recognition support
2. Falls back to browser API automatically
3. No Azure Functions needed
4. Works on most modern browsers (Chrome, Edge, Safari)

**Limitation:** Only works when using PWA directly, not through BC Mobile App WebView

### Alternative: Direct Azure OpenAI Call
For testing, you can call Azure OpenAI directly:

```bash
curl "https://your-openai.openai.azure.com/openai/deployments/whisper/audio/transcriptions?api-version=2024-10-21" \
  -H "api-key: YOUR_KEY" \
  -H "Content-Type: multipart/form-data" \
  -F "file=@audio.m4a" \
  -F "model=whisper-1"
```

If this works but Function App doesn't, the issue is in the Function App, not Azure OpenAI.

## Permanent Fix

**For Production Use:**
1. Deploy Function App to Premium Plan (eliminates cold starts)
2. Enable Application Insights for monitoring
3. Set up health check endpoint
4. Configure alerts for 503 errors
5. Implement automatic retry logic in BC code

**Code Enhancement:**
Update Business Central codeunit to retry on 503:

```al
// Pseudo-code for retry logic
procedure TranscribeWithRetry(Base64Audio: Text; MimeType: Text): Text
var
    Attempt: Integer;
    MaxAttempts: Integer;
    Response: HttpResponseMessage;
begin
    MaxAttempts := 3;
    for Attempt := 1 to MaxAttempts do begin
        if Client.Post(TranscriptionProxyUrl, RequestContent, Response) then begin
            if Response.IsSuccessStatusCode() then
                exit(ParseSuccessResponse(Response));
            
            if Response.HttpStatusCode() = 503 then begin
                if Attempt < MaxAttempts then begin
                    Sleep(10000); // Wait 10 seconds
                    continue;
                end;
            end;
        end;
    end;
    exit('Transcription failed after ' + Format(MaxAttempts) + ' attempts');
end;
```

## Related Issues

See also:
- `DEPLOY-TRANSCRIPTION-FIX.md` - Detailed deployment instructions
- `SECURITY-FIXES.md` - Security improvements including better error handling
- Azure Functions documentation on cold starts

## Status & Next Steps

**Current State:**
- ✅ Better error messages added to help diagnose 503 errors
- ✅ CORS configuration improved
- ⚠️ Cold start issue remains (inherent to Consumption Plan)

**Recommended Actions:**
1. Deploy function code if not already done
2. Wait for cold start on first request
3. Consider Premium Plan for production
4. Add retry logic to BC codeunit

---
**Last Updated:** February 4, 2026  
**Related Error Codes:** 503, Service Unavailable  
**Keywords:** PWA, transcription, Azure Functions, cold start
