/// <summary>
/// API page for processing voice commands via HTTP endpoints.
/// Enables external applications (PWA, mobile apps) to send voice queries to Business Central.
/// </summary>
page 50613 "NXR Voice Command API"
{
    PageType = API;
    APIPublisher = 'hackathon';
    APIGroup = 'voiceAssistant';
    APIVersion = 'v1.0';
    EntityName = 'voiceCommand';
    EntitySetName = 'voiceCommands';
    SourceTable = "NXR Voice Query Intent";
    SourceTableTemporary = true;
    DelayedInsert = true;
    ODataKeyFields = "Entry No.";

    layout
    {
        area(Content)
        {
            repeater(VoiceCommands)
            {
                field(entryNo; Rec."Entry No.")
                {
                    Caption = 'Entry No.';
                }
                field(queryText; Rec."Query Text")
                {
                    Caption = 'Query Text';
                }
                field(responseText; ResponseText)
                {
                    Caption = 'Response Text';
                }
                field(structuredData; StructuredDataText)
                {
                    Caption = 'Structured Data';
                }
                field(success; Success)
                {
                    Caption = 'Success';
                }
                field(errorMessage; ErrorMessage)
                {
                    Caption = 'Error Message';
                }
            }
        }
    }

    var
        ResponseText: Text;
        StructuredDataText: Text;
        Success: Boolean;
        ErrorMessage: Text;

    trigger OnInsertRecord(BelowxRec: Boolean): Boolean
    begin
        ProcessVoiceQuery();
        exit(false); // Don't actually insert - this is a processing endpoint
    end;

    local procedure ProcessVoiceQuery()
    var
        VoiceAssistantMgt: Codeunit "NXR Voice Assistant Mgt.";
        AIService: Codeunit "NXR Voice AI Service";
        DynamicExecutor: Codeunit "NXR Voice Dynamic Query Exec.";
        GenericODataExecutor: Codeunit "NXR Generic OData Executor";
        Setup: Record "NXR Voice Assistant Setup";
        Intent: Record "NXR Voice Query Intent" temporary;
        QueryJson: JsonObject;
        ResultData: JsonObject;
        RecordCount: Integer;
        QueryText: Text;
        ExecutionMode: Text;
    begin
        QueryText := Rec."Query Text";

        if QueryText = '' then begin
            Success := false;
            ErrorMessage := 'Query text is required';
            exit;
        end;

        // Try AI-powered structured query first
        if Setup.Get() and (Setup."AI Backend Type" <> Setup."AI Backend Type"::None) then begin
            // Use AI to analyze query
            if AIService.AnalyzeQueryWithAI(QueryText, Intent) then begin
                // Use the FULL structured data from AI
                if Intent."Structured Data" <> '' then begin
                    if QueryJson.ReadFrom(Intent."Structured Data") then begin
                        // Check execution mode
                        ExecutionMode := GetJsonText(QueryJson, 'executionMode');

                        case ExecutionMode of
                            'odata':
                                begin
                                    // Use Generic OData Executor for advanced queries
                                    if GenericODataExecutor.ExecuteODataQuery(QueryJson, ResultData, RecordCount, ResponseText) then begin
                                        Success := true;
                                        StructuredDataText := Format(ResultData);
                                        exit;
                                    end;
                                end;
                            'native', '':
                                begin
                                    // Use Native Dynamic Executor for standard queries
                                    if DynamicExecutor.ExecuteStructuredQuery(QueryJson, ResultData, RecordCount, ResponseText) then begin
                                        Success := true;
                                        StructuredDataText := Format(ResultData);
                                        exit;
                                    end;
                                end;
                        end;
                    end;
                end;
            end;
        end;

        // Fallback to simple BC-native processing
        ResponseText := VoiceAssistantMgt.ProcessQuery(QueryText, '', '');
        Success := ResponseText <> '';

        if not Success then
            ErrorMessage := 'Unable to process query';

        // Sanitize response text for speech output
        if Success then
            ResponseText := SanitizeForSpeech(ResponseText);
    end;

    local procedure SanitizeForSpeech(InputText: Text): Text
    var
        CleanText: Text;
    begin
        CleanText := InputText;

        // Remove literal backslash-n sequences
        CleanText := CleanText.Replace('\n', ' ');
        CleanText := CleanText.Replace('\r', ' ');
        CleanText := CleanText.Replace('\t', ' ');

        // Remove actual line breaks and tabs
        CleanText := CleanText.Replace(Format(10), ' '); // Line Feed
        CleanText := CleanText.Replace(Format(13), ' '); // Carriage Return
        CleanText := CleanText.Replace(Format(9), ' ');  // Tab

        // Remove multiple spaces
        while CleanText.Contains('  ') do
            CleanText := CleanText.Replace('  ', ' ');

        // Trim
        CleanText := CleanText.Trim();

        exit(CleanText);
    end;

    local procedure GetJsonText(JObject: JsonObject; PropertyName: Text): Text
    var
        JToken: JsonToken;
    begin
        if JObject.Get(PropertyName, JToken) then
            if JToken.IsValue() then
                exit(JToken.AsValue().AsText());
        exit('');
    end;
}
