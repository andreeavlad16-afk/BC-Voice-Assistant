/// <summary>
/// Configuration page for Voice Assistant AI backend settings.
/// Allows setup of OpenAI, Azure OpenAI, or Local LLM connections.
/// </summary>
page 50611 "NXR Voice Assistant Setup"
{
    PageType = Card;
    ApplicationArea = All;
    UsageCategory = Administration;
    Caption = 'Voice Assistant Setup';
    SourceTable = "NXR Voice Assistant Setup";
    InsertAllowed = false;
    DeleteAllowed = false;

    layout
    {
        area(Content)
        {
            group(General)
            {
                Caption = 'AI Backend Configuration';

                field("AI Backend Type"; Rec."AI Backend Type")
                {
                    ApplicationArea = All;
                    ToolTip = 'Select the AI backend to use for query parsing';

                    trigger OnValidate()
                    begin
                        UpdateVisibility();
                    end;
                }

                field("Fallback to Pattern Matching"; Rec."Fallback to Pattern Matching")
                {
                    ApplicationArea = All;
                    ToolTip = 'If AI backend fails or is unavailable, fall back to basic pattern matching';
                }
            }

            group(OpenAISettings)
            {
                Caption = 'OpenAI Settings';
                Visible = ShowOpenAI;

                field(OpenAIModel; Rec."Model Name")
                {
                    ApplicationArea = All;
                    Caption = 'Model';
                    ToolTip = 'OpenAI model to use (e.g., gpt-4o, gpt-4o-mini, gpt-3.5-turbo)';
                }

                field(OpenAIApiKey; ApiKeyInput)
                {
                    ApplicationArea = All;
                    Caption = 'API Key';
                    ToolTip = 'Your OpenAI API key (securely stored)';
                    ExtendedDatatype = Masked;

                    trigger OnValidate()
                    begin
                        if ApiKeyInput <> '' then begin
                            Rec.SetApiKey(ApiKeyInput);
                            ApiKeyInput := '********';
                            UpdateApiKeyStatus();
                            Message('API Key saved securely.');
                        end;
                    end;
                }

                field(OpenAIKeyStatus; ApiKeyStatusText)
                {
                    ApplicationArea = All;
                    Caption = 'API Key Status';
                    Editable = false;
                    Style = Favorable;
                    StyleExpr = HasApiKeyConfigured;
                }

                field("Max Tokens"; Rec."Max Tokens")
                {
                    ApplicationArea = All;
                    ToolTip = 'Maximum tokens for AI response';
                }
            }

            group(AzureSettings)
            {
                Caption = 'Azure OpenAI Settings';
                Visible = ShowAzure;

                field(AzureEndpoint; Rec."API Endpoint")
                {
                    ApplicationArea = All;
                    Caption = 'Azure Endpoint';
                    ToolTip = 'Your Azure OpenAI resource endpoint (e.g., https://your-resource.openai.azure.com)';
                }

                field("Azure Deployment Name"; Rec."Azure Deployment Name")
                {
                    ApplicationArea = All;
                    ToolTip = 'The deployment name in Azure OpenAI';
                }

                field("Azure API Version"; Rec."Azure API Version")
                {
                    ApplicationArea = All;
                    ToolTip = 'Azure OpenAI API version';
                }

                field(AzureApiKey; ApiKeyInput)
                {
                    ApplicationArea = All;
                    Caption = 'API Key';
                    ToolTip = 'Your Azure OpenAI API key (securely stored)';
                    ExtendedDatatype = Masked;

                    trigger OnValidate()
                    begin
                        if ApiKeyInput <> '' then begin
                            Rec.SetApiKey(ApiKeyInput);
                            ApiKeyInput := '********';
                            UpdateApiKeyStatus();
                            Message('API Key saved securely.');
                        end;
                    end;
                }

                field(AzureKeyStatus; ApiKeyStatusText)
                {
                    ApplicationArea = All;
                    Caption = 'API Key Status';
                    Editable = false;
                    Style = Favorable;
                    StyleExpr = HasApiKeyConfigured;
                }

                field(AzureModel; Rec."Model Name")
                {
                    ApplicationArea = All;
                    Caption = 'Model (Optional)';
                    ToolTip = 'Override model name if different from deployment';
                }

                field(AzureMaxTokens; Rec."Max Tokens")
                {
                    ApplicationArea = All;
                    ToolTip = 'Maximum tokens for AI response';
                }
            }

            group(LocalLLMSettings)
            {
                Caption = 'Local LLM Settings';
                Visible = ShowLocalLLM;

                field(LocalLLMWarning; LocalLLMWarningText)
                {
                    ApplicationArea = All;
                    Caption = 'Important';
                    Editable = false;
                    MultiLine = true;
                    Style = StrongAccent;
                    StyleExpr = true;
                    ShowCaption = false;
                }

                field(LocalEndpoint; Rec."API Endpoint")
                {
                    ApplicationArea = All;
                    Caption = 'LLM Endpoint';
                    ToolTip = 'Local LLM endpoint (e.g., http://yourserver:1234/v1 for LM Studio)';
                }

                field(LocalModel; Rec."Model Name")
                {
                    ApplicationArea = All;
                    Caption = 'Model Name';
                    ToolTip = 'Model name if required by your local LLM';
                }

                field(LocalApiKey; ApiKeyInput)
                {
                    ApplicationArea = All;
                    Caption = 'API Key (Optional)';
                    ToolTip = 'API key if your local LLM requires authentication';
                    ExtendedDatatype = Masked;

                    trigger OnValidate()
                    begin
                        if ApiKeyInput <> '' then begin
                            Rec.SetApiKey(ApiKeyInput);
                            ApiKeyInput := '********';
                            Message('API Key saved securely.');
                        end;
                    end;
                }
            }

            group(OnDeviceInfo)
            {
                Caption = 'On-Device AI Information';
                Visible = ShowOnDevice;

                field(OnDeviceNote; OnDeviceInfoText)
                {
                    ApplicationArea = All;
                    Caption = 'Note';
                    Editable = false;
                    MultiLine = true;
                    ShowCaption = false;
                }
            }

            group(MobileSettings)
            {
                Caption = 'Mobile App Settings (BC Mobile App)';

                field("Transcription Proxy URL"; Rec."Transcription Proxy URL")
                {
                    ApplicationArea = All;
                    ToolTip = 'Azure Function URL for audio transcription. Required for voice input on BC Mobile App. Format: https://your-function.azurewebsites.net/api/transcribe';
                    MultiLine = false;
                }

                field(MobileNote; MobileNoteText)
                {
                    ApplicationArea = All;
                    Caption = '';
                    Editable = false;
                    MultiLine = true;
                    ShowCaption = false;
                    Style = Subordinate;
                    StyleExpr = true;
                }
            }

            group(DebugSettings)
            {
                Caption = 'Debug & Troubleshooting';

                field("Conversation History Size"; Rec."Conversation History Size")
                {
                    ApplicationArea = All;
                    ToolTip = 'Number of previous messages to include as context (0-50, default: 10). Higher values provide more context but consume more tokens.';
                }

                field("Debug Mode"; Rec."Debug Mode")
                {
                    ApplicationArea = All;
                    ToolTip = 'Enable to show debug messages during query execution (useful for troubleshooting AI query interpretation)';
                }

                field("Text Only Mode"; Rec."Text Only Mode")
                {
                    ApplicationArea = All;
                    ToolTip = 'Disable voice output (silent mode). Responses will only appear as text. Useful for testing without disturbing others.';
                }

                field("Schema Last Updated"; Rec."Schema Last Updated")
                {
                    ApplicationArea = All;
                    ToolTip = 'Last time OData schema was refreshed from BC APIs. Use Refresh OData Schema action to update.';
                }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(TestConnection)
            {
                ApplicationArea = All;
                Caption = 'Test Connection';
                Image = TestDatabase;
                Promoted = true;
                PromotedCategory = Process;
                PromotedIsBig = true;

                trigger OnAction()
                var
                    VoiceAIService: Codeunit "NXR Voice AI Service";
                    BackendTypeText: Text;
                    TestResult: Boolean;
                    AITestResult: Boolean;
                    AIResponseText: Text;
                begin
                    if Rec."AI Backend Type" = Rec."AI Backend Type"::None then begin
                        Message('No AI backend configured. Pattern matching will be used.');
                        exit;
                    end;

                    if Rec."AI Backend Type" = Rec."AI Backend Type"::OnDeviceAI then begin
                        Message('On-device AI is handled by the browser. No server connection to test.');
                        exit;
                    end;

                    // Save the record first to ensure we're testing current settings
                    CurrPage.Update(true);
                    Commit();

                    // Validate required fields
                    BackendTypeText := Format(Rec."AI Backend Type");
                    case Rec."AI Backend Type" of
                        Rec."AI Backend Type"::OpenAI:
                            if not Rec.HasApiKey() then begin
                                Error('OpenAI requires an API key. Please enter and save your API key before testing.');
                            end;
                        Rec."AI Backend Type"::AzureOpenAI:
                            begin
                                if not Rec.HasApiKey() then
                                    Error('Azure OpenAI requires an API key. Please enter and save your API key before testing.');
                                if Rec."API Endpoint" = '' then
                                    Error('Azure OpenAI requires an API Endpoint (e.g., https://your-resource.openai.azure.com).');
                                if Rec."Azure Deployment Name" = '' then
                                    Error('Azure OpenAI requires a Deployment Name.');
                            end;
                        Rec."AI Backend Type"::LocalLLM:
                            if Rec."API Endpoint" = '' then
                                Error('Local LLM requires an API Endpoint (e.g., http://localhost:1234).');
                    end;

                    // Test the connection first (with diagnostics)
                    TestResult := VoiceAIService.TestConnectionWithDetail(AIResponseText);

                    if not TestResult then
                        Error('✗ Connection failed.\\Possible issues:\\- Invalid or expired API key\\- Incorrect endpoint URL\\- Network connectivity problems\\- Service is down\\\\Backend: %1\\Endpoint: %2\\Detail: %3\\\\Please verify your settings and try again.', BackendTypeText, GetEndpointDisplay(), AIResponseText);

                    // Connection successful, now test with actual AI query
                    AITestResult := VoiceAIService.TestQueryAI(AIResponseText);

                    if AITestResult then
                        Message('✓ Connection successful!\\Backend: %1\\Endpoint: %2\\\\✓ AI Test Query Successful:\\%3', BackendTypeText, GetEndpointDisplay(), AIResponseText)
                    else
                        Message('✓ Connection successful!\\Backend: %1\\Endpoint: %2\\\\⚠ AI test query failed: %3\\\\The connection works but AI may not be responding correctly.', BackendTypeText, GetEndpointDisplay(), AIResponseText);
                end;
            }

            action(ClearApiKey)
            {
                ApplicationArea = All;
                Caption = 'Clear API Key';
                Image = Delete;
                Promoted = true;
                PromotedCategory = Process;

                trigger OnAction()
                begin
                    if Confirm('Are you sure you want to remove the stored API key?') then begin
                        Rec.ClearApiKey();
                        ApiKeyInput := '';
                        Message('API key removed.');
                    end;
                end;
            }

            action(OpenVoiceAssistant)
            {
                ApplicationArea = All;
                Caption = 'Open Voice Assistant';
                Image = Start;
                Promoted = true;
                PromotedCategory = Process;
                PromotedIsBig = true;
                RunObject = page "NXR Voice Assistant";
            }

            action(RefreshSchema)
            {
                ApplicationArea = All;
                Caption = 'Refresh Schema from OData Metadata';
                Image = RefreshLines;
                Promoted = true;
                PromotedCategory = Process;
                ToolTip = 'Build schema from OData $metadata (field-level), cache for AI queries';

                trigger OnAction()
                var
                    SchemaContext: Codeunit "NXR Schema Context";
                    ODataSchemaDiscovery: Codeunit "NXR OData Schema Discovery";
                    SchemaText: Text;
                begin
                    SchemaText := ODataSchemaDiscovery.DiscoverODataSchema();
                    SchemaContext.SetSchemaContext(SchemaText);
                    CurrPage.Update(false);
                    Message('Schema refreshed from OData $metadata! AI now has field-level details for all published OData services.');
                end;
            }
        }
    }

    trigger OnOpenPage()
    begin
        if not Rec.Get() then begin
            Rec.Init();
            Rec."Primary Key" := '';
            Rec."Fallback to Pattern Matching" := true;
            Rec."Max Tokens" := 500;
            Rec."Azure API Version" := '2024-02-15-preview';
            Rec."API Endpoint" := 'https://func-bcvoice-v2.azurewebsites.net/api/transcribe';
            Rec.Insert();
        end else if (Rec."API Endpoint" = '' OR Rec."API Endpoint".Contains('func-bcvoice-prod')) then begin
            // Migrate from old endpoint to new v2 endpoint
            Rec."API Endpoint" := 'https://func-bcvoice-v2.azurewebsites.net/api/transcribe';
            Rec.Modify();
        end;

        UpdateVisibility();
        UpdateApiKeyStatus();

        if Rec.HasApiKey() then
            ApiKeyInput := '********'
        else
            ApiKeyInput := '';
    end;

    var
        ApiKeyInput: Text[250];
        ApiKeyStatusText: Text;
        HasApiKeyConfigured: Boolean;
        ShowOpenAI: Boolean;
        ShowAzure: Boolean;
        ShowLocalLLM: Boolean;
        ShowOnDevice: Boolean;
        OnDeviceInfoText: Label 'On-device AI uses Google Gemini Nano via Chrome''s window.ai API. This works on Chrome 127+ desktop only. On mobile devices, pattern matching is used automatically. No configuration needed here.';
        LocalLLMWarningText: Label '⚠ On-Premises Only: Local LLM requires the BC server to reach your LLM endpoint. This only works with on-premises BC installations where the server can access your local network. For BC Cloud (SaaS), use OpenAI or Azure OpenAI instead.';
        MobileNoteText: Label 'For mobile voice control, configure the Transcription Function URL above. The PWA will use this for speech-to-text conversion.';

    local procedure UpdateVisibility()
    begin
        ShowOpenAI := Rec."AI Backend Type" = Rec."AI Backend Type"::OpenAI;
        ShowAzure := Rec."AI Backend Type" = Rec."AI Backend Type"::AzureOpenAI;
        ShowLocalLLM := Rec."AI Backend Type" = Rec."AI Backend Type"::LocalLLM;
        ShowOnDevice := Rec."AI Backend Type" = Rec."AI Backend Type"::OnDeviceAI;
    end;

    local procedure UpdateApiKeyStatus()
    begin
        HasApiKeyConfigured := Rec.HasApiKey();
        if HasApiKeyConfigured then
            ApiKeyStatusText := '✓ API Key configured'
        else
            ApiKeyStatusText := '✗ No API Key';
    end;

    local procedure GetEndpointDisplay(): Text
    begin
        case Rec."AI Backend Type" of
            Rec."AI Backend Type"::OpenAI:
                exit('https://api.openai.com');
            Rec."AI Backend Type"::AzureOpenAI:
                if Rec."API Endpoint" <> '' then
                    exit(Rec."API Endpoint")
                else
                    exit('(not configured)');
            Rec."AI Backend Type"::LocalLLM:
                if Rec."API Endpoint" <> '' then
                    exit(Rec."API Endpoint")
                else
                    exit('(not configured)');
            else
                exit('');
        end;
    end;
}
