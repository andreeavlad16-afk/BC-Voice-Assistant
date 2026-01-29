# BC Voice Assistant - PWA

Standalone Progressive Web App for BC Voice Assistant with full microphone access on Android & iOS.

## 🚀 Quick Start

### Option 1: Local Development
```bash
cd pwa
npx serve .
# Opens at http://localhost:3000
```

### Option 2: Host on GitHub Pages / Vercel / Netlify
1. Push the `pwa/` folder to a repository
2. Enable GitHub Pages or deploy to Vercel/Netlify
3. Access via HTTPS (required for microphone access)

## 📱 Installing on Mobile

### Android
1. Open the PWA URL in Chrome
2. Tap the menu (⋮) → "Add to Home Screen"
3. The app will install with full microphone access

### iOS
1. Open the PWA URL in Safari
2. Tap the Share button → "Add to Home Screen"
3. The app will install as a standalone app

## ⚙️ Configuration

On first launch, tap ⚙️ to configure:

1. **BC Environment URL**: Your BC environment URL
   - Format: `https://businesscentral.dynamics.com/{tenant-id}/{environment-name}`
   
2. **Azure AD Client ID**: App Registration Client ID
   
3. **Azure AD Tenant ID**: Your Azure AD Tenant ID

## 🔐 Azure AD App Registration

Create an App Registration in Azure Portal:

1. Go to Azure Portal → Azure Active Directory → App registrations
2. New registration:
   - Name: "BC Voice Assistant PWA"
   - Supported account types: "Accounts in this organizational directory only"
   - Redirect URI: (Web) `https://your-pwa-url.com/` or `http://localhost:3000/` for dev
3. API permissions:
   - Add: "Dynamics 365 Business Central" → Delegated → "user_impersonation"
4. Authentication:
   - Enable: "Access tokens" and "ID tokens"
   - Add platform: "Single-page application" with your redirect URI

## 📁 Files

```
pwa/
├── index.html      # Main HTML structure
├── app.js          # Application logic (speech, auth, API)
├── styles.css      # Mobile-optimized styles
├── manifest.json   # PWA manifest for installation
├── sw.js           # Service worker for offline support
└── icons/          # App icons (generate from icon.svg)
    └── icon.svg    # Source icon
```

## 🎨 Generating Icons

Use a tool like https://realfavicongenerator.net/ or run:

```bash
# Using ImageMagick
for size in 72 96 128 144 152 192 384 512; do
  convert icons/icon.svg -resize ${size}x${size} icons/icon-${size}.png
done
```

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────┐
│              PWA (This App)                      │
│  ┌─────────────┐  ┌──────────────┐              │
│  │ Web Speech  │  │ MSAL.js      │              │
│  │ API         │  │ (Azure AD)   │              │
│  └──────┬──────┘  └──────┬───────┘              │
│         │                │                       │
│         ▼                ▼                       │
│  ┌─────────────────────────────────────────┐    │
│  │         app.js (Business Logic)          │    │
│  └─────────────────────────────────────────┘    │
└─────────────────────────┬───────────────────────┘
                          │ HTTPS + Bearer Token
                          ▼
┌─────────────────────────────────────────────────┐
│        Business Central                          │
│  ┌─────────────────────────────────────────┐    │
│  │  Pag50213.VoiceCommandAPI                │    │
│  │  POST /api/hackathon/voiceAssistant/...  │    │
│  └──────────────────────────────────────────┘    │
│                    │                             │
│                    ▼                             │
│  ┌─────────────────────────────────────────┐    │
│  │  Existing Voice Processing Codeunits     │    │
│  │  - VoiceAssistantMgt                     │    │
│  │  - VoiceDynamicQueryExecutor             │    │
│  │  - VoiceAIService                        │    │
│  └─────────────────────────────────────────┘    │
└─────────────────────────────────────────────────┘
```

## ✅ Features

- 🎤 **Full Microphone Access**: Works on all mobile browsers
- 📱 **Installable**: Add to home screen like a native app
- 🔐 **Secure**: Azure AD OAuth2 authentication
- 💬 **Voice Output**: Text-to-speech responses
- ⌨️ **Text Fallback**: Type queries when voice isn't available
- 🌙 **Dark Mode**: Automatic dark theme support
- 📴 **Offline UI**: Service worker caches the app shell
