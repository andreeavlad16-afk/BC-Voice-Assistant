# Deploy Latest PWA to Azure Static Web Apps

## Quick Deploy via Azure Portal

1. **Go to Azure Portal**: https://portal.azure.com
2. **Navigate to**: Resource Groups → `rg-bcvoice-prod` → `bcvoice-pwa`
3. **Click**: "Manage deployment token" (copy it)
4. **Run this command**:

```powershell
cd c:\Users\44321157\OneDrive\VOICEACTIVATED-BC

# Install SWA CLI globally (one-time)
npm install -g @azure/static-web-apps-cli

# Deploy
swa deploy ./pwa --deployment-token "<YOUR_TOKEN>" --env production
```

## Alternative: GitHub Actions (Recommended)

The repository already has GitHub Actions configured. Simply:

```powershell
cd c:\Users\44321157\OneDrive\VOICEACTIVATED-BC
git add pwa/
git commit -m "Update PWA to latest version with auto-config"
git push
```

GitHub Actions will automatically deploy to Azure Static Web Apps.

## Manual Upload via Azure CLI

```powershell
cd c:\Users\44321157\OneDrive\VOICEACTIVATED-BC

# Zip the PWA files
Compress-Archive -Path "pwa\*" -DestinationPath "pwa-deploy.zip" -Force

# Upload via Azure Portal:
# 1. Go to Static Web App → "Manage deployments"
# 2. Upload pwa-deploy.zip
```

## Current Configuration

The PWA now includes `config.js` which auto-configures production settings:

- **Client ID**: 2dfcd259-35d2-43f4-ad0c-7e8863588472
- **Tenant ID**: 60d3cd31-aac9-4a19-90f7-4cff0310f993
- **BC Environment**: https://api.businesscentral.dynamics.com/v2.0/60d3cd31-aac9-4a19-90f7-4cff0310f993/GB-Demonstration
- **Relay URL**: https://func-bcvoice-v2.azurewebsites.net/api/relay

## Status

✅ **Localhost**: http://localhost:3000 (running now)
🌐 **Production**: https://gray-sand-017a93f03.1.azurestaticapps.net (needs update)

Once deployed, the production site will automatically configure itself with the correct BC environment settings.
