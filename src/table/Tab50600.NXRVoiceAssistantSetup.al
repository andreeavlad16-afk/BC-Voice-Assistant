/// <summary>
/// Configuration table for NXR Voice Assistant AI backend settings.
/// Stores API endpoints, model names, and other AI service configuration.
/// API keys are stored securely in Isolated Storage, not in the table.
/// </summary>
table 50600 "NXR Voice Assistant Setup"
{
    Caption = 'NXR Voice Assistant Setup';
    DataClassification = CustomerContent;

    fields
    {
        field(1; "Primary Key"; Code[10])
        {
            Caption = 'Primary Key';
            DataClassification = SystemMetadata;
        }

        field(10; "AI Backend Type"; Enum "NXR AI Backend Type")
        {
            Caption = 'AI Backend Type';
            DataClassification = CustomerContent;
        }

        field(20; "API Endpoint"; Text[250])
        {
            Caption = 'API Endpoint';
            ToolTip = 'OpenAI-compatible endpoint (e.g., http://localhost:1234/v1 for LocalLLM, or https://your-resource.openai.azure.com for Azure)';
            DataClassification = CustomerContent;
        }

        // API Key is NOT stored in the table - use Isolated Storage instead
        // This field is kept for display purposes only (masked indicator)
        field(30; "API Key Set"; Boolean)
        {
            Caption = 'API Key Configured';
            ToolTip = 'Indicates whether an API key has been securely stored';
            Editable = false;
            FieldClass = FlowField;
            CalcFormula = exist("NXR Voice Assistant Setup" where("Primary Key" = field("Primary Key")));
        }

        field(40; "Model Name"; Text[100])
        {
            Caption = 'Model Name';
            ToolTip = 'Model to use (e.g., gpt-4o, gpt-4o-mini, gpt-3.5-turbo)';
            DataClassification = CustomerContent;
        }

        field(50; "Azure Deployment Name"; Text[100])
        {
            Caption = 'Azure Deployment Name';
            ToolTip = 'Azure OpenAI deployment name (only for Azure backend)';
            DataClassification = CustomerContent;
        }

        field(60; "Azure API Version"; Text[50])
        {
            Caption = 'Azure API Version';
            ToolTip = 'Azure OpenAI API version (e.g., 2024-08-06)';
            DataClassification = CustomerContent;
            InitValue = '2024-08-06';
        }

        field(70; "Fallback to Pattern Matching"; Boolean)
        {
            Caption = 'Fallback to Pattern Matching';
            ToolTip = 'If AI backend fails, use basic pattern matching';
            DataClassification = CustomerContent;
            InitValue = true;
        }

        field(80; "Max Tokens"; Integer)
        {
            Caption = 'Max Tokens';
            ToolTip = 'Maximum tokens for AI response (default: 500)';
            DataClassification = CustomerContent;
            InitValue = 500;
            MinValue = 100;
            MaxValue = 4000;
        }

        field(90; "Transcription Proxy URL"; Text[250])
        {
            Caption = 'Transcription Proxy URL';
            ToolTip = 'Azure Function URL for audio transcription (e.g., https://your-function.azurewebsites.net/api/transcribe). Required for BC Mobile App voice input.';
            DataClassification = CustomerContent;
        }

        field(100; "BC OData Base URL"; Text[250])
        {
            Caption = 'BC OData Base URL';
            ToolTip = 'Business Central OData API base URL (e.g., https://api.businesscentral.dynamics.com/v2.0/tenant/env/api/v2.0/). Leave blank to use current environment.';
            DataClassification = CustomerContent;
        }

        field(110; "Debug Mode"; Boolean)
        {
            Caption = 'Debug Mode';
            ToolTip = 'Show debug messages during query execution (for troubleshooting)';
            DataClassification = CustomerContent;
            InitValue = false;
        }

        field(120; "Text Only Mode"; Boolean)
        {
            Caption = 'Text Only Mode';
            ToolTip = 'Disable voice output (silent mode - responses shown as text only). Useful for testing without disturbing others.';
            DataClassification = CustomerContent;
            InitValue = false;
        }

        field(130; "OData Schema Context"; Blob)
        {
            Caption = 'OData Schema Context';
            ToolTip = 'Cached schema from OData $metadata endpoint. Refreshed via Refresh Schema action.';
            DataClassification = CustomerContent;
        }

        field(140; "Schema Last Updated"; DateTime)
        {
            Caption = 'Schema Last Updated';
            ToolTip = 'Timestamp of last schema refresh from OData';
            DataClassification = CustomerContent;
            Editable = false;
        }

        field(150; "Conversation History Size"; Integer)
        {
            Caption = 'Conversation History Size';
            ToolTip = 'Number of previous messages to include as context (default: 10)';
            DataClassification = SystemMetadata;
            InitValue = 10;
            MinValue = 0;
            MaxValue = 50;
        }
    }

    keys
    {
        key(PK; "Primary Key")
        {
            Clustered = true;
        }
    }

    var
        ApiKeyLbl: Label 'VoiceAssistant_ApiKey', Locked = true;

    /// <summary>
    /// Securely stores the API key in Isolated Storage.
    /// </summary>
    /// <param name="ApiKey">The API key to store (SecretText for security).</param>
    procedure SetApiKey(ApiKey: SecretText)
    begin
        if ApiKey.IsEmpty() then
            IsolatedStorage.Delete(ApiKeyLbl, DataScope::Module)
        else
            IsolatedStorage.Set(ApiKeyLbl, ApiKey, DataScope::Module);
    end;

    /// <summary>
    /// Retrieves the securely stored API key from Isolated Storage.
    /// </summary>
    /// <returns>The stored API key as SecretText, or empty SecretText if not set.</returns>
    procedure GetApiKey(): SecretText
    var
        ApiKeyValue: SecretText;
    begin
        if IsolatedStorage.Get(ApiKeyLbl, DataScope::Module, ApiKeyValue) then
            exit(ApiKeyValue);
        exit(ApiKeyValue); // Returns empty SecretText
    end;

    /// <summary>
    /// Checks whether an API key has been configured.
    /// </summary>
    /// <returns>True if an API key exists in Isolated Storage, false otherwise.</returns>
    procedure HasApiKey(): Boolean
    begin
        exit(IsolatedStorage.Contains(ApiKeyLbl, DataScope::Module));
    end;

    /// <summary>
    /// Removes the API key from Isolated Storage.
    /// </summary>
    procedure ClearApiKey()
    begin
        if IsolatedStorage.Contains(ApiKeyLbl, DataScope::Module) then
            IsolatedStorage.Delete(ApiKeyLbl, DataScope::Module);
    end;

    /// <summary>
    /// Tests the connection to the configured AI backend service.
    /// </summary>
    /// <returns>True if connection is successful, false otherwise.</returns>
    procedure TestConnection(): Boolean
    var
        VoiceAIService: Codeunit "NXR Voice AI Service";
        Detail: Text;
    begin
        exit(VoiceAIService.TestConnectionWithDetail(Detail));
    end;
}
