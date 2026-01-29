// BC Voice Assistant - Complete Infrastructure as Code
// Deploys all Azure resources needed for the voice assistant
// Region: UK South (Whisper model availability)

@description('Base name for all resources')
param baseName string = 'bcvoice'

@description('Environment suffix (dev, prod)')
param environment string = 'prod'

@description('Location for all resources - Sweden Central has confirmed Whisper availability')
param location string = 'swedencentral'

@description('Unique identifier for resource names')
param uniqueId string = uniqueString(resourceGroup().id)

// Variables
var resourcePrefix = '${baseName}-${environment}'
var openAIName = 'openai-${resourcePrefix}-${uniqueId}'
var functionAppName = 'func-${resourcePrefix}-${uniqueId}'
var storageAccountName = 'st${baseName}${uniqueId}'
var signalRName = 'signalr-${resourcePrefix}-${uniqueId}'
var appInsightsName = 'appi-${resourcePrefix}-${uniqueId}'
var appServicePlanName = 'asp-${resourcePrefix}-${uniqueId}'

// Azure OpenAI Resource
resource openAI 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: openAIName
  location: location
  kind: 'OpenAI'
  sku: {
    name: 'S0'
  }
  properties: {
    customSubDomainName: openAIName
    publicNetworkAccess: 'Enabled'
  }
}

// Deploy GPT-4o-mini model
resource gptDeployment 'Microsoft.CognitiveServices/accounts/deployments@2023-05-01' = {
  parent: openAI
  name: 'gpt-4o-mini'
  sku: {
    name: 'Standard'
    capacity: 50
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-4o-mini'
      version: '2024-07-18'
    }
    versionUpgradeOption: 'OnceCurrentVersionExpired'
    raiPolicyName: 'Microsoft.Default'
  }
}

// Deploy Whisper model
resource whisperDeployment 'Microsoft.CognitiveServices/accounts/deployments@2023-05-01' = {
  parent: openAI
  name: 'whisper'
  sku: {
    name: 'Standard'
    capacity: 1
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'whisper'
      version: '001'
    }
    versionUpgradeOption: 'OnceCurrentVersionExpired'
  }
  dependsOn: [
    gptDeployment // Deploy sequentially to avoid conflicts
  ]
}

// Storage Account for Functions
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
  }
}

// Application Insights
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// App Service Plan (Consumption)
resource appServicePlan 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: appServicePlanName
  location: location
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  properties: {}
}

// SignalR Service
resource signalR 'Microsoft.SignalRService/signalR@2023-02-01' = {
  name: signalRName
  location: location
  sku: {
    name: 'Free_F1'
    tier: 'Free'
    capacity: 1
  }
  properties: {
    cors: {
      allowedOrigins: ['*']
    }
    features: [
      {
        flag: 'ServiceMode'
        value: 'Serverless'
      }
    ]
  }
}

// Function App
resource functionApp 'Microsoft.Web/sites@2022-09-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp'
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${az.environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${az.environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower(functionAppName)
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'node'
        }
        {
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: '~18'
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: appInsights.properties.InstrumentationKey
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights.properties.ConnectionString
        }
        {
          name: 'AZURE_OPENAI_ENDPOINT'
          value: openAI.properties.endpoint
        }
        {
          name: 'AZURE_OPENAI_KEY'
          value: openAI.listKeys().key1
        }
        {
          name: 'AZURE_OPENAI_DEPLOYMENT'
          value: 'gpt-4o-mini'
        }
        {
          name: 'AZURE_OPENAI_WHISPER_DEPLOYMENT'
          value: 'whisper'
        }
        {
          name: 'AZURE_OPENAI_API_VERSION'
          value: '2024-08-06'
        }
        {
          name: 'AzureSignalRConnectionString'
          value: signalR.listKeys().primaryConnectionString
        }
        {
          name: 'NODE_ENV'
          value: 'production'
        }
      ]
      cors: {
        allowedOrigins: ['*']
      }
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
    }
  }
}

// Outputs
output resourceGroupName string = resourceGroup().name
output location string = location
output openAIName string = openAI.name
output openAIEndpoint string = openAI.properties.endpoint
output openAIKey string = openAI.listKeys().key1
output gptDeploymentName string = gptDeployment.name
output whisperDeploymentName string = whisperDeployment.name
output functionAppName string = functionApp.name
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'
output transcribeUrl string = 'https://${functionApp.properties.defaultHostName}/api/transcribe'
output storageAccountName string = storageAccount.name
output signalRName string = signalR.name
output signalRConnectionString string = signalR.listKeys().primaryConnectionString
output appInsightsInstrumentationKey string = appInsights.properties.InstrumentationKey
