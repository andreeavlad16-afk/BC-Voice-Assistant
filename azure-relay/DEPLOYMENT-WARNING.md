# ⚠️ IMPORTANT: Azure Function Deployment

## ✅ CORRECT WAY TO DEPLOY

**ALWAYS use this script:**
```powershell
cd azure-relay
.\deploy-safe.ps1
```

This is the ONLY script that:
- ✓ Uses correct folder structure
- ✓ Includes all functions (transcribe, negotiate, query, voiceQuery)
- ✓ Tests deployment automatically
- ✓ Won't break your deployment

## ❌ DO NOT USE

These scripts have been fixed but are NOT recommended:
- `deploy-code.ps1` - Now fixed, but use deploy-safe.ps1 instead
- `deploy-transcribe-only.ps1` - Only deploys transcribe (breaks other functions)
- `deploy-with-build.ps1` - Now fixed, but use deploy-safe.ps1 instead
- `deploy-verify.ps1` - Now fixed, but use deploy-safe.ps1 instead

## 🗂️ Folder Structure

**CORRECT structure (current):**
```
azure-relay/
├── transcribe/          ← Real function code
│   ├── index.js
│   └── function.json
├── negotiate/           ← Real function code
├── query/               ← Real function code
├── voiceQuery/          ← Real function code
├── host.json
├── package.json
└── deploy-safe.ps1      ← USE THIS!
```

**DO NOT recreate:**
```
azure-relay/
├── functions/           ← Empty folder (DELETED - causes problems)
```

## 📋 Manual Deployment (If Needed)

If deploy-safe.ps1 fails, use manual method:
```powershell
cd azure-relay
Compress-Archive -Path transcribe,negotiate,query,voiceQuery,host.json,package.json -DestinationPath deploy.zip -Force
az functionapp deployment source config-zip --resource-group rg-bcvoice-prod --name func-bcvoice-prod --src deploy.zip
```

## 🔧 If Functions Return 500 Error

The npm dependencies might not be installed. Fix it:

1. Go to: https://func-bcvoice-prod.scm.azurewebsites.net/DebugConsole
2. Navigate to `site/wwwroot`
3. Run: `npm install`
4. Wait 1-2 minutes for installation
5. Test: https://func-bcvoice-prod.azurewebsites.net/api/transcribe

## 📝 What Went Wrong Before

- There was an empty `functions/` folder (leftover from old structure)
- Old deployment scripts copied from this empty folder
- This overwrote all real function code
- Result: All functions disappeared, returning 404
- **Solution: Deleted empty `functions/` folder, fixed all scripts**

## ✅ All Scripts Fixed

The following scripts have been updated to use the correct folder structure:
- ✓ deploy-safe.ps1 (RECOMMENDED)
- ✓ deploy-code.ps1
- ✓ deploy-transcribe-only.ps1
- ✓ deploy-with-build.ps1
- ✓ deploy-verify.ps1

**But still: USE deploy-safe.ps1 for all deployments!**
