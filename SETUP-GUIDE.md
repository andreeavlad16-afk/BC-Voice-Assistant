# BC Voice Assistant - Setup Guide

## Quick Start for New Users

This guide will help you set up the BC Voice Assistant in your environment.

## Prerequisites

### Required
- Business Central SaaS or On-Premise environment
- Visual Studio Code with AL Language extension
- BC Mobile App (iOS/Android) for voice features

### Optional (for Azure integration)
- Azure subscription
- Azure CLI or PowerShell Az module

## Architecture Options

### Option 1: BC-Native Only (Recommended for Getting Started)
- ✅ No Azure required
- ✅ All processing in Business Central AL code
- ✅ Easy debugging
- ⚠️ Limited to BC Mobile's native speech capabilities

### Option 2: Azure-Enhanced (Production Ready)
- ✅ Azure OpenAI for advanced transcription (Whisper)
- ✅ GPT-4o-mini for intelligent query processing
- ✅ Azure Functions for relay services
- ⚠️ Requires Azure subscription (~$8-12/month)

---

## Setup Instructions

### Step 1: Deploy Business Central Extension

1. **Clone this repository**
   ```bash
   git clone https://github.com/andreeavlad16-afk/BC-Voice-Assistant
   cd BC-Voice-Assistant
   ```

2. **Open in VS Code**
   ```bash
   code .
   ```

3. **Configure your BC environment**
   - Edit `app.json` to set your publisher name and version
   - Update launch.json with your BC instance details

4. **Compile and publish**
   - Press `Ctrl+Shift+P` and select "AL: Publish"
   - Or use F5 to publish and debug

5. **Configure the extension**
   - Open Business Central
   - Search for "NXR Voice Assistant Setup" (or "BC Voice Assistant Setup")
   - Configure basic settings

### Step 2: Test Basic Functionality

1. **Open the Voice Assistant page**
   - Search for "Voice Assistant" in BC
   - The page should load with voice controls

2. **Test without Azure** (BC-Native mode)
   - Click "Start Listening"
   - Speak: "Show me customers"
   - The system should process your request using pattern matching

### Step 3: Azure Integration (Optional)

#### 3.1 Deploy Azure Infrastructure (One Command!)

The repository includes complete Infrastructure as Code (Bicep templates) for automated deployment.

**Prerequisites:**
- Azure CLI installed: `az --version`
- Logged in to Azure: `az login`

**Deploy everything in one command:**

```bash
# Clone the repository
git clone <your-repo-url>
cd bc-voice-assistant

# Login to Azure (opens browser)
az login

# Create resource group
az group create \
  --name rg-bcvoice-prod \
  --location swedencentral

# Deploy all infrastructure (5-10 minutes)
cd infrastructure
az deployment group create \
  --resource-group rg-bcvoice-prod \
  --template-file main.bicep \
  --parameters baseName=bcvoice environment=prod

# Save the output - you'll need these values!
```

**What gets deployed automatically:**

| Resource | Purpose | Tier/SKU |
|----------|---------|----------|
| Azure OpenAI | Whisper + GPT-4o-mini models | S0 (Standard) |
| Azure Functions | Serverless backend (4 functions) | Windows Consumption |
| Azure SignalR | Real-time communication | Free |
| Storage Account | Function state and data | Standard LRS |
| Application Insights | Monitoring and logging | Basic |
| App Service Plan | Hosts the functions | Consumption (Y1) |

**Deployment output example:**
```json
{
  "openAIEndpoint": "https://openai-bcvoice-prod-abc123.openai.azure.com/",
  "openAIKey": "your-api-key-here",
  "functionAppName": "func-bcvoice-prod-abc123",
  "functionAppUrl": "https://func-bcvoice-prod-abc123.azurewebsites.net",
  "signalRConnectionString": "Endpoint=https://...",
  "storageConnectionString": "DefaultEndpointsProtocol=https;..."
}
```

**📋 Save these values!** You'll need them for configuration.

**Verify deployment:**
```bash
# Check function app is running
az functionapp show \
  --name <your-function-app-name> \
  --resource-group rg-bcvoice-prod \
  --query "state" -o tsv
# Should return: Running

# Check OpenAI models deployed
az cognitiveservices account deployment list \
  --name <your-openai-resource-name> \
  --resource-group rg-bcvoice-prod
# Should show: gpt-4o-mini, whisper
```

**Troubleshooting:**
- **Quota issues**: If OpenAI deployment fails, request quota increase in Azure Portal
- **Model availability**: Whisper not available in all regions - Sweden Central is confirmed
- **Deployment timeout**: Increase timeout with `--timeout` parameter

#### 3.2 Configure Azure OpenAI

1. **Deploy models**
   - Go to Azure Portal → Your OpenAI resource
   - Navigate to "Model deployments"
   - Deploy "whisper" model
   - Deploy "gpt-4o-mini" model

2. **Get your API key**
   - In Azure Portal, go to your OpenAI resource
   - Click "Keys and Endpoint"
   - Copy Key 1 or Key 2

3. **Update configuration**
   - Copy `azure-relay/local.settings.json.example` to `azure-relay/local.settings.json`
   - Fill in your Azure OpenAI details:
     ```json
     {
       "Values": {
         "AZURE_OPENAI_KEY": "your-key-here",
         "AZURE_OPENAI_ENDPOINT": "https://your-resource.openai.azure.com/",
         "AzureWebJobsStorage": "your-storage-connection-string",
         "AzureSignalRConnectionString": "your-signalr-connection-string"
       }
     }
     ```

#### 3.3 Deploy Azure Functions

**Prerequisites:**
- Azure Functions Core Tools: `npm install -g azure-functions-core-tools@4`
- Node.js 20.x: `node --version`

**Deployment steps:**

```bash
cd azure-relay

# Install dependencies
npm install

# Optional: Test locally first
func start
# Visit: http://localhost:7071/api/health

# Deploy to Azure (uses the function app created by Bicep)
func azure functionapp publish <your-function-app-name>

# Example:
# func azure functionapp publish func-bcvoice-prod-abc123
```

**What gets deployed:**
- ✅ `/api/transcribe` - Whisper audio transcription
- ✅ `/api/query` - BC OData query execution
- ✅ `/api/voiceQuery` - Complete voice workflow
- ✅ `/api/negotiate` - SignalR connection negotiation

**Verify deployment:**
```bash
# Test health endpoint
curl https://<your-function-app-name>.azurewebsites.net/api/health

# Expected response:
# {"status": "healthy", "timestamp": "2026-01-29T..."}
```

**Configure Azure Function App Settings:**

The Bicep template automatically configures these, but verify:

```bash
# Check configuration
az functionapp config appsettings list \
  --name <your-function-app-name> \
  --resource-group rg-bcvoice-prod

# Should include:
# - AZURE_OPENAI_KEY
# - AZURE_OPENAI_ENDPOINT
# - AzureWebJobsStorage
# - AzureSignalRConnectionString
```

**Update BC Configuration:**

1. Open Business Central
2. Search: "NXR Voice Assistant Setup"
3. Configure:
   - **Backend Type**: Azure Functions
   - **Azure Function URL**: `https://<your-function-app-name>.azurewebsites.net`
   - **Azure OpenAI Endpoint**: (from deployment output)
   - **Azure OpenAI Key**: (from deployment output)
4. Click "Test Connection" - should succeed!
5. Save

### Step 4: Configure Business Central API Access

If using Azure Functions to query BC:

1. **Create Azure AD App Registration**
   - Go to Azure Portal → Azure Active Directory → App registrations
   - Click "New registration"
   - Name: "BC Voice Assistant"
   - Redirect URI: `https://your-function-app.azurewebsites.net/.auth/login/aad/callback`

2. **Configure API permissions**
   - Add Dynamics 365 Business Central permissions
   - Grant "user_impersonation" or specific API scopes

3. **Update .env.template**
   - Copy `AzureBackend/.env.template` to `AzureBackend/.env`
   - Fill in:
     ```
     BC_BASE_URL=https://api.businesscentral.dynamics.com/v2.0/YOUR-TENANT/YOUR-ENV/ODataV4/
     BC_CLIENT_ID=your-app-registration-id
     BC_CLIENT_SECRET=your-client-secret
     BC_TENANT_ID=your-tenant-id
     ```

---

## Testing Your Setup

### Basic Tests

1. **Voice Recognition Test**
   - Open Voice Assistant page in BC Mobile App
   - Click "Start Listening"
   - Say: "Show me customers"
   - Should see/hear results

2. **Azure Function Test** (if using Azure)
   ```powershell
   # Test negotiate endpoint
   Invoke-RestMethod -Uri "https://your-function-app.azurewebsites.net/api/negotiate" -Method Post
   
   # Should return SignalR connection info
   ```

3. **Transcription Test** (if using Azure)
   ```powershell
   # Test transcribe endpoint with audio file
   $headers = @{ "Content-Type" = "audio/wav" }
   Invoke-RestMethod -Uri "https://your-function-app.azurewebsites.net/api/transcribe" `
     -Method Post -InFile "test-audio.wav" -Headers $headers
   ```

### Example Queries

Try these voice commands:
- "Show me today's sales orders"
- "What's the inventory for item 1000?"
- "List top 5 customers by balance"
- "How many invoices this month?"
- "Tell me about customer Adatum Corporation"

---

## Troubleshooting

### Issue: "Function not found"
- Verify function app is deployed and running
- Check Application Insights logs
- Ensure CORS is configured correctly

### Issue: "Azure OpenAI quota exceeded"
- Request quota increase in Azure Portal
- Or use BC-Native mode without Azure

### Issue: "Permission denied" on BC API
- Verify Azure AD app registration permissions
- Check BC user permissions
- Ensure OAuth token is being passed correctly

### Issue: Voice not working on mobile
- Ensure device has microphone permissions
- Check BC Mobile App is up to date
- Verify network connectivity

---

## Configuration Files Reference

### Required Files (Create from templates)

| File | Template | Purpose |
|------|----------|---------|
| `azure-relay/local.settings.json` | `local.settings.json.example` | Azure Function configuration |
| `AzureBackend/.env` | `.env.template` | BC API credentials |
| `infrastructure/deployment-config.json` | Update with your resource names | Azure deployment tracking |

### Important: Security

⚠️ **NEVER commit these files to git:**
- `local.settings.json`
- `.env`
- `deployment-config.json` (with real values)
- Any file containing API keys or connection strings

These are already in `.gitignore` but be careful!

---

## Cost Estimation

### Azure Resources (Optional)

| Resource | Tier | Est. Monthly Cost |
|----------|------|-------------------|
| Azure OpenAI | Pay-as-you-go | $2-5 (light usage) |
| Azure Functions | Consumption | $1-3 |
| SignalR Service | Free | $0 |
| Storage Account | Standard | $1-2 |
| **Total** | | **$4-10/month** |

### BC-Native Only

| Cost | Amount |
|------|--------|
| Azure | $0 |
| BC License | Existing |
| **Total** | **$0/month** |

---

## Next Steps

1. **Customize the solution**
   - Add your own query patterns
   - Customize the UI/UX
   - Add new entities

2. **Extend functionality**
   - Add support for creating records (not just querying)
   - Integrate with BC workflows
   - Add conversation memory

3. **Production deployment**
   - Enable Azure AD authentication on Function Apps
   - Set up proper monitoring and alerting
   - Implement error handling and logging
   - Regular security reviews

---

## Getting Help

- Check existing documentation in the repository
- Review Application Insights logs for Azure errors
- Check BC Error Messages page for AL errors
- Review the source code comments for implementation details

## Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

---

**Last Updated**: January 29, 2026  
**Version**: 2.1.4.3
