/// <summary>
/// Main management codeunit for processing voice queries and converting them into Business Central operations.
/// Handles query analysis, intent detection, and response formatting.
/// </summary>
codeunit 50605 "NXR Voice Assistant Mgt."
{
    /// <summary>
    /// Processes a natural language query and returns a formatted response.
    /// </summary>
    /// <param name="QueryText">The natural language query from the user.</param>
    /// <param name="BackendUrl">Optional Azure backend URL for advanced AI processing.</param>
    /// <param name="BCBaseUrl">Base URL of the Business Central web service.</param>
    /// <returns>A natural language response to the user's query.</returns>
    procedure ProcessQuery(QueryText: Text; BackendUrl: Text; BCBaseUrl: Text): Text
    var
        Intent: Record "NXR Voice Query Intent" temporary;
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
            DebugInfo := '\\\\[DEBUG] Original Query: "' + QueryText + '"';

        // Try AI analysis first if configured
        if AIService.AnalyzeQueryWithAI(QueryText, Intent) then begin
            // AI returned structured data - use it
            if Intent."Structured Data" <> '' then begin
                if Setup.Get() and Setup."Debug Mode" then
                    DebugInfo += '\\[DEBUG] AI Structured Response: ' + Intent."Structured Data";

                if StructuredQueryJson.ReadFrom(Intent."Structured Data") then begin
                    // Check execution mode and route appropriately
                    if StructuredQueryJson.Get('executionMode', ExecutionModeToken) then
                        ExecutionMode := ExecutionModeToken.AsValue().AsText();

                    // Check for special intents
                    if StructuredQueryJson.Get('intent', ExecutionModeToken) then begin
                        if ExecutionModeToken.AsValue().AsText() = 'selectCompany' then begin
                            ResponseText := HandleCompanySelection(StructuredQueryJson);
                            if Setup.Get() and Setup."Debug Mode" then
                                ResponseText := DebugInfo + '\\' + ResponseText;
                            exit(ResponseText);
                        end;
                        if ExecutionModeToken.AsValue().AsText() = 'currentCompany' then begin
                            ResponseText := HandleCurrentCompanyQuery();
                            if Setup.Get() and Setup."Debug Mode" then
                                ResponseText := DebugInfo + '\\' + ResponseText;
                            exit(ResponseText);
                        end;
                    end;

                    if Setup.Get() and Setup."Debug Mode" then
                        DebugInfo += '\\[DEBUG] Execution Mode: ' + ExecutionMode;

                    case ExecutionMode of
                        'odata':
                            begin
                                // Use Generic OData Executor for advanced queries
                                if GenericODataExecutor.ExecuteODataQuery(StructuredQueryJson, ResultData, RecordCount, ResponseText) then begin
                                    if Setup.Get() and Setup."Debug Mode" then
                                        ResponseText := DebugInfo + '\\' + ResponseText;
                                    exit(ResponseText);
                                end else begin
                                    // OData executor failed - return the error instead of falling through
                                    if Setup.Get() and Setup."Debug Mode" then
                                        ResponseText := DebugInfo + '\\[DEBUG] OData executor failed\\' + ResponseText
                                    else if ResponseText = '' then
                                        ResponseText := 'I encountered an error processing that query with OData.';
                                    exit(ResponseText);
                                end;
                            end;
                        'native', '':
                            begin
                                // Use Native Dynamic Executor for standard queries
                                if DynamicQueryExecutor.ExecuteStructuredQuery(StructuredQueryJson, ResultData, RecordCount, ResponseText) then begin
                                    // Prepend upstream debug info
                                    if Setup.Get() and Setup."Debug Mode" then
                                        ResponseText := DebugInfo + ResponseText;
                                    exit(ResponseText);
                                end else begin
                                    // Native executor failed - return error
                                    if Setup.Get() and Setup."Debug Mode" then
                                        ResponseText := DebugInfo + '\\[DEBUG] Native executor failed\\' + ResponseText
                                    else if ResponseText = '' then
                                        ResponseText := 'I encountered an error processing that query.';
                                    exit(ResponseText);
                                end;
                            end;
                    end;
                end;
            end;
            // AI parsed but no structured data - use legacy executor
            if Setup.Get() and Setup."Debug Mode" then begin
                DebugInfo += '\\[DEBUG] AI returned no structured data - using legacy path';
                ResponseText := ExecuteQueryAndFormatResponse(Intent, QueryText);
                ResponseText := DebugInfo + ResponseText;
                exit(ResponseText);
            end else
                exit(ExecuteQueryAndFormatResponse(Intent, QueryText));
        end;

        // Fallback to pattern matching if AI not available
        if Setup.Get() and Setup."Debug Mode" then
            DebugInfo += '\\[DEBUG] AI not available - using pattern matching';

        if not AnalyzeQueryIntent(QueryText, Intent) then begin
            if Setup.Get() and Setup."Debug Mode" then
                exit(DebugInfo + '\\I didn''t understand that query. Try asking about customers, sales orders, or items.');
            exit('I didn''t understand that query. Try asking about customers, sales orders, or items.');
        end;

        // Execute the query and return response
        if Setup.Get() and Setup."Debug Mode" then begin
            ResponseText := ExecuteQueryAndFormatResponse(Intent, QueryText);
            ResponseText := DebugInfo + ResponseText;
            exit(ResponseText);
        end else
            exit(ExecuteQueryAndFormatResponse(Intent, QueryText));
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
    begin
        if Setup.Get() and Setup."Debug Mode" then
            DebugPrefix := '[DEBUG] FormatResponse called - RecordCount=' + Format(RecordCount) + ', Entity=' + Format(Intent.Entity) + ', TopN=' + Format(Intent."Top N") + '\\\n';

        if RecordCount = 0 then
            exit(DebugPrefix + 'I couldn''t find any matching records.');

        EntityName := Format(Intent.Entity);

        if RecordCount = 1 then
            exit(DebugPrefix + StrSubstNo('I found 1 %1.', EntityName))
        else if Intent."Top N" > 0 then
            exit(DebugPrefix + StrSubstNo('Here are the top %1 %2s.', Intent."Top N", EntityName))
        else
            exit(DebugPrefix + StrSubstNo('I found %1 %2s.', RecordCount, EntityName));
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