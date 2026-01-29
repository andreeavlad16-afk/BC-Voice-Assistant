# BC Voice Assistant - Progressive Web App

A cross-platform Progressive Web App (PWA) for voice queries to Business Central.

## Features

✅ **Works on both iOS and Android**  
✅ **Voice recording** with microphone  
✅ **Text input** option  
✅ **Installable** - add to home screen  
✅ **Responsive** - works on any screen size  
✅ **No app store** required  

---

## Quick Start

### Option 1: Test Locally (Instant)

1. Open `index.html` in any modern browser
2. Grant microphone permission when prompted
3. Start using voice or text queries

**Note:** File URLs (`file://`) may have limited functionality. Use Option 2 or 3 for full features.

---

### Option 2: Host on Azure Static Web Apps (Recommended)

#### Deploy via Azure Portal

1. Go to Azure Portal → Create Resource → Static Web App
2. Fill in details:
   - Name: `bc-voice-assistant`
   - Region: West Europe
   - Source: Other
3. Click "Review + Create"
4. After deployment, go to the Static Web App resource
5. Click "Browse" to get your URL (e.g., `https://bc-voice-assistant.azurestaticapps.net`)
6. Go to "Configuration" → "Application settings"
7. Upload files:
   - `index.html`
   - `manifest.json`
   - `sw.js`

#### Deploy via Azure CLI

```bash
# Install Azure Static Web Apps CLI
npm install -g @azure/static-web-apps-cli

# Login to Azure
az login

# Deploy
cd web-app
swa deploy --app-name bc-voice-assistant \
  --resource-group rg-bcvoice-prod \
  --deployment-token YOUR_DEPLOYMENT_TOKEN
```

**Get deployment token:**
```bash
az staticwebapp secrets list \
  --name bc-voice-assistant \
  --resource-group rg-bcvoice-prod \
  --query "properties.apiKey" -o tsv
```

---

### Option 3: Host on GitHub Pages (Free)

1. Create a GitHub repository
2. Upload files to root or `/docs` folder:
   - `index.html`
   - `manifest.json`
   - `sw.js`
3. Go to Settings → Pages
4. Select source: main branch → `/docs` folder (or root)
5. Save - your site will be live at: `https://yourusername.github.io/repo-name/`

---

### Option 4: Host Anywhere Else

You can host these files on:
- **Netlify** (drag & drop)
- **Vercel** (drag & drop)
- **Azure Blob Storage** (static website hosting)
- **AWS S3** (static website hosting)
- Any web server (Apache, Nginx, IIS)

**Requirements:**
- HTTPS required for microphone access
- All 3 files must be in the same directory

---

## Configuration

### Update Function URL

⚠️ **IMPORTANT:** The default URL shown below is a placeholder/example from the original deployment. You must replace it with your own Azure Function URL after deployment.

By default, the app uses:
```
https://func-bcvoice-prod.azurewebsites.net  ⚠️ EXAMPLE ONLY
```

To change:
1. Open the app in browser
2. Click "⚙️ Settings" button at bottom
3. Update Function URL
4. Add Function Key (if required)
5. Click "💾 Save Settings"

Settings are saved in browser localStorage.

---

## Using the App

### Voice Query
1. Tap the 🎤 microphone button
2. Speak your question (e.g., "How many locations do we have?")
3. Tap again to stop ⏹️
4. Wait for response

### Text Query
1. Type your question in the text box
2. Or click a quick example chip
3. Click "Send Query" button
4. Wait for response

---

## Install as App

### On Android (Chrome)
1. Open the web app in Chrome
2. Tap the "Install App" banner (or)
3. Menu (⋮) → "Add to Home screen"
4. App appears on home screen
5. Opens in fullscreen mode

### On iOS (Safari)
1. Open the web app in Safari
2. Tap the Share button (📤)
3. Scroll and tap "Add to Home Screen"
4. Name it "BC Voice"
5. Tap "Add"
6. App appears on home screen

---

## Troubleshooting

### Microphone not working
- **Check permissions:** Browser settings → Site permissions → Microphone
- **HTTPS required:** Local `file://` URLs don't support microphone
- **Solution:** Host on HTTPS server or use localhost

### "Function key required" error
- Go to Settings (⚙️)
- Add your function key from Azure Portal
- Function App → App Keys → Copy default key
- Save settings

### "Network error"
- Check internet connection
- Verify Function URL in Settings (must be YOUR deployed function, not the example)
- Test Function directly: Replace `https://func-bcvoice-prod.azurewebsites.net/api/query` with your actual Function URL

### App not installing
- **iOS:** Only works in Safari, not Chrome
- **Android:** Works in Chrome, Edge, Samsung Internet
- Must be hosted on HTTPS (not file://)

---

## Icons (Optional)

To add custom app icons, create:
- `icon-192.png` (192x192 pixels)
- `icon-512.png` (512x512 pixels)

Place in same folder as `index.html`.

**Quick icon generator:** https://realfavicongenerator.net

---

## Security

### Function Key
- Stored in browser localStorage (not transmitted)
- Each user must configure their own
- Optional - remove if function is public

### HTTPS
- Required for microphone access
- All hosting options above provide HTTPS
- Azure Static Web Apps: Free SSL included

---

## Browser Support

| Browser | Voice | Text | Install |
|---------|-------|------|---------|
| Chrome (Android) | ✅ | ✅ | ✅ |
| Safari (iOS) | ✅ | ✅ | ✅ |
| Edge (Android) | ✅ | ✅ | ✅ |
| Firefox (Android) | ✅ | ✅ | ❌ |
| Chrome (Desktop) | ✅ | ✅ | ✅ |
| Safari (Desktop) | ✅ | ✅ | ❌ |

---

## Customization

### Change Colors
Edit `index.html` CSS variables:
```css
background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
/* Change to your brand colors */
```

### Change Title
```html
<h1>🎤 BC Voice Assistant</h1>
<!-- Change to your company name -->
```

### Add More Examples
```javascript
<button class="example-chip" onclick="setQuery('Your question')">Label</button>
```

---

## Cost

### Azure Static Web Apps
- **Free tier:** 100GB bandwidth/month, 2 custom domains
- **Standard:** $9/month for more bandwidth
- **Our usage:** FREE (well within free tier)

### GitHub Pages
- **Completely free** (100GB bandwidth/month)

---

## Next Steps

1. ✅ Test locally: Open `index.html` in browser
2. ⬜ Deploy to Azure Static Web Apps or GitHub Pages
3. ⬜ Share URL with users
4. ⬜ Users install as app on their devices
5. ⬜ Monitor usage in Azure Application Insights

---

## Support

**App not working?**
1. Check browser console (F12) for errors
2. Verify Function URL in Settings
3. Test Function endpoint with curl
4. Check Azure Function logs in Application Insights

**Need help?**
- Azure Static Web Apps docs: https://learn.microsoft.com/azure/static-web-apps/
- GitHub Pages docs: https://docs.github.com/pages

---

## Summary

✅ **One HTML file** - super simple  
✅ **Works everywhere** - iOS, Android, Desktop  
✅ **No compilation** - just HTML/CSS/JS  
✅ **Free hosting** - Azure or GitHub  
✅ **Installable** - feels like native app  
✅ **Production ready** - secure and fast  

Share the URL and users can start using it immediately! 🚀
