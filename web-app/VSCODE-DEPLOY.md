# VS Code Extension Deployment Guide

The Azure Static Web Apps extension is now installed!

## Deploy using VS Code (2 minutes):

### Option 1: Right-click Deploy (Easiest)
1. In VS Code Explorer, right-click the `web-app` folder
2. Select: **"Deploy to Static Web App..."**
3. Select: **"Use existing Static Web App"**
4. Choose subscription: Your Azure subscription
5. Choose: **bcvoice-web-app** (West Europe)
6. Confirm deployment
7. Wait 1-2 minutes
8. Done!

### Option 2: Command Palette
1. Press: `Ctrl+Shift+P` (or F1)
2. Type: **"Static Web Apps: Deploy"**
3. Select the command
4. Choose: **bcvoice-web-app**
5. Wait for deployment
6. Done!

### Option 3: Azure View
1. Click the Azure icon in VS Code left sidebar (should be open now)
2. Expand: **Static Web Apps**
3. Right-click: **bcvoice-web-app**
4. Select: **"Deploy to Static Web App"**
5. Select folder: **web-app**
6. Confirm
7. Wait for deployment

---

## After Deployment

VS Code will show deployment progress in the output panel.

Once complete, open: https://salmon-smoke-02a9c2c03.2.azurestaticapps.net

You should see the BC Voice Assistant interface!

---

## Why This is Better

✅ No GitHub Actions configuration needed  
✅ No workflow files  
✅ Direct deployment from VS Code  
✅ One-click updates  
✅ Shows deployment progress  
✅ Automatic error handling  

**This is what we should have done from the start!** 😅
