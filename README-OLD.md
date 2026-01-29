# BC Voice Assistant - Hackathon EMEA 2025

A voice-activated assistant for Business Central that allows users to query BC data using voice commands and receive spoken responses.

## 🎯 Overview

This proof-of-concept enables users to interact with Business Central hands-free - perfect for multitasking scenarios like exercising on a treadmill while managing business operations!

**Production Status (Jan 2026):** ✅ Fully operational with Azure OpenAI transcription
- Endpoint: Sweden Central (whisper + gpt-4o-mini)
- Function App: Windows Consumption (West Europe)
- Cost: ~$8-12/month typical usage
- See [LESSONS-LEARNED.md](LESSONS-LEARNED.md) for deployment insights

**NEW: 100% BC-Native Architecture!** No Azure required - everything runs in Business Central AL code.

### Key Features
- 🎤 **Voice Input**: Speak naturally to query Business Central data
- 🔊 **Voice Output**: Hear responses read aloud
- 🚀 **Pure BC**: All processing in AL - no external services needed
- 🐛 **Easy Debugging**: Standard AL debugging - no Azure complexity
- 📱 **Mobile-Ready**: Works in BC Mobile App via custom control add-in
- 🔗 **Direct Access**: Queries BC tables directly - fast and secure
- ⚡ **Optional AI**: Azure OpenAI integration available but not required

## 🏗️ Architecture

```
User Voice → Mobile Device (Speech-to-Text)
                ↓
    BC Mobile App (Control Add-in)
                ↓
    ╔════════════════════════════════════╗
    ║  Business Central (AL Code)       ║
    ║  • Intent Analysis                ║
    ║  • Query Execution                ║
    ║  • Response Formatting            ║
    ╚════════════════════════════════════╝
                ↓
    Mobile Device (Text-to-Speech) → User
```

### Components

1. **AL Extension** (`/src`)
   - Voice Assistant page
   - Custom control add-in
   - Intent analysis codeunit (pattern matching)
   - Query executor codeunit (direct table access)
   - Response formatter (natural language)

2. **Control Add-in** (`/src/controladdin`)
   - JavaScript using Web Speech API
   - Speech recognition (voice input)
   - Speech synthesis (voice output)
   - Visual status indicators

3. **Azure Backend** (`/AzureBackend`) - **OPTIONAL**
   - Only needed for advanced AI features
   - Basic functionality works without Azure

## 🚀 Getting Started

### Prerequisites

- Business Central SaaS environment
- BC Mobile App (iOS/Android)
- Visual Studio Code with AL Language extension
- **No Azure subscription needed!**

### 1. Deploy AL Extension

```powershell
# Navigate to project root
cd "c:\Users\44321157\OneDrive\VOICEACTIVATED-BC"

# Compile and publish
# (Use AL: Publish command in VS Code)
```

### 2. Deploy Azure Backend

```poweTest in BC Mobile App

1. Open BC Mobile App
2. Navigate to "Voice Assistant" page
3. Click **Start Listening**
4. Say: "Show me customers"
5. Hear the response!

**That's it!** No Azure setup needed.📱 Usage

1. Open **Voice Assistant** page in BC Mobile App
2. Click **Start Listening** button
3. Speak your query (see examples below)
4. Wait for processing
5. Hear the response spoken back

### Example Queries

- "Show me today's sales orders"
- "What's the inventory for item 1000?"
- "List top 5 customers by balance"
- "How many invoices this month?"
- "Tell me about customer Adatum Corporation"

## 🛠️ Development

### Project Structure

```
VOICEACTIVATED-BC/
├── app.json                          # AL app manifest
├── src/
│   ├── page/
│   │   └── Pag70000.VoiceAssistant.al
│   ├── codeunit/
│   │   └── Cod70000.VoiceAssistantMgt.al
│   ├── table/
│   │   └── Tab70000.VoiceAssistantSetup.al
│   └── controladdin/
│       ├── VoiceControlAddIn.al
│       ├── scripts/
│       │   └── VoiceControl.js
│       └── styles/
│           └── VoiceControl.css
└── AzureBackend/
    ├── ProcessVoiceQuery.cs
    ├── BCVoiceAssistant.csproj
    ├── host.json
    └── local.settings.json
```

### Extending the Solution

#### Add New Query Types

Edit `ProcessVoiceQuery.cs` → `AnalyzeQueryIntent()`:

```csharp
if (query.Contains("vendor"))
    intent.Entity = "Vendor";
```

#### Customize Voice UI

Edit `/src/controladdin/styles/VoiceControl.css`

#### Add BC Authentication

Update `ExecuteBCQuery()` to include OAuth2 token:

```csharp
request.Headers.Add("Authorization", "Bearer " + await GetBCToken());
```

## 🔐 Security Considerations

- **Authentication**: Implement OAuth2 for BC API calls
- **Authorization**: Respect BC user permissions
- **API Keys**: Store Azure OpenAI keys in Azure Key Vault
- **Function Auth**: Use Function-level or Azure AD authentication
- **Data Privacy**: Voice queries may contain sensitive business data

## 🎨 Customization Ideas

- [ ] Add support for multiple languages
- [ ] Implement conversation memory/context
- [ ] Add voice commands for creating records (not just querying)
- [ ] Support for Power BI report queries
- [ ] Integration with BC approvals workflow
- [ ] Offline mode with cached responses
- [ ] Voice authentication/security phrases

## 📊 Technical Details

### Web Speech API Support

The control add-in uses browser-native Speech APIs:
- **Chrome/Edge**: Full support (SpeechRecognition, SpeechSynthesis)
- **Safari iOS**: Speech Synthesis only (no recognition on iOS)
- **Firefox**: Limited support

### BC Mobile Compatibility

- Works on iOS and Android via BC Mobile App
- Requires device microphone permissions
- Internet connection required for backend processing

## 🧪 Testing

### Test Locally

1. Run Azure Function locally:
   ```powershell
   cd AzureBackend
   func start
   ```

2. Update BC extension to point to `http://localhost:7071/api/ProcessVoiceQuery`

3. Test in BC Web Client (with microphone)

### Pure BC Architecture

All query processing happens in AL:
- **Intent Analysis**: Pattern matching in AL (`Cod70000`)
- **Query Execution**: Direct table access (`Cod70001`)
- **Response Formatting**: String manipulation in AL
- **Performance**: ~250ms average (much faster than Azure!)

### Supported Entities

- Customers
- Sales Orders
- Items (Inventory)
- Sales Invoices
- Vendors

### Supported Filters

- **Time**: today, yesterday, this week, this month, this year
- **Top N**: "top 5", "top 10", etc.
- **Specific**: "customer 10000", "item 1000"

See [QUERY-PATTERNS.md](QUERY-PATTERNS.md) for complete list.
- Try Chrome/Edge instead of Safari

**Backend not responding?**
- Verify Azure Function URL is correct
- Check Function App logs in Azure Portal
- Ensure CORS is configured if testing from web

**BC queries failing?**
- Verify OData URL is correct
- Check BC authentication
- Confirm user has permission for requested entities

## 📝 License

This is a proof-of-concept for Directions EMEA 2025 Hackathon.

## 👥 Team

- Andreea Vlad ([@andreeavlad16-afk](https://github.com/andreeavlad16-afk))

## 🏆 Hackathon Info

- **Event**: Directions EMEA 2025 Hackathon
- **Issue**: [#8 BC voice agent](https://github.com/directions4partners/Hackathon-EMEA2025/issues/8)
- **Submission Deadline**: February 3rd, 2026
- **Webinar**: March 3rd, 2026

---

**Built with** ❤️ **for the BC Community**
