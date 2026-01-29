/// <summary>
/// Generic OData Query Executor for Business Central APIs.
/// Executes any OData query against BC's REST APIs without entity-specific code.
/// Supports aggregations, complex filters, joins, and grouping.
/// </summary>
codeunit 50614 "NXR Generic OData Executor"
{
    var
        Setup: Record "NXR Voice Assistant Setup";
        SelectedCompanyName: Text[100];
        SelectedCompanyGuid: Text;

    /// <summary>
    /// Executes a generic OData query and returns results.
    /// </summary>
    /// <param name="ODataQueryJson">JSON containing: entity, query, resultType, responseTemplate</param>
    /// <param name="ResultData">JSON object containing the query results</param>
    /// <param name="RecordCount">Number of records returned</param>
    /// <param name="ResponseText">Natural language response text</param>
    /// <returns>True if execution succeeded</returns>
    procedure ExecuteODataQuery(ODataQueryJson: JsonObject; var ResultData: JsonObject; var RecordCount: Integer; var ResponseText: Text): Boolean
    var
        Client: HttpClient;
        Response: HttpResponseMessage;
        ODataObj: JsonToken;
        EntityPath: Text;
        QueryString: Text;
        ResultType: Text;
        ResponseTemplate: Text;
        FullUrl: Text;
        ResponseContent: Text;
        ResponseJson: JsonObject;
        Setup: Record "NXR Voice Assistant Setup";
        DebugInfo: Text;
    begin
        // Debug: Show we entered OData executor
        if Setup.Get() and Setup."Debug Mode" then
            DebugInfo := '\\[DEBUG-ODATA] ExecuteODataQuery called';

        // Extract OData query components
        if not ODataQueryJson.Get('odata', ODataObj) then begin
            if Setup.Get() and Setup."Debug Mode" then
                ResponseText := DebugInfo + '\\[DEBUG-ODATA] No odata object in JSON. JSON keys present: ' + GetJsonKeys(ODataQueryJson);
            exit(false);
        end;

        if not ODataObj.IsObject() then begin
            if Setup.Get() and Setup."Debug Mode" then
                ResponseText := DebugInfo + '\[DEBUG-ODATA] odata is not an object';
            exit(false);
        end;

        EntityPath := GetJsonText(ODataObj.AsObject(), 'entity');
        QueryString := GetJsonText(ODataObj.AsObject(), 'query');
        ResultType := GetJsonText(ODataObj.AsObject(), 'resultType');
        ResponseTemplate := GetJsonText(ODataQueryJson, 'responseTemplate');

        if Setup.Get() and Setup."Debug Mode" then begin
            DebugInfo += '\[DEBUG-ODATA] Entity=' + EntityPath;
            DebugInfo += '\[DEBUG-ODATA] Query=' + QueryString;
            DebugInfo += '\[DEBUG-ODATA] ResultType=' + ResultType;
        end;

        if EntityPath = '' then begin
            if Setup.Get() and Setup."Debug Mode" then
                ResponseText := DebugInfo + '\[DEBUG-ODATA] EntityPath is empty';
            exit(false);
        end;

        // Build complete OData URL
        FullUrl := BuildODataUrl(EntityPath, QueryString);

        if Setup.Get() and Setup."Debug Mode" then
            DebugInfo += '\[DEBUG-ODATA] URL=' + FullUrl;

        // Add authentication headers
        AddAuthHeaders(Client);

        // Execute HTTP GET
        if not Client.Get(FullUrl, Response) then begin
            if Setup.Get() and Setup."Debug Mode" then
                ResponseText := DebugInfo + '\[DEBUG-ODATA] HTTP GET failed'
            else
                ResponseText := 'Failed to connect to Business Central API.';
            exit(false);
        end;

        if not Response.IsSuccessStatusCode() then begin
            // Note: Field correction would require refactoring to work with JsonObject signature
            // For now, we show detailed error with field discovery guidance
            if Setup.Get() and Setup."Debug Mode" then
                ResponseText := DebugInfo + '\[DEBUG-ODATA] HTTP Status: ' + Format(Response.HttpStatusCode()) + ' - ' + FormatErrorResponse(Response)
            else
                ResponseText := FormatErrorResponse(Response);
            exit(false);
        end;

        // Parse response
        Response.Content().ReadAs(ResponseContent);
        if Setup.Get() and Setup."Debug Mode" then
            DebugInfo += '\[DEBUG-ODATA] Response length: ' + Format(StrLen(ResponseContent));

        if not ResponseJson.ReadFrom(ResponseContent) then begin
            if Setup.Get() and Setup."Debug Mode" then
                ResponseText := DebugInfo + '\[DEBUG-ODATA] Failed to parse JSON response'
            else
                ResponseText := 'Failed to parse Business Central response.';
            exit(false);
        end;

        // Process based on result type
        case ResultType of
            'count':
                begin
                    if not ProcessCountResult(ResponseJson, ResultData, RecordCount, ResponseText, ResponseTemplate) then begin
                        if Setup.Get() and Setup."Debug Mode" then
                            ResponseText := DebugInfo + '\[DEBUG-ODATA] ProcessCountResult failed - ' + ResponseText;
                        exit(false);
                    end;
                    if Setup.Get() and Setup."Debug Mode" then
                        ResponseText := DebugInfo + '\' + ResponseText;
                    exit(true);
                end;
            'array':
                begin
                    if not ProcessArrayResult(ResponseJson, ResultData, RecordCount, ResponseText, ResponseTemplate) then begin
                        if Setup.Get() and Setup."Debug Mode" then
                            ResponseText := DebugInfo + '\[DEBUG-ODATA] ProcessArrayResult failed - ' + ResponseText;
                        exit(false);
                    end;
                    if Setup.Get() and Setup."Debug Mode" then
                        ResponseText := DebugInfo + '\' + ResponseText;
                    exit(true);
                end;
            'aggregation':
                begin
                    if not ProcessAggregationResult(ResponseJson, ResultData, RecordCount, ResponseText, ResponseTemplate) then begin
                        if Setup.Get() and Setup."Debug Mode" then
                            ResponseText := DebugInfo + '\[DEBUG-ODATA] ProcessAggregationResult failed - ' + ResponseText;
                        exit(false);
                    end;
                    if Setup.Get() and Setup."Debug Mode" then
                        ResponseText := DebugInfo + '\' + ResponseText;
                    exit(true);
                end;
            'single':
                begin
                    if not ProcessSingleResult(ResponseJson, ResultData, RecordCount, ResponseText, ResponseTemplate) then begin
                        if Setup.Get() and Setup."Debug Mode" then
                            ResponseText := DebugInfo + '\[DEBUG-ODATA] ProcessSingleResult failed - ' + ResponseText;
                        exit(false);
                    end;
                    if Setup.Get() and Setup."Debug Mode" then
                        ResponseText := DebugInfo + '\' + ResponseText;
                    exit(true);
                end;
            else begin
                if Setup.Get() and Setup."Debug Mode" then
                    ResponseText := DebugInfo + '\[DEBUG-ODATA] Default to ProcessArrayResult';
                if not ProcessArrayResult(ResponseJson, ResultData, RecordCount, ResponseText, ResponseTemplate) then begin
                    if Setup.Get() and Setup."Debug Mode" then
                        ResponseText := DebugInfo + '\[DEBUG-ODATA] ProcessArrayResult failed - ' + ResponseText;
                    exit(false);
                end;
                if Setup.Get() and Setup."Debug Mode" then
                    ResponseText := DebugInfo + '\' + ResponseText;
                exit(true);
            end;
        end;
    end;

    local procedure BuildODataUrl(EntityPath: Text; QueryString: Text): Text
    var
        BaseUrl: Text;
        CompanyPath: Text;
    begin
        // Load setup
        if not Setup.Get() then begin
            // Default to current environment
            BaseUrl := GetUrl(ClientType::Web);
            if not BaseUrl.EndsWith('/') then
                BaseUrl += '/';
            BaseUrl += 'api/v2.0/';
        end else begin
            BaseUrl := Setup."BC OData Base URL";
            if BaseUrl = '' then begin
                BaseUrl := GetUrl(ClientType::Web);
                if not BaseUrl.EndsWith('/') then
                    BaseUrl += '/';
                BaseUrl += 'api/v2.0/';
            end;
        end;

        // Inject company GUID if entity path contains placeholder for standard API
        if EntityPath.Contains('companies(CRONUS)') or EntityPath.Contains('companies(COMPANY)') then begin
            CompanyPath := StrSubstNo('companies(%1)', GetCompanyGuid());
            EntityPath := EntityPath.Replace('companies(CRONUS)', CompanyPath);
            EntityPath := EntityPath.Replace('companies(COMPANY)', CompanyPath);
        end;

        // Inject company NAME for ODataV4 custom services
        if EntityPath.Contains('Company(''COMPANY'')') then begin
            EntityPath := EntityPath.Replace('Company(''COMPANY'')', StrSubstNo('Company(''%1'')', CompanyName()));
        end;

        // For ODataV4 paths, don't prepend api/v2.0/
        if EntityPath.StartsWith('ODataV4/') then
            BaseUrl := GetUrl(ClientType::Web);

        // Construct full URL
        if QueryString <> '' then
            exit(BaseUrl + EntityPath + '?' + QueryString)
        else
            exit(BaseUrl + EntityPath);
    end;

    local procedure GetCompanyGuid(): Text
    var
        Company: Record Company;
    begin
        // If a company has been selected in the session, use that
        if SelectedCompanyGuid <> '' then
            exit(SelectedCompanyGuid);

        // Otherwise use current company
        Company.Get(CompanyName());
        exit(Format(Company.SystemId).Replace('{', '').Replace('}', ''));
    end;

    local procedure AddAuthHeaders(var Client: HttpClient)
    var
        Headers: HttpHeaders;
    begin
        Headers := Client.DefaultRequestHeaders();
        Headers.Add('Accept', 'application/json');
        // Note: When calling from within BC, authentication is handled by the platform
        // For external calls, would need to add Bearer token
    end;

    local procedure ProcessArrayResult(ResponseJson: JsonObject; var ResultData: JsonObject; var RecordCount: Integer; var ResponseText: Text; ResponseTemplate: Text): Boolean
    var
        ValueToken: JsonToken;
        ValueArray: JsonArray;
    begin
        if not ResponseJson.Get('value', ValueToken) then
            exit(false);

        if not ValueToken.IsArray() then
            exit(false);

        ValueArray := ValueToken.AsArray();
        RecordCount := ValueArray.Count();

        ResultData := ResponseJson;

        // Generate response text
        if ResponseTemplate <> '' then
            ResponseText := ResponseTemplate.Replace('{count}', Format(RecordCount))
        else if RecordCount = 0 then
            ResponseText := 'No records found.'
        else if RecordCount = 1 then
            ResponseText := 'Found 1 record.'
        else
            ResponseText := StrSubstNo('Found %1 records.', RecordCount);

        exit(true);
    end;

    local procedure ProcessCountResult(ResponseJson: JsonObject; var ResultData: JsonObject; var RecordCount: Integer; var ResponseText: Text; ResponseTemplate: Text): Boolean
    var
        CountToken: JsonToken;
    begin
        // Response format: {"@odata.count":5, "value":[...]}
        if not ResponseJson.Get('@odata.count', CountToken) then
            exit(false);

        RecordCount := CountToken.AsValue().AsInteger();
        ResultData := ResponseJson;

        // Generate response text
        if ResponseTemplate <> '' then
            ResponseText := ResponseTemplate.Replace('{count}', Format(RecordCount)).Replace('{value}', Format(RecordCount))
        else
            ResponseText := Format(RecordCount);

        exit(true);
    end;

    local procedure ProcessAggregationResult(ResponseJson: JsonObject; var ResultData: JsonObject; var RecordCount: Integer; var ResponseText: Text; ResponseTemplate: Text): Boolean
    var
        ValueToken: JsonToken;
        ValueArray: JsonArray;
        FirstItem: JsonToken;
        FirstObj: JsonObject;
        AggregateValue: Decimal;
        AggregateText: Text;
    begin
        if not ResponseJson.Get('value', ValueToken) then
            exit(false);

        ValueArray := ValueToken.AsArray();
        RecordCount := ValueArray.Count();

        ResultData := ResponseJson;

        // Extract first aggregation value
        if ValueArray.Get(0, FirstItem) then begin
            if FirstItem.IsObject() then begin
                FirstObj := FirstItem.AsObject();
                // Try common aggregation field names
                if not TryGetAggregateValue(FirstObj, 'TotalAmount', AggregateValue) then
                    if not TryGetAggregateValue(FirstObj, 'TotalSales', AggregateValue) then
                        if not TryGetAggregateValue(FirstObj, 'TotalBalance', AggregateValue) then
                            if not TryGetAggregateValue(FirstObj, 'AvgAmount', AggregateValue) then
                                if not TryGetAggregateValue(FirstObj, 'TotalCount', AggregateValue) then
                                    TryGetAggregateValue(FirstObj, 'Count', AggregateValue);

                AggregateText := Format(AggregateValue, 0, '<Precision,2:2><Standard Format,0>');
            end;
        end;

        // Generate response text
        if ResponseTemplate <> '' then begin
            ResponseText := ResponseTemplate.Replace('{value}', AggregateText);
            ResponseText := ResponseText.Replace('{count}', Format(RecordCount));
        end else
            ResponseText := StrSubstNo('Result: %1', AggregateText);

        exit(true);
    end;

    local procedure ProcessSingleResult(ResponseJson: JsonObject; var ResultData: JsonObject; var RecordCount: Integer; var ResponseText: Text; ResponseTemplate: Text): Boolean
    begin
        RecordCount := 1;
        ResultData := ResponseJson;

        if ResponseTemplate <> '' then
            ResponseText := ResponseTemplate
        else
            ResponseText := 'Retrieved record successfully.';

        exit(true);
    end;

    [TryFunction]
    local procedure TryGetAggregateValue(JObject: JsonObject; FieldName: Text; var Value: Decimal)
    var
        Token: JsonToken;
    begin
        if JObject.Get(FieldName, Token) then
            if Token.IsValue() then
                Value := Token.AsValue().AsDecimal();
    end;

    local procedure FormatErrorResponse(Response: HttpResponseMessage): Text
    var
        StatusCode: Integer;
        ResponseContent: Text;
        ErrorJson: JsonObject;
        ErrorObj: JsonObject;
        ErrorToken: JsonToken;
        MessageToken: JsonToken;
        ErrorMessage: Text;
    begin
        StatusCode := Response.HttpStatusCode();

        // Try to parse error message from response body
        if Response.Content().ReadAs(ResponseContent) then begin
            if ErrorJson.ReadFrom(ResponseContent) then begin
                if ErrorJson.Get('error', ErrorToken) and ErrorToken.IsObject() then begin
                    ErrorObj := ErrorToken.AsObject();
                    if ErrorObj.Get('message', MessageToken) then begin
                        ErrorMessage := MessageToken.AsValue().AsText();
                        // Check if it's a field error
                        if ErrorMessage.Contains('Could not find a property named') or
                           ErrorMessage.Contains('does not exist') or
                           ErrorMessage.Contains('Invalid property') then
                            exit('Invalid field name in query. ' + ErrorMessage);
                    end;
                end;
            end;
        end;

        case StatusCode of
            400:
                exit('Invalid query format. Please try rephrasing your question.');
            401:
                exit('Authentication failed. Please check your credentials.');
            403:
                exit('You don''t have permission to access that data.');
            404:
                exit('The requested data was not found in Business Central.');
            else
                exit(StrSubstNo('Business Central API returned error %1.', StatusCode));
        end;
    end;

    /// <summary>
    /// Discovers available fields for an entity by querying BC OData API with $select=*
    /// </summary>
    /// <param name="EntityName">The entity name (e.g., 'customers', 'items')</param>
    /// <param name="FieldList">Comma-separated list of available field names</param>
    /// <returns>True if fields were discovered successfully</returns>
    procedure DiscoverEntityFields(EntityName: Text; var FieldList: Text): Boolean
    var
        Client: HttpClient;
        Response: HttpResponseMessage;
        FullUrl: Text;
        ResponseContent: Text;
        ResponseJson: JsonObject;
        ValueToken: JsonToken;
        ValueArray: JsonArray;
        FirstItem: JsonToken;
        FirstObj: JsonObject;
        Keys: List of [Text];
        KeyText: Text;
    begin
        // Build URL to get one record with all fields
        FullUrl := BuildODataUrl('companies(COMPANY)/' + EntityName, '$top=1');

        AddAuthHeaders(Client);

        if not Client.Get(FullUrl, Response) then
            exit(false);

        if not Response.IsSuccessStatusCode() then
            exit(false);

        Response.Content().ReadAs(ResponseContent);
        if not ResponseJson.ReadFrom(ResponseContent) then
            exit(false);

        // Get first record to see its fields
        if not ResponseJson.Get('value', ValueToken) then
            exit(false);

        if not ValueToken.IsArray() then
            exit(false);

        ValueArray := ValueToken.AsArray();
        if ValueArray.Count() = 0 then
            exit(false); // No records to inspect

        ValueArray.Get(0, FirstItem);
        if not FirstItem.IsObject() then
            exit(false);

        FirstObj := FirstItem.AsObject();
        Keys := FirstObj.Keys();

        // Build comma-separated field list
        FieldList := '';
        foreach KeyText in Keys do begin
            if FieldList <> '' then
                FieldList += ', ';
            FieldList += KeyText;
        end;

        exit(true);
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

    /// <summary>
    /// Gets list of all available companies in Business Central
    /// </summary>
    /// <param name="CompaniesJson">JSON array of companies with Name and SystemId</param>
    /// <returns>True if companies were retrieved successfully</returns>
    procedure GetAvailableCompanies(var CompaniesJson: JsonArray): Boolean
    var
        Company: Record Company;
        CompanyJson: JsonObject;
    begin
        CompaniesJson := CompaniesJson; // Initialize
        if Company.FindSet() then
            repeat
                Clear(CompanyJson);
                CompanyJson.Add('name', Company.Name);
                CompanyJson.Add('systemId', Format(Company.SystemId).Replace('{', '').Replace('}', ''));
                CompanyJson.Add('displayName', Company."Display Name");
                CompaniesJson.Add(CompanyJson);
            until Company.Next() = 0;
        exit(CompaniesJson.Count() > 0);
    end;

    /// <summary>
    /// Selects a company for the current session using partial name matching
    /// </summary>
    /// <param name="PartialCompanyName">Partial company name from user</param>
    /// <param name="MatchedCompanyName">The actual matched company name</param>
    /// <returns>True if company was found and selected</returns>
    procedure SelectCompanyByName(PartialCompanyName: Text; var MatchedCompanyName: Text): Boolean
    var
        Company: Record Company;
        BestMatch: Record Company;
        SearchText: Text;
        BestMatchScore: Integer;
        CurrentScore: Integer;
    begin
        SearchText := LowerCase(PartialCompanyName);
        BestMatchScore := 0;

        // Find best matching company
        if Company.FindSet() then
            repeat
                CurrentScore := 0;

                // Exact match (case insensitive)
                if LowerCase(Company.Name) = SearchText then
                    CurrentScore := 1000
                // Contains match
                else if LowerCase(Company.Name).Contains(SearchText) then
                    CurrentScore := 500
                // Display name exact match
                else if LowerCase(Company."Display Name") = SearchText then
                    CurrentScore := 900
                // Display name contains
                else if LowerCase(Company."Display Name").Contains(SearchText) then
                    CurrentScore := 450
                // Starts with
                else if LowerCase(Company.Name).StartsWith(SearchText) then
                    CurrentScore := 600;

                // Bonus for shorter company names (prefer exact matches)
                if CurrentScore > 0 then
                    CurrentScore := CurrentScore - StrLen(Company.Name);

                if CurrentScore > BestMatchScore then begin
                    BestMatchScore := CurrentScore;
                    BestMatch := Company;
                end;
            until Company.Next() = 0;

        // If we found a match, set it
        if BestMatchScore > 0 then begin
            SelectedCompanyName := BestMatch.Name;
            SelectedCompanyGuid := Format(BestMatch.SystemId).Replace('{', '').Replace('}', '');
            MatchedCompanyName := BestMatch.Name;
            exit(true);
        end;

        exit(false);
    end;

    /// <summary>
    /// Gets the currently selected company name for the session
    /// </summary>
    /// <returns>Selected company name, or empty if using current company</returns>
    procedure GetSelectedCompanyName(): Text
    begin
        exit(SelectedCompanyName);
    end;

    /// <summary>
    /// Clears the selected company, reverting to current company context
    /// </summary>
    procedure ClearSelectedCompany()
    begin
        Clear(SelectedCompanyName);
        Clear(SelectedCompanyGuid);
    end;
    /// <summary>
    /// Gets available OData entities by querying a sample endpoint and extracting entity names from URLs
    /// </summary>
    /// <param name="EntityNames">Comma-separated list of entity names</param>
    /// <returns>True if entities were discovered</returns>
    procedure GetAvailableODataEntities(var EntityNames: Text): Boolean
    var
        Client: HttpClient;
        Response: HttpResponseMessage;
        BaseUrl: Text;
        ResponseContent: Text;
        ResponseJson: JsonObject;
        ValueToken: JsonToken;
        ValueArray: JsonArray;
        ItemToken: JsonToken;
        ItemObj: JsonObject;
        NameToken: JsonToken;
        EntityName: Text;
        EntityList: List of [Text];
        i: Integer;
    begin
        // Get base URL
        BaseUrl := GetUrl(ClientType::Web);
        if not BaseUrl.EndsWith('/') then
            BaseUrl += '/';
        BaseUrl += 'api/v2.0/';

        AddAuthHeaders(Client);

        // Try to get the root API endpoint which lists available entities
        if not Client.Get(BaseUrl, Response) then
            exit(false);

        if not Response.IsSuccessStatusCode() then
            exit(false);

        Response.Content().ReadAs(ResponseContent);
        if not ResponseJson.ReadFrom(ResponseContent) then
            exit(false);

        // Parse the value array which contains entity information
        if ResponseJson.Get('value', ValueToken) and ValueToken.IsArray() then begin
            ValueArray := ValueToken.AsArray();
            for i := 0 to ValueArray.Count() - 1 do begin
                ValueArray.Get(i, ItemToken);
                if ItemToken.IsObject() then begin
                    ItemObj := ItemToken.AsObject();
                    if ItemObj.Get('name', NameToken) then begin
                        EntityName := NameToken.AsValue().AsText();
                        if EntityName <> '' then
                            if not EntityList.Contains(EntityName) then
                                EntityList.Add(EntityName);
                    end;
                end;
            end;
        end;

        // Build comma-separated list
        EntityNames := '';
        foreach EntityName in EntityList do begin
            if EntityNames <> '' then
                EntityNames += ', ';
            EntityNames += EntityName;
        end;

        exit(EntityNames <> '');
    end;

    local procedure AttemptFieldCorrection(Entity: Text; OriginalQuery: Text; ResultType: Text; ResponseTemplate: Text; var ResultData: JsonObject; var RecordCount: Integer; var ResponseText: Text): Boolean
    var
        AvailableFields: Text;
        CorrectedQuery: Text;
        InvalidField: Text;
        CorrectedField: Text;
        Setup: Record "NXR Voice Assistant Setup";
        DebugInfo: Text;
    begin
        // Try to discover available fields for this entity
        if not DiscoverEntityFields(Entity, AvailableFields) then
            exit(false); // Can't discover fields

        if Setup.Get() and Setup."Debug Mode" then
            DebugInfo := '[DEBUG-FIELD-FIX] Available fields: ' + AvailableFields + '\';

        // Try to extract the invalid field name from the query
        if not ExtractInvalidFieldFromQuery(OriginalQuery, InvalidField) then begin
            // Can't determine which field is wrong, show all available
            ResponseText := 'Query failed - field not found. Available fields: ' + AvailableFields;
            exit(false);
        end;

        if Setup.Get() and Setup."Debug Mode" then
            DebugInfo += '[DEBUG-FIELD-FIX] Invalid field detected: ' + InvalidField + '\';

        // Try to fuzzy match the invalid field to an available field
        if not FindClosestField(InvalidField, AvailableFields, CorrectedField) then begin
            ResponseText := 'Query failed - field "' + InvalidField + '" not found. Available fields: ' + AvailableFields;
            exit(false);
        end;

        if Setup.Get() and Setup."Debug Mode" then
            DebugInfo += '[DEBUG-FIELD-FIX] Matched to field: ' + CorrectedField + '\';

        // Replace invalid field with corrected field in query
        CorrectedQuery := ReplaceFieldInQuery(OriginalQuery, InvalidField, CorrectedField);

        if Setup.Get() and Setup."Debug Mode" then
            DebugInfo += '[DEBUG-FIELD-FIX] Corrected query would be: ' + CorrectedQuery + '\';

        // Note: Retry logic requires refactoring ExecuteODataQuery signature
        // For now, return the corrected field suggestion to user
        ResponseText := 'Field "' + InvalidField + '" not found. Did you mean "' + CorrectedField + '"? Available fields: ' + AvailableFields;
        exit(false);
    end;

    local procedure ExtractInvalidFieldFromQuery(Query: Text; var InvalidField: Text): Boolean
    var
        FilterPos: Integer;
        OrderByPos: Integer;
        SelectPos: Integer;
        FieldStart: Integer;
        FieldEnd: Integer;
        CurrentChar: Char;
        i: Integer;
    begin
        // Try to find field name in common OData operations
        // Look in $filter, $orderby, $select clauses

        // Check $filter= for field names
        FilterPos := Query.IndexOf('$filter=');
        if FilterPos > 0 then begin
            FieldStart := FilterPos + StrLen('$filter=');
            // Extract first field name (before space, eq, gt, lt, etc.)
            for i := FieldStart to StrLen(Query) do begin
                CurrentChar := Query[i];
                if CurrentChar in [' ', '='] then begin
                    FieldEnd := i - 1;
                    InvalidField := CopyStr(Query, FieldStart, FieldEnd - FieldStart + 1);
                    exit(InvalidField <> '');
                end;
            end;
        end;

        // Check $orderby= for field names
        OrderByPos := Query.IndexOf('$orderby=');
        if OrderByPos > 0 then begin
            FieldStart := OrderByPos + StrLen('$orderby=');
            for i := FieldStart to StrLen(Query) do begin
                CurrentChar := Query[i];
                if CurrentChar in [' ', '&', ','] then begin
                    FieldEnd := i - 1;
                    InvalidField := CopyStr(Query, FieldStart, FieldEnd - FieldStart + 1);
                    exit(InvalidField <> '');
                end;
            end;
        end;

        // Check $select= for field names
        SelectPos := Query.IndexOf('$select=');
        if SelectPos > 0 then begin
            FieldStart := SelectPos + StrLen('$select=');
            for i := FieldStart to StrLen(Query) do begin
                CurrentChar := Query[i];
                if CurrentChar in ['&', ','] then begin
                    FieldEnd := i - 1;
                    InvalidField := CopyStr(Query, FieldStart, FieldEnd - FieldStart + 1);
                    exit(InvalidField <> '');
                end;
            end;
        end;

        exit(false);
    end;

    local procedure FindClosestField(InvalidField: Text; AvailableFields: Text; var CorrectedField: Text): Boolean
    var
        FieldList: List of [Text];
        CurrentField: Text;
        BestScore: Integer;
        BestField: Text;
        Score: Integer;
    begin
        // Split AvailableFields by comma
        FieldList := AvailableFields.Split(',');

        BestScore := 0;
        BestField := '';

        foreach CurrentField in FieldList do begin
            CurrentField := CurrentField.Trim();
            Score := CalculateFieldSimilarity(InvalidField, CurrentField);

            if Score > BestScore then begin
                BestScore := Score;
                BestField := CurrentField;
            end;
        end;

        // Require at least 30% similarity to suggest a correction
        if BestScore >= 300 then begin
            CorrectedField := BestField;
            exit(true);
        end;

        exit(false);
    end;

    local procedure CalculateFieldSimilarity(Field1: Text; Field2: Text): Integer
    var
        Score: Integer;
        F1Lower: Text;
        F2Lower: Text;
    begin
        F1Lower := LowerCase(Field1);
        F2Lower := LowerCase(Field2);

        // Exact match (case-insensitive)
        if F1Lower = F2Lower then
            exit(1000);

        // Starts with
        if F2Lower.StartsWith(F1Lower) or F1Lower.StartsWith(F2Lower) then
            Score += 700;

        // Contains
        if F2Lower.Contains(F1Lower) or F1Lower.Contains(F2Lower) then
            Score += 500;

        // Similar length (closer lengths = higher score)
        if Abs(StrLen(Field1) - StrLen(Field2)) <= 2 then
            Score += 200;

        // Check for common patterns: underscore vs space, with vs without spaces
        if (F1Lower.Replace('_', '') = F2Lower.Replace('_', '')) or
           (F1Lower.Replace(' ', '') = F2Lower.Replace(' ', ''))
        then
            Score += 800;

        exit(Score);
    end;

    local procedure ReplaceFieldInQuery(OriginalQuery: Text; OldField: Text; NewField: Text): Text
    var
        CorrectedQuery: Text;
    begin
        // Replace all occurrences of OldField with NewField in the query
        // Be careful to do case-insensitive replacement
        CorrectedQuery := OriginalQuery.Replace(OldField, NewField);

        // Also try with different cases
        if CorrectedQuery = OriginalQuery then
            CorrectedQuery := OriginalQuery.Replace(LowerCase(OldField), NewField);

        if CorrectedQuery = OriginalQuery then
            CorrectedQuery := OriginalQuery.Replace(UpperCase(OldField), NewField);

        exit(CorrectedQuery);
    end;

    local procedure GetJsonKeys(JsonObj: JsonObject): Text
    var
        KeysList: List of [Text];
        KeysText: Text;
        KeyToken: JsonToken;
        KeyName: Text;
    begin
        KeysText := '';
        foreach KeyName in JsonObj.Keys() do begin
            if KeysText <> '' then
                KeysText += ', ';
            KeysText += KeyName;
        end;
        exit(KeysText);
    end;
}