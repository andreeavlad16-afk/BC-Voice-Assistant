/// <summary>
/// API page for managing Voice Assistant Setup configuration via OData/REST.
/// Enables external tools and scripts to update configuration programmatically.
/// </summary>
page 50614 "NXR Voice Setup API"
{
    PageType = API;
    APIPublisher = 'hackathon';
    APIGroup = 'voiceAssistant';
    APIVersion = 'v1.0';
    EntityName = 'voiceAssistantSetup';
    EntitySetName = 'voiceAssistantSetups';
    SourceTable = "NXR Voice Assistant Setup";
    DelayedInsert = true;
    ODataKeyFields = "Primary Key";
    Extensible = false;

    layout
    {
        area(Content)
        {
            repeater(Setup)
            {
                field(primaryKey; Rec."Primary Key")
                {
                    Caption = 'Primary Key';
                }
                field(aiBackendType; Rec."AI Backend Type")
                {
                    Caption = 'AI Backend Type';
                }
                field(apiEndpoint; Rec."API Endpoint")
                {
                    Caption = 'API Endpoint';
                }
                field(modelName; Rec."Model Name")
                {
                    Caption = 'Model Name';
                }
                field(azureDeploymentName; Rec."Azure Deployment Name")
                {
                    Caption = 'Azure Deployment Name';
                }
                field(azureAPIVersion; Rec."Azure API Version")
                {
                    Caption = 'Azure API Version';
                }
                field(fallbackToPatternMatching; Rec."Fallback to Pattern Matching")
                {
                    Caption = 'Fallback to Pattern Matching';
                }
                field(maxTokens; Rec."Max Tokens")
                {
                    Caption = 'Max Tokens';
                }
                field(transcriptionProxyURL; Rec."Transcription Proxy URL")
                {
                    Caption = 'Transcription Proxy URL';
                }
                field(bcODataBaseURL; Rec."BC OData Base URL")
                {
                    Caption = 'BC OData Base URL';
                }
                field(debugMode; Rec."Debug Mode")
                {
                    Caption = 'Debug Mode';
                }
                field(textOnlyMode; Rec."Text Only Mode")
                {
                    Caption = 'Text Only Mode';
                }
            }
        }
    }

    // Note: API Key is NOT exposed via API for security reasons
    // Use the BC web client to set the API key securely
}
