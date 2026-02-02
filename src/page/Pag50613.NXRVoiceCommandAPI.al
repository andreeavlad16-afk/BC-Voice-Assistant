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

        // Remove ALL forms of newlines and escape sequences
        CleanText := CleanText.Replace('\n', ' ');
        CleanText := CleanText.Replace('\r', ' ');
        CleanText := CleanText.Replace('\t', ' ');
        CleanText := CleanText.Replace('\\n', ' ');
        CleanText := CleanText.Replace('\\r', ' ');
        CleanText := CleanText.Replace('\\t', ' ');
        CleanText := CleanText.Replace('/n', ' ');
        CleanText := CleanText.Replace(Format(10), ' '); // Line Feed
        CleanText := CleanText.Replace(Format(13), ' '); // Carriage Return
        CleanText := CleanText.Replace(Format(9), ' ');  // Tab

        // Remove any stray patterns that might be read as "point 10" or similar
        CleanText := CleanText.Replace('.10', ' ');
        CleanText := CleanText.Replace('.13', ' ');
        CleanText := CleanText.Replace('.9', ' ');
        CleanText := CleanText.Replace(' 10 ', ' ');
        CleanText := CleanText.Replace(' 13 ', ' ');
        CleanText := CleanText.Replace(' 9 ', ' ');

        // Format order numbers with prefix
        CleanText := FormatOrderNumbers(CleanText);

        // Format identifiers (customer numbers, order numbers, etc.) to read digit by digit
        CleanText := FormatIdentifierNumbers(CleanText);

        // Format currency values
        CleanText := FormatCurrencyValues(CleanText);

        // Replace periods with commas for natural pauses (except end of text)
        CleanText := CleanText.Replace('. ', ', ');
        // Remove trailing period if present
        if CleanText.EndsWith('.') then
            CleanText := CopyStr(CleanText, 1, StrLen(CleanText) - 1);

        // Remove multiple spaces
        while CleanText.Contains('  ') do
            CleanText := CleanText.Replace('  ', ' ');

        CleanText := CleanText.Trim();
        exit(CleanText);
    end;

    local procedure FormatIdentifierNumbers(InputText: Text): Text
    var
        Result: Text;
        i: Integer;
        j: Integer;
        InNumber: Boolean;
        NumberStart: Integer;
        Number: Text;
        SpacedNumber: Text;
        Prefix: Text;
    begin
        Result := InputText;

        // Pattern: "reference 101004" or "number 101004" or just "101004" after certain keywords
        // Space out 4+ digit numbers that appear after keywords or standalone
        i := 1;
        while i <= StrLen(Result) do begin
            // Check for number patterns after keywords
            if (i > 10) and (Result[i] in ['0' .. '9']) then begin
                // Check if preceded by "reference ", "number ", "order ", "customer "
                if i >= 10 then
                    Prefix := CopyStr(Result, i - 10, 10)
                else
                    Prefix := CopyStr(Result, 1, i);
                if (Prefix.Contains('reference ')) or (Prefix.Contains('number ')) or
                   (Prefix.Contains('order ')) or (Prefix.Contains('customer ')) then begin
                    NumberStart := i;
                    j := i;
                    Number := '';

                    // Collect the full number (including hyphens)
                    while (j <= StrLen(Result)) and (Result[j] in ['0' .. '9', '-']) do begin
                        Number += Format(Result[j]);
                        j += 1;
                    end;

                    // If it's 4+ digits, space them out
                    if StrLen(Number.Replace('-', '')) >= 4 then begin
                        SpacedNumber := '';
                        for j := 1 to StrLen(Number) do begin
                            SpacedNumber += Format(Result[NumberStart + j - 1]);
                            if j < StrLen(Number) then
                                SpacedNumber += ' ';
                        end;

                        Result := CopyStr(Result, 1, NumberStart - 1) + SpacedNumber + CopyStr(Result, NumberStart + StrLen(Number));
                        i := NumberStart + StrLen(SpacedNumber);
                    end else
                        i := j;
                end else
                    i += 1;
            end else
                i += 1;
        end;

        exit(Result);
    end;

    local procedure FormatOrderNumbers(InputText: Text): Text
    var
        Result: Text;
    begin
        Result := InputText;
        // Add "order number" prefix when we see SO followed by numbers
        Result := Result.Replace('SO-', 'order number SO-');
        Result := Result.Replace('SO', 'order number SO');
        exit(Result);
    end;

    local procedure FormatCurrencyValues(InputText: Text): Text
    var
        Result: Text;
        i: Integer;
        CurrencyPos: Integer;
        NumberStart: Integer;
        NumberEnd: Integer;
        Number: Text;
        CurrencyText: Text;
    begin
        Result := InputText;

        // Handle $123.45 format - move $ to after the number
        i := 1;
        while i <= StrLen(Result) do begin
            if Result[i] in ['$', '£', '€'] then begin
                CurrencyPos := i;
                NumberStart := i + 1;
                NumberEnd := NumberStart;

                // Find end of number (digits, comma, period)
                while (NumberEnd <= StrLen(Result)) and
                      (Result[NumberEnd] in ['0' .. '9', ',', '.']) do
                    NumberEnd += 1;

                if NumberEnd > NumberStart then begin
                    Number := CopyStr(Result, NumberStart, NumberEnd - NumberStart);

                    case Result[CurrencyPos] of
                        '$':
                            CurrencyText := ' dollars';
                        '£':
                            CurrencyText := ' pounds';
                        '€':
                            CurrencyText := ' euros';
                    end;

                    // Replace "$123.45" with "123.45 dollars"
                    Result := CopyStr(Result, 1, CurrencyPos - 1) + Number + CurrencyText + CopyStr(Result, NumberEnd);
                    i := CurrencyPos + StrLen(Number) + StrLen(CurrencyText);
                end else
                    i += 1;
            end else
                i += 1;
        end;

        exit(Result);
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
