/// <summary>
/// Main management codeunit for processing voice queries and converting them into Business Central operations.
/// Handles query analysis, intent detection, and response formatting.
/// </summary>
codeunit 50605 "NXR Voice Assistant Mgt."
{
    var
        NewLine: Char;

    trigger OnRun()
    begin
        NewLine := 10; // Line feed character
    end;

    /// <summary>
    /// Processes a natural language query with conversation history and returns a formatted response with follow-up suggestions.
    /// </summary>
    /// <param name="QueryText">The natural language query from the user.</param>
    /// <param name="ConversationHistory">JSON array of previous messages with role/content.</param>
    /// <param name="BackendUrl">Optional Azure backend URL for advanced AI processing.</param>
    /// <param name="BCBaseUrl">Base URL of the Business Central web service.</param>
    /// <returns>A natural language response with follow-up suggestions.</returns>
    procedure ProcessQueryWithHistory(QueryText: Text; ConversationHistory: JsonArray; BackendUrl: Text; BCBaseUrl: Text): Text
    var
        Intent: Record "NXR Voice Query Intent" temporary;
        AIService: Codeunit "NXR Voice AI Service";
        ResponseText: Text;
        FollowUpText: Text;
    begin
        // First get the main response using existing logic with history
        ResponseText := ProcessQueryWithHistoryInternal(QueryText, ConversationHistory, BackendUrl, BCBaseUrl, Intent);

        // Generate follow-up suggestions based on the query and result
        FollowUpText := AIService.GenerateFollowUpSuggestions(QueryText, ResponseText, Intent."Structured Data", ConversationHistory);

        // Append follow-ups if generated
        if FollowUpText <> '' then
            ResponseText += '...' + Format(NewLine) + Format(NewLine) + FollowUpText;

        exit(ResponseText);
    end;

    local procedure ProcessQueryWithHistoryInternal(QueryText: Text; ConversationHistory: JsonArray; BackendUrl: Text; BCBaseUrl: Text; var Intent: Record "NXR Voice Query Intent" temporary): Text
    var
        AIService: Codeunit "NXR Voice AI Service";
        DynamicQueryExecutor: Codeunit "NXR Voice Dynamic Query Exec.";
        GenericODataExecutor: Codeunit "NXR Generic OData Executor";
        StructuredQueryJson: JsonObject;
        ResultData: JsonObject;
        RecordCount: Integer;
        ResponseText: Text;
        ExecutionMode: Text;
        ExecutionModeToken: JsonToken;
        Setup: Record "NXR Voice Assistant Setup";
        DebugInfo: Text;
    begin
        // DEBUG: Capture original query
        if Setup.Get() and Setup."Debug Mode" then
            DebugInfo := '[DEBUG] Original Query: "' + QueryText + '"';

        // Try AI analysis with conversation history
        if AIService.AnalyzeQueryWithHistory(QueryText, ConversationHistory, Intent) then begin
            // AI returned structured data - use it
            if Intent."Structured Data" <> '' then begin
                if StructuredQueryJson.ReadFrom(Intent."Structured Data") then begin
                    if DebugInfo <> '' then
                        DebugInfo += Format(NewLine) + '[DEBUG] AI Structured Data: ' + Intent."Structured Data";
                    // Check execution mode and route appropriately
                    if StructuredQueryJson.Get('executionMode', ExecutionModeToken) then
                        ExecutionMode := ExecutionModeToken.AsValue().AsText();

                    // Check for special intents
                    if StructuredQueryJson.Get('intent', ExecutionModeToken) then begin
                        if ExecutionModeToken.AsValue().AsText() = 'selectCompany' then begin
                            ResponseText := HandleCompanySelection(StructuredQueryJson);
                            exit(ApplyDebug(ResponseText, DebugInfo));
                        end;
                        if ExecutionModeToken.AsValue().AsText() = 'currentCompany' then begin
                            ResponseText := HandleCurrentCompanyQuery();
                            exit(ApplyDebug(ResponseText, DebugInfo));
                        end;
                        if ExecutionModeToken.AsValue().AsText() = 'unsupported' then begin
                            ResponseText := HandleUnsupportedQuery(StructuredQueryJson);
                            exit(ApplyDebug(ResponseText, DebugInfo));
                        end;
                        if ExecutionModeToken.AsValue().AsText() = 'multistep' then begin
                            ResponseText := HandleMultiStepQuery(StructuredQueryJson);
                            exit(ApplyDebug(ResponseText, DebugInfo));
                        end;
                    end;

                    case ExecutionMode of
                        'odata':
                            begin
                                // Use Generic OData Executor for advanced queries
                                if GenericODataExecutor.ExecuteODataQuery(StructuredQueryJson, ResultData, RecordCount, ResponseText) then
                                    exit(ApplyDebug(ResponseText, DebugInfo))
                                else begin
                                    // OData executor failed - return the error
                                    if ResponseText = '' then
                                        ResponseText := 'I encountered an error processing that query with OData.';
                                    exit(ApplyDebug(ResponseText, DebugInfo));
                                end;
                            end;
                        'native', '':
                            begin
                                // Use Native Dynamic Executor for standard queries
                                if DynamicQueryExecutor.ExecuteStructuredQuery(StructuredQueryJson, ResultData, RecordCount, ResponseText) then
                                    exit(ApplyDebug(ResponseText, DebugInfo))
                                else begin
                                    // Native executor failed - return error
                                    if ResponseText = '' then
                                        ResponseText := 'I encountered an error processing that query.';
                                    exit(ApplyDebug(ResponseText, DebugInfo));
                                end;
                            end;
                    end;
                end;
            end;
            // AI parsed but no structured data
            if DebugInfo <> '' then
                DebugInfo += Format(NewLine) + '[DEBUG] AI returned no structured data';

            // Check if fallback to pattern matching is enabled
            if Setup.Get() and Setup."Fallback to Pattern Matching" then begin
                if DebugInfo <> '' then
                    DebugInfo += Format(NewLine) + '[DEBUG] Falling back to pattern matching';
                exit(ExecuteQueryAndFormatResponse(Intent, QueryText));
            end else
                exit(ApplyDebug('I couldn''t analyze that query. The AI didn''t return structured data.', DebugInfo));
        end;

        // AI not available - check if fallback enabled
        if Setup.Get() and not Setup."Fallback to Pattern Matching" then
            exit('AI backend is not available. Please configure the Voice Assistant Setup.');

        // Fallback to pattern matching
        if DebugInfo <> '' then
            DebugInfo += Format(NewLine) + '[DEBUG] Using pattern matching (AI not available)';

        if not AnalyzeQueryIntent(QueryText, Intent) then
            exit(ApplyDebug('I didn''t understand that query. Try asking about customers, sales orders, or items.', DebugInfo));

        // Execute the query and return response
        exit(ExecuteQueryAndFormatResponse(Intent, QueryText));
    end;

    /// <summary>
    /// Processes a natural language query and returns a formatted response.
    /// </summary>
    /// <param name="QueryText">The natural language query from the user.</param>
    /// <param name="BackendUrl">Optional Azure backend URL for advanced AI processing.</param>
    /// <param name="BCBaseUrl">Base URL of the Business Central web service.</param>
    /// <returns>A natural language response to the user's query.</returns>
    procedure ProcessQuery(QueryText: Text; BackendUrl: Text; BCBaseUrl: Text): Text
    var
        EmptyHistory: JsonArray;
    begin
        // Delegate to new method with empty history for backward compatibility
        exit(ProcessQueryWithHistory(QueryText, EmptyHistory, BackendUrl, BCBaseUrl));
    end;

    local procedure ApplyDebug(ResponseText: Text; DebugInfo: Text): Text
    begin
        if DebugInfo <> '' then
            exit(DebugInfo + Format(NewLine) + ResponseText);
        exit(ResponseText);
    end;

    local procedure AnalyzeQueryIntent(QueryText: Text; var Intent: Record "NXR Voice Query Intent" temporary): Boolean
    var
        QueryLower: Text;
    begin
        QueryLower := LowerCase(QueryText);
        Intent.Init();
        Intent."Query Text" := QueryText;

        // Detect entity type
        if StrPos(QueryLower, 'customer') > 0 then
            Intent.Entity := Intent.Entity::Customer
        else if (StrPos(QueryLower, 'sales order') > 0) or (StrPos(QueryLower, 'order') > 0) then
            Intent.Entity := Intent.Entity::SalesOrder
        else if (StrPos(QueryLower, 'item') > 0) or (StrPos(QueryLower, 'inventory') > 0) or (StrPos(QueryLower, 'product') > 0) then
            Intent.Entity := Intent.Entity::Item
        else if (StrPos(QueryLower, 'invoice') > 0) then
            Intent.Entity := Intent.Entity::SalesInvoice
        else if (StrPos(QueryLower, 'vendor') > 0) or (StrPos(QueryLower, 'supplier') > 0) then
            Intent.Entity := Intent.Entity::Vendor
        else
            exit(false);

        // Detect filters
        if StrPos(QueryLower, 'today') > 0 then
            Intent."Date Filter" := Today
        else if StrPos(QueryLower, 'yesterday') > 0 then
            Intent."Date Filter" := Today - 1;

        // Detect time ranges
        if StrPos(QueryLower, 'this week') > 0 then
            Intent."Date Range" := Intent."Date Range"::ThisWeek
        else if StrPos(QueryLower, 'this month') > 0 then
            Intent."Date Range" := Intent."Date Range"::ThisMonth
        else if StrPos(QueryLower, 'this year') > 0 then
            Intent."Date Range" := Intent."Date Range"::ThisYear;

        // Detect top N
        Intent."Top N" := ExtractTopN(QueryLower);

        // Detect specific filters (item no, customer no, etc.)
        Intent."Specific Filter" := ExtractSpecificFilter(QueryLower);

        exit(true);
    end;

    local procedure ExtractTopN(QueryText: Text): Integer
    var
        Words: List of [Text];
        Word: Text;
        i: Integer;
        TopN: Integer;
    begin
        Words := QueryText.Split(' ');
        foreach Word in Words do begin
            i += 1;
            if (Word = 'top') and (i < Words.Count) then
                if Evaluate(TopN, Words.Get(i + 1)) then
                    exit(TopN);
        end;
        exit(0);
    end;

    local procedure ExtractSpecificFilter(QueryText: Text): Text
    var
        Words: List of [Text];
        Word: Text;
        i: Integer;
    begin
        // Extract item/customer numbers like "item 1000" or "customer 10000"
        Words := QueryText.Split(' ');
        foreach Word in Words do begin
            i += 1;
            if (Word in ['item', 'customer', 'vendor', 'invoice', 'order']) and (i < Words.Count) then
                exit(Words.Get(i + 1));
        end;
        exit('');
    end;

    local procedure ExecuteQueryAndFormatResponse(Intent: Record "NXR Voice Query Intent" temporary; OriginalQuery: Text): Text
    var
        QueryExecutor: Codeunit "NXR Voice Query Executor";
        ResultData: JsonObject;
        RecordCount: Integer;
    begin
        // Execute the query based on intent
        if not QueryExecutor.ExecuteQuery(Intent, ResultData, RecordCount) then
            exit('I encountered an error executing that query.');

        // Format the response in natural language
        exit(FormatResponse(Intent, RecordCount, ResultData));
    end;

    local procedure FormatResponse(Intent: Record "NXR Voice Query Intent" temporary; RecordCount: Integer; Data: JsonObject): Text
    var
        EntityName: Text;
        Setup: Record "NXR Voice Assistant Setup";
        DebugPrefix: Text;
        RecordNo: Text;
    begin
        if Setup.Get() and Setup."Debug Mode" then
            DebugPrefix := '[DEBUG] FormatResponse called - RecordCount=' + Format(RecordCount) + ', Entity=' + Format(Intent.Entity) + ', TopN=' + Format(Intent."Top N") + Format(NewLine);
        if RecordCount = 0 then
            exit(DebugPrefix + 'I couldn''t find any matching records.');

        EntityName := Format(Intent.Entity);

        if RecordCount = 1 then begin
            if TryGetSingleRecordNo(Data, Intent.Entity, RecordNo) then
                exit(DebugPrefix + StrSubstNo('%1 %2.', EntityName, RecordNo));
            exit(DebugPrefix + StrSubstNo('I found 1 %1.', EntityName));
        end else if Intent."Top N" > 0 then
                exit(DebugPrefix + StrSubstNo('Here are the top %1 %2s.', Intent."Top N", EntityName))
        else
            exit(DebugPrefix + StrSubstNo('I found %1 %2s.', RecordCount, EntityName));
    end;

    local procedure TryGetSingleRecordNo(Data: JsonObject; Entity: Enum "NXR Voice Entity Type"; var RecordNo: Text): Boolean
    begin
        case Entity of
            Entity::SalesOrder:
                exit(TryGetFirstArrayField(Data, 'salesOrders', 'no', RecordNo));
            Entity::SalesInvoice:
                exit(TryGetFirstArrayField(Data, 'salesInvoices', 'no', RecordNo));
            Entity::PurchaseOrder:
                exit(TryGetFirstArrayField(Data, 'purchaseOrders', 'no', RecordNo));
            Entity::PurchaseInvoice:
                exit(TryGetFirstArrayField(Data, 'purchaseInvoices', 'no', RecordNo));
        end;
        exit(false);
    end;

    local procedure TryGetFirstArrayField(Data: JsonObject; ArrayName: Text; FieldName: Text; var FieldValue: Text): Boolean
    var
        Token: JsonToken;
        Arr: JsonArray;
        ItemToken: JsonToken;
        Obj: JsonObject;
        FieldToken: JsonToken;
    begin
        if not Data.Get(ArrayName, Token) then
            exit(false);

        if not Token.IsArray() then
            exit(false);

        Arr := Token.AsArray();
        if Arr.Count() = 0 then
            exit(false);

        Arr.Get(0, ItemToken);
        Obj := ItemToken.AsObject();
        if not Obj.Get(FieldName, FieldToken) then
            exit(false);

        FieldValue := FieldToken.AsValue().AsText();
        exit(FieldValue <> '');
    end;

    local procedure HandleCompanySelection(QueryJson: JsonObject): Text
    var
        GenericODataExecutor: Codeunit "NXR Generic OData Executor";
        CompanyNameToken: JsonToken;
        PartialCompanyName: Text;
        MatchedCompanyName: Text;
        AvailableCompanies: JsonArray;
        CompanyJson: JsonObject;
        CompanyToken: JsonToken;
        CompanyList: Text;
        i: Integer;
    begin
        // Extract company name from query
        if not QueryJson.Get('companyName', CompanyNameToken) then
            exit('I didn''t catch which company you want to work with. Please try again.');

        PartialCompanyName := CompanyNameToken.AsValue().AsText();

        // Try to match the company
        if GenericODataExecutor.SelectCompanyByName(PartialCompanyName, MatchedCompanyName) then
            exit(StrSubstNo('Switched to company "%1". All future queries will use this company.', MatchedCompanyName))
        else begin
            // No match found - list available companies
            if GenericODataExecutor.GetAvailableCompanies(AvailableCompanies) then begin
                CompanyList := '';
                for i := 0 to AvailableCompanies.Count() - 1 do begin
                    AvailableCompanies.Get(i, CompanyToken);
                    if CompanyToken.IsObject() then begin
                        CompanyJson := CompanyToken.AsObject();
                        if CompanyList <> '' then
                            CompanyList += ', ';
                        CompanyList += GetJsonText(CompanyJson, 'name');
                    end;
                end;
                exit(StrSubstNo('I couldn''t find a company matching "%1". Available companies: %2', PartialCompanyName, CompanyList));
            end else
                exit('I couldn''t find any companies in the system.');
        end;
    end;

    local procedure HandleCurrentCompanyQuery(): Text
    var
        GenericODataExecutor: Codeunit "NXR Generic OData Executor";
        SelectedCompany: Text;
    begin
        SelectedCompany := GenericODataExecutor.GetSelectedCompanyName();
        if SelectedCompany <> '' then
            exit(StrSubstNo('You are currently working in company "%1".', SelectedCompany))
        else
            exit(StrSubstNo('You are currently working in company "%1" (the default company).', CompanyName()));
    end;

    local procedure HandleUnsupportedQuery(QueryJson: JsonObject): Text
    var
        MessageToken: JsonToken;
        Message: Text;
    begin
        if QueryJson.Get('message', MessageToken) then
            Message := MessageToken.AsValue().AsText();

        if Message <> '' then
            exit(Message)
        else
            exit('This type of query is not yet supported. Try asking for specific records, counts, or top/biggest queries.');
    end;

    local procedure HandleMultiStepQuery(QueryJson: JsonObject): Text
    var
        DynamicQueryExecutor: Codeunit "NXR Voice Dynamic Query Exec.";
        Step1Token: JsonToken;
        Step1Query: JsonObject;
        GuidanceToken: JsonToken;
        GuidanceTemplate: Text;
        ReasonToken: JsonToken;
        Reason: Text;
        ResultData: JsonObject;
        RecordCount: Integer;
        Step1Response: Text;
        FinalResponse: Text;
        SuggestedQuery: Text;
    begin
        // Get the first step query
        if not QueryJson.Get('step1Query', Step1Token) then
            exit('I understand this requires multiple steps, but I couldn''t determine the first step.');

        if not Step1Token.IsObject() then
            exit('Invalid multi-step query format.');

        Step1Query := Step1Token.AsObject();

        // Execute step 1
        if not DynamicQueryExecutor.ExecuteStructuredQuery(Step1Query, ResultData, RecordCount, Step1Response) then
            exit('I tried to start your multi-step query but encountered an error: ' + Step1Response);

        // Get guidance template and reason
        if QueryJson.Get('guidanceTemplate', GuidanceToken) then
            GuidanceTemplate := GuidanceToken.AsValue().AsText();

        if QueryJson.Get('reason', ReasonToken) then
            Reason := ReasonToken.AsValue().AsText();

        // Format the response with actual data
        SuggestedQuery := FormatGuidanceWithData(GuidanceTemplate, ResultData);

        // Build final response
        FinalResponse := Step1Response;
        if Reason <> '' then
            FinalResponse += Format(NewLine) + Format(NewLine) + '📍 ' + Reason;
        if SuggestedQuery <> '' then
            FinalResponse += Format(NewLine) + Format(NewLine) + '💡 Next step: ' + SuggestedQuery;

        exit(FinalResponse);
    end;

    local procedure FormatGuidanceWithData(Template: Text; ResultData: JsonObject): Text
    var
        FormattedText: Text;
        EntityToken: JsonToken;
        EntityKeys: List of [Text];
        EntityKey: Text;
    begin
        FormattedText := Template;

        // Generic processing: loop through all arrays in ResultData
        // Process common entity types: items, customers, vendors, employees, locations, etc.
        EntityKeys := ResultData.Keys();
        foreach EntityKey in EntityKeys do begin
            if ResultData.Get(EntityKey, EntityToken) then begin
                if EntityToken.IsArray() then
                    FormattedText := ProcessEntityArray(FormattedText, EntityKey, EntityToken.AsArray());
            end;
        end;

        exit(FormattedText);
    end;

    local procedure ProcessEntityArray(Template: Text; EntityName: Text; EntityArray: JsonArray): Text
    var
        FormattedText: Text;
        FirstRecord: JsonObject;
        FirstToken: JsonToken;
        FieldMappings: Dictionary of [Text, Text];
    begin
        FormattedText := Template;

        // Define common field mappings for each entity type
        FieldMappings := GetFieldMappings(EntityName);

        // Replace first record fields (e.g., {itemNo}, {customerName})
        if EntityArray.Count > 0 then begin
            EntityArray.Get(0, FirstToken);
            if FirstToken.IsObject() then begin
                FirstRecord := FirstToken.AsObject();
                FormattedText := ReplaceFirstRecordFields(FormattedText, EntityName, FirstRecord, FieldMappings);
            end;
        end;

        // Replace list fields (e.g., {locationCities}, {vendorNames})
        FormattedText := ReplaceListFields(FormattedText, EntityName, EntityArray, FieldMappings);

        exit(FormattedText);
    end;

    local procedure GetFieldMappings(EntityName: Text): Dictionary of [Text, Text]
    var
        Mappings: Dictionary of [Text, Text];
    begin
        // Map singular entity names to their common fields
        // Format: placeholderSuffix -> jsonFieldName
        case EntityName of
            'items':
                begin
                    Mappings.Add('No', 'no');
                    Mappings.Add('Description', 'description');
                    Mappings.Add('UnitPrice', 'unitPrice');
                end;
            'customers':
                begin
                    Mappings.Add('No', 'no');
                    Mappings.Add('Name', 'name');
                    Mappings.Add('City', 'city');
                    Mappings.Add('Balance', 'balance');
                end;
            'vendors':
                begin
                    Mappings.Add('No', 'no');
                    Mappings.Add('Name', 'name');
                    Mappings.Add('City', 'city');
                end;
            'employees':
                begin
                    Mappings.Add('No', 'no');
                    Mappings.Add('FirstName', 'firstName');
                    Mappings.Add('LastName', 'lastName');
                    Mappings.Add('JobTitle', 'jobTitle');
                end;
            'locations':
                begin
                    Mappings.Add('Code', 'code');
                    Mappings.Add('Name', 'name');
                    Mappings.Add('City', 'city');
                end;
        end;
        exit(Mappings);
    end;

    local procedure ReplaceFirstRecordFields(Template: Text; EntityName: Text; FirstRecord: JsonObject; FieldMappings: Dictionary of [Text, Text]): Text
    var
        FormattedText: Text;
        PlaceholderSuffix: Text;
        FieldName: Text;
        EntityPrefix: Text;
        AllFieldKeys: List of [Text];
        FieldKey: Text;
    begin
        FormattedText := Template;
        EntityPrefix := GetEntityPrefix(EntityName);

        // First, replace using predefined friendly mappings: e.g., {itemNo} for 'no' field
        foreach PlaceholderSuffix in FieldMappings.Keys() do begin
            FieldName := FieldMappings.Get(PlaceholderSuffix);
            FormattedText := ReplaceJsonPlaceholder(FormattedText, EntityPrefix + PlaceholderSuffix, FirstRecord, FieldName);
        end;

        // Second, replace ALL fields from the JSON directly: e.g., {itemQuantity}, {itemUnitPrice}, {itemValue}
        // This allows AI to reference any field without us hardcoding it
        AllFieldKeys := FirstRecord.Keys();
        foreach FieldKey in AllFieldKeys do begin
            // Convert field name to placeholder format: 'unitPrice' -> 'UnitPrice'
            PlaceholderSuffix := ToPascalCase(FieldKey);
            FormattedText := ReplaceJsonPlaceholder(FormattedText, EntityPrefix + PlaceholderSuffix, FirstRecord, FieldKey);
        end;

        exit(FormattedText);
    end;

    local procedure ReplaceListFields(Template: Text; EntityName: Text; EntityArray: JsonArray; FieldMappings: Dictionary of [Text, Text]): Text
    var
        FormattedText: Text;
        PlaceholderSuffix: Text;
        FieldName: Text;
        EntityPrefix: Text;
        FirstToken: JsonToken;
        FirstRecord: JsonObject;
        AllFieldKeys: List of [Text];
        FieldKey: Text;
    begin
        FormattedText := Template;
        EntityPrefix := GetEntityPrefix(EntityName);

        // First, replace using predefined friendly mappings: e.g., {locationCities}
        foreach PlaceholderSuffix in FieldMappings.Keys() do begin
            FieldName := FieldMappings.Get(PlaceholderSuffix);
            // Pluralize the placeholder: {locationCities} not {locationCity}
            FormattedText := ReplaceWithListPlaceholder(FormattedText, EntityPrefix + PlaceholderSuffix + 's', EntityArray, FieldName);
        end;

        // Second, replace ALL fields from the JSON directly: e.g., {itemQuantitys}, {itemUnitPrices}
        // Get field names from first record
        if EntityArray.Count > 0 then begin
            EntityArray.Get(0, FirstToken);
            if FirstToken.IsObject() then begin
                FirstRecord := FirstToken.AsObject();
                AllFieldKeys := FirstRecord.Keys();
                foreach FieldKey in AllFieldKeys do begin
                    PlaceholderSuffix := ToPascalCase(FieldKey);
                    FormattedText := ReplaceWithListPlaceholder(FormattedText, EntityPrefix + PlaceholderSuffix + 's', EntityArray, FieldKey);
                end;
            end;
        end;

        exit(FormattedText);
    end;

    local procedure GetEntityPrefix(EntityName: Text): Text
    begin
        // Convert plural entity name to singular prefix for placeholders
        // "items" -> "item", "customers" -> "customer", "locations" -> "location"
        case EntityName of
            'items':
                exit('item');
            'customers':
                exit('customer');
            'vendors':
                exit('vendor');
            'employees':
                exit('employee');
            'locations':
                exit('location');
        end;
        exit(EntityName); // fallback to original name
    end;

    local procedure ReplaceJsonPlaceholder(Template: Text; PlaceholderName: Text; DataObject: JsonObject; FieldName: Text): Text
    var
        FieldToken: JsonToken;
        FieldValue: Text;
    begin
        if DataObject.Get(FieldName, FieldToken) then begin
            FieldValue := FieldToken.AsValue().AsText();
            exit(Template.Replace('{' + PlaceholderName + '}', FieldValue));
        end;
        exit(Template);
    end;

    local procedure ReplaceWithListPlaceholder(Template: Text; PlaceholderName: Text; DataArray: JsonArray; FieldName: Text): Text
    var
        ItemToken: JsonToken;
        ItemObject: JsonObject;
        FieldToken: JsonToken;
        ValuesList: Text;
        i: Integer;
    begin
        ValuesList := '';
        for i := 0 to DataArray.Count - 1 do begin
            DataArray.Get(i, ItemToken);
            if ItemToken.IsObject() then begin
                ItemObject := ItemToken.AsObject();
                if ItemObject.Get(FieldName, FieldToken) then begin
                    if ValuesList <> '' then
                        ValuesList += ', ';
                    ValuesList += FieldToken.AsValue().AsText();
                end;
            end;
        end;
        exit(Template.Replace('{' + PlaceholderName + '}', ValuesList));
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

    local procedure ToPascalCase(FieldName: Text): Text
    var
        Result: Text;
        i: Integer;
        Char: Char;
        NextCharUppercase: Boolean;
    begin
        Result := '';
        NextCharUppercase := true;
        for i := 1 to StrLen(FieldName) do begin
            Char := FieldName[i];
            if Char = '_' then
                NextCharUppercase := true
            else begin
                if NextCharUppercase then begin
                    Result += UpperCase(CopyStr(FieldName, i, 1));
                    NextCharUppercase := false;
                end else
                    Result += CopyStr(FieldName, i, 1);
            end;
        end;
        exit(Result);
    end;
}
