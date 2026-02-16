# iOS Transcription Diagnostic - ROOT CAUSE FOUND

## Problem Summary
iOS transcription consistently returns HTTP 500 error with empty body.

## Root Cause
**Azure Function dependencies (node_modules) not installed on Azure.**

The transcribe function requires:
- `form-data` npm package
- `node-fetch` npm package

When these aren't installed, the function crashes immediately when trying to import them, resulting in HTTP 500 with no error message.

## Why Dependencies Keep Getting Lost

### The Problem
You have conflicting folder structures:
- ✓ **Correct**: Individual function folders (`transcribe/`, `negotiate/`, `query/`, `voiceQuery/`)
- ✗ **Wrong**: Empty `functions/` folder (leftover from old structure)
- ✗ **Broken**: `deploy-code.ps1` script copies from empty `functions/` folder → **wipes all functions**

### What Happened Today
1. Used `deploy-code.ps1` which deployed empty functions → broke everything
2. Fixed by deploying correct folders
3. **BUT** npm dependencies didn't install because Azure's auto-install failed

## The Fix

### Immediate Fix (Manual)
1. SSH into Azure Function Kudu console: https://func-bcvoice-prod.scm.azurewebsites.net/DebugConsole
2. Navigate to `site/wwwroot`
3. Run: `npm install`
4. Test transcribe endpoint

### Permanent Fix (Done)
1. ✓ Deleted empty `functions/` folder
2. ✓ Created `deploy-safe.ps1` - ALWAYS use this script
3. ✓ Updated .deployment config

### Going Forward
**ONLY use this command to deploy:**
```powershell
cd azure-relay
.\deploy-safe.ps1
```

**NEVER use:**
- `deploy-code.ps1` (broken - copies from wrong folder)
- Manual zip deployments without checking folders

## Current Status
- Function code: ✓ Deployed correctly
- Dependencies: ✗ Not installed (causing 500 errors)
- Next step: Manual npm install via Kudu console

## Test Results
- Audio size: 81KB ✓
- MIME type: audio/m4a ✓
- URL: https://func-bcvoice-prod.azurewebsites.net/api/transcribe ✓
- HTTP request: Reaches Azure ✓
- Function execution: ✗ Crashes on missing dependencies

---

# Original Diagnostic Guide

## Issue: "Transcription failed" on iOS BC App

### Quick Checks:

1. **Check Setup in BC:**
   - Open "NXR Voice Assistant Setup" page
   - Check "Transcription Proxy URL" field
   - Should be: `https://[your-function-app].azurewebsites.net/api/transcribe`
   - Check that it's not empty

2. **Check Azure Function App Status:**
   - Go to Azure Portal
   - Navigate to your Function App
   - Check if it's running (not stopped)
   - Check if the `transcribe` function exists

3. **Check Azure Function Logs:**
   - In Azure Portal, go to Function App → Functions → transcribe
   - Click "Monitor" or "Logs"
   - Try voice input on iOS
   - Look for error messages in real-time logs

4. **Check Environment Variables:**
   - In Azure Portal, Function App → Configuration
   - Verify these are set:
     - `AZURE_OPENAI_ENDPOINT` (e.g., https://YOUR-RESOURCE.openai.azure.com/)
     - `AZURE_OPENAI_KEY` (your API key)
     - `AZURE_OPENAI_WHISPER_DEPLOYMENT` (your Whisper deployment name)

5. **Test Transcription Directly:**
   - Use Postman or similar to test the Azure Function directly
   - POST to: `https://[your-function-app].azurewebsites.net/api/transcribe`
   - Body:
     ```json
     {
       "audioData": "base64-encoded-audio-here",
       "mimeType": "audio/m4a"
     }
     ```
   - Should return: `{"text": "transcribed text", "success": true}`

### Common Issues:

**A. "Transcription Proxy URL" is empty:**
- Set it to your Azure Function URL
- Save the setup

**B. Azure Function is stopped:**
- Start it in Azure Portal

**C. Missing API credentials:**
- Add AZURE_OPENAI_* environment variables
- Restart Function App

**D. Wrong Whisper deployment name:**
- Check Azure OpenAI Studio for correct deployment name
- Update `AZURE_OPENAI_WHISPER_DEPLOYMENT` variable

**E. Audio too large:**
- iOS might be sending very large audio files
- Check Azure Function logs for "Audio size" message
- Whisper has a 25MB limit

### Debug Mode:

The AL code has DEBUG messages enabled (line 84 in Cod50612):
```al
Message('DEBUG Response: [%1]', ResponseText);
```

When you try voice input, you should see a message popup with the Azure Function response. 

**What to look for:**
- If you see no message: BC isn't calling the transcription service
- If message shows `{"error": "..."}`: Azure Function problem
- If message shows `{"text": "...", "success": true}`: Transcription working!

### Next Steps:

1. Check "Transcription Proxy URL" in BC setup - what is it set to?
2. Try voice input and note any DEBUG messages that appear
3. Check Azure Function logs at the same time
4. Share what you see and I can pinpoint the exact issue
