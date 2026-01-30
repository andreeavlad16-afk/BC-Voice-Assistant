/// <summary>
/// Integrates with AI services (Azure OpenAI, OpenAI, Local LLM) for advanced query analysis.
/// Provides intelligent query understanding beyond pattern matching.
/// </summary>
codeunit 50607 "NXR Voice AI Service"
{
    var
        Setup: Record "NXR Voice Assistant Setup";
        SetupLoaded: Boolean;

    /// <summary>
    /// Analyzes a natural language query using configured AI backend.
    /// </summary>
    /// <param name="QueryText">The natural language query to analyze.</param>
    /// <param name="Intent">The resulting query intent with extracted entities and parameters.</param>
    /// <returns>True if AI analysis was successful, false if no AI backend configured or analysis failed.</returns>
    procedure AnalyzeQueryWithAI(QueryText: Text; var Intent: Record "NXR Voice Query Intent" temporary): Boolean
    var
        EmptyHistory: JsonArray;
    begin
        // Delegate to history-aware method with empty history for backward compatibility
        exit(AnalyzeQueryWithHistory(QueryText, EmptyHistory, Intent));
    end;

    /// <summary>
    /// Analyzes a natural language query with conversation history and returns structured query intent using AI.
    /// </summary>
    procedure AnalyzeQueryWithHistory(QueryText: Text; ConversationHistory: JsonArray; var Intent: Record "NXR Voice Query Intent" temporary): Boolean
    var
        Setup: Record "NXR Voice Assistant Setup";
        DebugInfo: Text;
    begin
        if not Setup.Get() then
            exit(false);

        if Setup."Debug Mode" then
            DebugInfo := StrSubstNo('[DEBUG] Analyzing query with %1: "%2"\', Format(Setup."AI Backend Type"), QueryText);

        case Setup."AI Backend Type" of
            Setup."AI Backend Type"::LocalLLM:
                exit(AnalyzeWithLocalLLM(QueryText, Intent));
            Setup."AI Backend Type"::AzureOpenAI:
                exit(AnalyzeWithAzureOpenAIAndHistory(QueryText, ConversationHistory, Intent));
            Setup."AI Backend Type"::OpenAI:
                exit(AnalyzeWithOpenAIAndHistory(QueryText, ConversationHistory, Intent));
            Setup."AI Backend Type"::OnDeviceAI:
                exit(false); // Handled by JavaScript control
            else
                exit(false);
        end;
    end;

    /// <summary>
    /// Generates follow-up question suggestions based on the current query and result.
    /// </summary>
    procedure GenerateFollowUpSuggestions(QueryText: Text; ResponseText: Text; StructuredData: Text; ConversationHistory: JsonArray): Text
    var
        Setup: Record "NXR Voice Assistant Setup";
        Client: HttpClient;
        RequestContent: HttpContent;
        Response: HttpResponseMessage;
        ResponseJson: JsonObject;
        ResponseTextResult: Text;
        AzureUrl: Text;
        RequestJson: JsonObject;
        MessagesArray: JsonArray;
        PromptText: Text;
    begin
        if not Setup.Get() then
            exit('');

        if Setup."AI Backend Type" <> Setup."AI Backend Type"::AzureOpenAI then
            exit(''); // Only support Azure OpenAI for now

        if (Setup."API Endpoint" = '') or (Setup."Azure Deployment Name" = '') then
            exit('');

        if not Setup.HasApiKey() then
            exit('');

        // Build prompt for follow-up generation
        PromptText := 'Based on this query and result, suggest 2-3 relevant follow-up questions the user might ask next.\n\n';
        PromptText += 'User Query: ' + QueryText + '\n';
        PromptText += 'System Response: ' + ResponseText + '\n\n';
        if StructuredData <> '' then
            PromptText += 'Query Structure: ' + StructuredData + '\n\n';
        PromptText += 'Generate ONLY 2-3 short follow-up questions (one per line, no numbering, no explanations). Examples:\n';
        PromptText += '- If they asked about customers, suggest: "Show me orders from my top customer" or "Which customers are in London?"\n';
        PromptText += '- If they asked about counts, suggest showing the actual list\n';
        PromptText += '- If they filtered by city, suggest other cities or related queries\n';
        PromptText += 'Format as: "You might also ask:\\n- Question 1\\n- Question 2"';

        // Build request with conversation history
        BuildFollowUpRequest(PromptText, ConversationHistory, RequestJson);
        
        AzureUrl := BuildAzureUrl();
        RequestJson.WriteTo(ResponseTextResult);
        RequestContent.WriteFrom(ResponseTextResult);
        
        AddAzureAuthHeader(Client);
        AddContentTypeHeader(RequestContent);

        if not Client.Post(AzureUrl, RequestContent, Response) then
            exit('');

        if not Response.IsSuccessStatusCode() then
            exit('');

        Response.Content().ReadAs(ResponseTextResult);
        if not ResponseJson.ReadFrom(ResponseTextResult) then
            exit('');

        exit(ExtractFollowUpText(ResponseJson));
    end;

    /// <summary>
    /// Analyzes a natural language query using configured AI backend and captures debug information.
    /// </summary>
    /// <param name="QueryText">The natural language query to analyze.</param>
    /// <param name="Intent">The resulting query intent with extracted entities and parameters.</param>
    /// <param name="DebugInfo">Returns debug information if Setup."Debug Mode" is enabled, empty otherwise.</param>
    /// <returns>True if AI analysis was successful, false if no AI backend configured or analysis failed.</returns>
    procedure AnalyzeQueryWithAIDebug(QueryText: Text; var Intent: Record "NXR Voice Query Intent" temporary; var DebugInfo: Text): Boolean
    begin
        DebugInfo := '';

        if not LoadSetup() then begin
            DebugInfo := '[DEBUG] Setup not loaded.';
            exit(false);
        end;

        if Setup."AI Backend Type" = Setup."AI Backend Type"::None then begin
            DebugInfo := '[DEBUG] No AI backend configured.';
            exit(false);
        end;

        if Setup."Debug Mode" then
            DebugInfo += StrSubstNo('[DEBUG] Analyzing query with %1: "%2"\', Format(Setup."AI Backend Type"), QueryText);

        case Setup."AI Backend Type" of
            Setup."AI Backend Type"::LocalLLM:
                exit(AnalyzeWithLocalLLM(QueryText, Intent));
            Setup."AI Backend Type"::AzureOpenAI:
                exit(AnalyzeWithAzureOpenAI(QueryText, Intent));
            Setup."AI Backend Type"::OpenAI:
                exit(AnalyzeWithOpenAI(QueryText, Intent));
            Setup."AI Backend Type"::OnDeviceAI:
                exit(false); // Handled by JavaScript control
            else
                exit(false);
        end;
    end;

    /// <summary>
    /// Tests the connection to the configured AI backend service.
    /// </summary>
    /// <returns>True if the connection is successful, false otherwise.</returns>
    procedure TestConnection(): Boolean
    var
        Detail: Text;
    begin
        exit(TestConnectionWithDetail(Detail));
    end;

    /// <summary>
    /// Tests the connection to the configured AI backend service and returns diagnostic detail.
    /// </summary>
    /// <param name="Detail">Returns HTTP status and body (trimmed) when available.</param>
    /// <returns>True if the connection is successful, false otherwise.</returns>
    procedure TestConnectionWithDetail(var Detail: Text): Boolean
    var
        Client: HttpClient;
        Response: HttpResponseMessage;
        TestUrl: Text;
        RequestContent: HttpContent;
    begin
        Detail := '';

        if not LoadSetup() then begin
            Detail := 'Setup not found.';
            exit(false);
        end;

        // Validate that API key is configured for backends that require it
        if Setup."AI Backend Type" in [Setup."AI Backend Type"::AzureOpenAI, Setup."AI Backend Type"::OpenAI] then
            if not Setup.HasApiKey() then begin
                Detail := 'API key is missing.';
                exit(false);
            end;

        case Setup."AI Backend Type" of
            Setup."AI Backend Type"::AzureOpenAI:
                begin
                    // Use the same chat completions endpoint as live calls to avoid path/verb mismatches
                    TestUrl := BuildAzureUrl();
                    if TestUrl = '' then begin
                        Detail := 'Missing API Endpoint or Deployment Name.';
                        exit(false);
                    end;
                    AddAzureAuthHeader(Client);
                    PrepareTestChatRequest(RequestContent);
                    if not TryPostRequest(Client, TestUrl, RequestContent, Response) then begin
                        Detail := 'HTTP POST failed (network/SSL/URL issue).';
                        exit(false);
                    end;
                end;
            Setup."AI Backend Type"::OpenAI:
                begin
                    TestUrl := 'https://api.openai.com/v1/models';
                    AddOpenAIAuthHeader(Client);
                    if not TryGetRequest(Client, TestUrl, Response) then begin
                        Detail := 'HTTP GET failed (network/SSL/URL issue).';
                        exit(false);
                    end;
                end;
            Setup."AI Backend Type"::LocalLLM:
                begin
                    if Setup."API Endpoint" = '' then begin
                        Detail := 'Local LLM endpoint is empty.';
                        exit(false);
                    end;
                    TestUrl := Setup."API Endpoint" + '/v1/models';
                    AddLocalLLMAuthHeader(Client);
                    if not TryGetRequest(Client, TestUrl, Response) then begin
                        Detail := 'HTTP GET failed (network/SSL/URL issue).';
                        exit(false);
                    end;
                end;
            else begin
                Detail := 'Unsupported backend type or not configured.';
                exit(false);
            end;
        end;

        Detail := GetResponseDetail(Response);
        exit(Response.IsSuccessStatusCode());
    end;

    local procedure GetResponseDetail(Response: HttpResponseMessage): Text
    var
        Body: Text;
        StatusText: Text;
    begin
        StatusText := StrSubstNo('Status: %1', Format(Response.HttpStatusCode()));

        Response.Content().ReadAs(Body);
        Body := CopyStr(Body, 1, 500); // keep it concise
        exit(StrSubstNo('%1. Body: %2', StatusText, Body));
    end;

    [TryFunction]
    local procedure TryPostRequest(var Client: HttpClient; TestUrl: Text; var RequestContent: HttpContent; var Response: HttpResponseMessage)
    begin
        Client.Post(TestUrl, RequestContent, Response);
    end;

    [TryFunction]
    local procedure TryGetRequest(var Client: HttpClient; TestUrl: Text; var Response: HttpResponseMessage)
    begin
        Client.Get(TestUrl, Response);
    end;

    local procedure PrepareTestChatRequest(var RequestContent: HttpContent)
    var
        Payload: JsonObject;
        Messages: JsonArray;
        Message: JsonObject;
        PayloadText: Text;
        Headers: HttpHeaders;
    begin
        Message.Add('role', 'user');
        Message.Add('content', 'ping');
        Messages.Add(Message);

        Payload.Add('messages', Messages);
        Payload.Add('max_tokens', 5);
        Payload.Add('temperature', 0);

        Payload.WriteTo(PayloadText);
        RequestContent.WriteFrom(PayloadText);
        RequestContent.GetHeaders(Headers);
        Headers.Clear();
        Headers.Add('Content-Type', 'application/json');
    end;

    /// <summary>
    /// Tests the AI backend by sending a sample query and returning the response.
    /// </summary>
    /// <param name="ResponseText">The AI's response to the test query.</param>
    /// <returns>True if the AI responded successfully, false otherwise.</returns>
    procedure TestQueryAI(var ResponseText: Text): Boolean
    var
        Intent: Record "NXR Voice Query Intent" temporary;
        TestQuery: Label 'Show me my top 5 customers';
        StructuredDataPreview: Text;
        DebugInfo: Text;
    begin
        if not LoadSetup() then
            exit(false);

        if Setup."AI Backend Type" = Setup."AI Backend Type"::None then
            exit(false);

        if Setup."AI Backend Type" = Setup."AI Backend Type"::OnDeviceAI then
            exit(false);

        // Try to analyze a simple test query (with debug capture)
        if not AnalyzeQueryWithAIDebug(TestQuery, Intent, DebugInfo) then begin
            ResponseText := 'AI did not respond';
            if Setup."Debug Mode" and (DebugInfo <> '') then
                ResponseText += '\' + DebugInfo;
            exit(false);
        end;

        // Show the full structured JSON that the AI returned
        if Intent."Structured Data" <> '' then begin
            StructuredDataPreview := Intent."Structured Data";
            // Truncate if too long for display
            if StrLen(StructuredDataPreview) > 500 then
                StructuredDataPreview := CopyStr(StructuredDataPreview, 1, 500) + '...';

            ResponseText := StrSubstNo('AI understood: "%1" as:\\%2', TestQuery, StructuredDataPreview);
        end else begin
            // Fallback to old format if no structured data
            ResponseText := StrSubstNo('AI understood: "%1" as:\\Entity: %2\\Top: %3',
                TestQuery,
                Format(Intent.Entity),
                Intent."Top N");
        end;

        // Append debug info if enabled
        if Setup."Debug Mode" and (DebugInfo <> '') then
            ResponseText += '\' + DebugInfo;

        exit(true);
    end;

    local procedure LoadSetup(): Boolean
    begin
        if SetupLoaded then
            exit(true);

        if not Setup.Get() then
            exit(false);

        SetupLoaded := true;
        exit(true);
    end;

    local procedure AnalyzeWithLocalLLM(QueryText: Text; var Intent: Record "NXR Voice Query Intent" temporary): Boolean
    var
        Client: HttpClient;
        RequestContent: HttpContent;
        Response: HttpResponseMessage;
        ResponseJson: JsonObject;
        ResponseText: Text;
    begin
        if Setup."API Endpoint" = '' then
            exit(false);

        PrepareRequest(RequestContent, QueryText);
        AddLocalLLMAuthHeader(Client);

        if not Client.Post(Setup."API Endpoint" + '/chat/completions', RequestContent, Response) then
            exit(false);

        if not Response.IsSuccessStatusCode() then
            exit(false);

        Response.Content().ReadAs(ResponseText);
        if not ResponseJson.ReadFrom(ResponseText) then
            exit(false);

        exit(ParseAIResponse(ResponseJson, Intent));
    end;

    local procedure AnalyzeWithAzureOpenAIAndHistory(QueryText: Text; ConversationHistory: JsonArray; var Intent: Record "NXR Voice Query Intent" temporary): Boolean
    var
        Client: HttpClient;
        RequestContent: HttpContent;
        Response: HttpResponseMessage;
        ResponseJson: JsonObject;
        ResponseText: Text;
        AzureUrl: Text;
        RequestJson: JsonObject;
    begin
        if (Setup."API Endpoint" = '') or (Setup."Azure Deployment Name" = '') then
            exit(false);

        if not Setup.HasApiKey() then
            exit(false);

        AzureUrl := BuildAzureUrl();
        RequestJson := BuildOpenAIRequestWithHistory(QueryText, ConversationHistory);
        PrepareRequestFromJson(RequestContent, RequestJson);
        AddAzureAuthHeader(Client);

        if not Client.Post(AzureUrl, RequestContent, Response) then
            exit(false);

        if not Response.IsSuccessStatusCode() then
            exit(false);

        Response.Content().ReadAs(ResponseText);
        if not ResponseJson.ReadFrom(ResponseText) then
            exit(false);

        exit(ParseAIResponse(ResponseJson, Intent));
    end;

    local procedure AnalyzeWithOpenAIAndHistory(QueryText: Text; ConversationHistory: JsonArray; var Intent: Record "NXR Voice Query Intent" temporary): Boolean
    var
        Client: HttpClient;
        RequestContent: HttpContent;
        Response: HttpResponseMessage;
        ResponseJson: JsonObject;
        ResponseText: Text;
        RequestJson: JsonObject;
    begin
        if not Setup.HasApiKey() then
            exit(false);

        RequestJson := BuildOpenAIRequestWithHistory(QueryText, ConversationHistory);
        PrepareRequestFromJson(RequestContent, RequestJson);
        AddOpenAIAuthHeader(Client);

        if not Client.Post('https://api.openai.com/v1/chat/completions', RequestContent, Response) then
            exit(false);

        if not Response.IsSuccessStatusCode() then
            exit(false);

        Response.Content().ReadAs(ResponseText);
        if not ResponseJson.ReadFrom(ResponseText) then
            exit(false);

        exit(ParseAIResponse(ResponseJson, Intent));
    end;

    local procedure AnalyzeWithAzureOpenAI(QueryText: Text; var Intent: Record "NXR Voice Query Intent" temporary): Boolean
    var
        Client: HttpClient;
        RequestContent: HttpContent;
        Response: HttpResponseMessage;
        ResponseJson: JsonObject;
        ResponseText: Text;
        AzureUrl: Text;
    begin
        if (Setup."API Endpoint" = '') or (Setup."Azure Deployment Name" = '') then
            exit(false);

        if not Setup.HasApiKey() then
            exit(false);

        AzureUrl := BuildAzureUrl();
        PrepareRequest(RequestContent, QueryText);
        AddAzureAuthHeader(Client);

        if not Client.Post(AzureUrl, RequestContent, Response) then
            exit(false);

        if not Response.IsSuccessStatusCode() then
            exit(false);

        Response.Content().ReadAs(ResponseText);
        if not ResponseJson.ReadFrom(ResponseText) then
            exit(false);

        exit(ParseAIResponse(ResponseJson, Intent));
    end;

    local procedure AnalyzeWithOpenAI(QueryText: Text; var Intent: Record "NXR Voice Query Intent" temporary): Boolean
    var
        Client: HttpClient;
        RequestContent: HttpContent;
        Response: HttpResponseMessage;
        ResponseJson: JsonObject;
        ResponseText: Text;
    begin
        if not Setup.HasApiKey() then
            exit(false);

        PrepareRequest(RequestContent, QueryText);
        AddOpenAIAuthHeader(Client);

        if not Client.Post('https://api.openai.com/v1/chat/completions', RequestContent, Response) then
            exit(false);

        if not Response.IsSuccessStatusCode() then
            exit(false);

        Response.Content().ReadAs(ResponseText);
        if not ResponseJson.ReadFrom(ResponseText) then
            exit(false);

        exit(ParseAIResponse(ResponseJson, Intent));
    end;

    local procedure BuildAzureUrl(): Text
    var
        AzureUrl: Text;
        ApiVersion: Text;
    begin
        AzureUrl := Setup."API Endpoint";
        // Remove trailing slash if present to avoid double slashes
        if AzureUrl.EndsWith('/') then
            AzureUrl := CopyStr(AzureUrl, 1, StrLen(AzureUrl) - 1);

        ApiVersion := Setup."Azure API Version";
        if ApiVersion = '' then
            ApiVersion := '2024-08-06';

        AzureUrl += '/openai/deployments/' + Setup."Azure Deployment Name" + '/chat/completions?api-version=' + ApiVersion;
        exit(AzureUrl);
    end;

    local procedure AddAzureAuthHeader(var Client: HttpClient)
    var
        ApiKey: SecretText;
    begin
        ApiKey := Setup.GetApiKey();
        if not ApiKey.IsEmpty() then
            Client.DefaultRequestHeaders().Add('api-key', ApiKey);
    end;

    local procedure AddOpenAIAuthHeader(var Client: HttpClient)
    var
        ApiKey: SecretText;
        AuthHeaderValue: SecretText;
    begin
        ApiKey := Setup.GetApiKey();
        if not ApiKey.IsEmpty() then begin
            AuthHeaderValue := SecretStrSubstNo('Bearer %1', ApiKey);
            Client.DefaultRequestHeaders().Add('Authorization', AuthHeaderValue);
        end;
    end;

    local procedure AddLocalLLMAuthHeader(var Client: HttpClient)
    var
        ApiKey: SecretText;
        AuthHeaderValue: SecretText;
    begin
        // Local LLM may or may not require auth
        ApiKey := Setup.GetApiKey();
        if not ApiKey.IsEmpty() then begin
            AuthHeaderValue := SecretStrSubstNo('Bearer %1', ApiKey);
            Client.DefaultRequestHeaders().Add('Authorization', AuthHeaderValue);
        end;
    end;

    local procedure PrepareRequest(var RequestContent: HttpContent; QueryText: Text)
    var
        ContentHeaders: HttpHeaders;
        RequestJson: JsonObject;
        RequestText: Text;
    begin
        RequestJson := BuildOpenAIRequest(QueryText);
        RequestJson.WriteTo(RequestText);

        RequestContent.WriteFrom(RequestText);
        RequestContent.GetHeaders(ContentHeaders);
        ContentHeaders.Clear();
        ContentHeaders.Add('Content-Type', 'application/json');
    end;

    local procedure BuildOpenAIRequest(QueryText: Text): JsonObject
    var
        RequestJson: JsonObject;
        MessagesArray: JsonArray;
        SystemMessage: JsonObject;
        UserMessage: JsonObject;
        MaxTokens: Integer;
        AvailableEntities: Text;
        EnhancedSystemPrompt: Text;
        ODataSchemaContext: Text;
        SystemPromptLbl: Label 'You are a Business Central query analyzer. Your job is to interpret natural language business questions and translate them into structured read-only database queries that return sensible, meaningful results.\\\\KEY PRINCIPLES:\\- Understand business intent, not just literal words\\- "Top customers" means highest sales volume, not first records\\- "Best" means highest value/performance metric\\- Choose appropriate sorting to make results meaningful\\- Always return read-only queries (SELECT, no INSERT/UPDATE/DELETE)\\- ALWAYS extract numbers from queries, whether written as digits (5, 10) or words (five, ten, three)\\- PREFER SINGLE-TABLE QUERIES: Use joins ONLY when data from multiple tables is truly needed\\- Most entity lists (customers, items, vendors) should be single-table queries\\- Example: "customers in London" = single table Customer with city filter, NOT a join\\\\NUMBER PARSING:\\- "five" → 5, "ten" → 10, "three" → 3, etc.\\- "top five", "top 5", "best 5", "give me 5" all mean "top": 5\\- If no number specified but query says "top/best/biggest", default to 10\\\\FILTER CONSTRUCTION RULES:\\1. Use EXACT field names from schema (case-sensitive for OData)\\2. Empty strings: Use '''' (two single quotes) NOT null or empty\\3. Null checks: Use IS NULL or IS NOT NULL, never = null\\4. Text filters: Use single quotes - City eq ''London''\\5. Number filters: No quotes - Balance_LCY gt 1000\\6. Combine filters with AND/OR - City eq ''London'' and Balance_LCY gt 1000\\7. Partial text match (OData): Use contains(Name,''text'') or startswith(Name,''text'')\\8. Partial text match (Native): Use filter with wildcards - Name LIKE ''%text%''\\\\DATE FILTER SYNTAX (Business Central):\\- Today: T or 0D (zero days from today)\\- Yesterday: -1D (one day before today)\\- Tomorrow: 1D (one day after today)\\- This week: CW (current week)\\- This month: CM (current month)\\- This year: CY (current year)\\- Last 7 days: -7D..0D or T-7D..T\\- Last 30 days: -30D..0D or T-30D..T\\- Next 30 days: 0D..30D or T..T+30D\\- Specific date: 2024-01-15 (YYYY-MM-DD format)\\- Date range: 2024-01-01..2024-12-31\\- From date onwards: 2024-01-01.. (no end date)\\- Up to date: ..2024-12-31 (no start date)\\\\DATE QUERY EXAMPLES:\\- "this year" → dateFilter: {"field":"Order_Date","value":"CY"}\\- "this month" → dateFilter: {"field":"Posting_Date","value":"CM"}\\- "today" → dateFilter: {"field":"Order_Date","value":"T"}\\- "yesterday" → dateFilter: {"field":"Order_Date","value":"-1D"}\\- "last 7 days" → dateFilter: {"field":"Order_Date","value":"T-7D..T"}\\- "last month" → dateFilter: {"field":"Order_Date","value":"CM-1"} or calculate range\\- "next week" → dateFilter: {"field":"Order_Date","value":"CW+1"}\\\\NULL vs EMPTY STRING:\\- Database NULL: Field has no value, use "IS NULL" check\\- Empty string '''': Field has empty text value, use = ''''\\- In JSON output: Use null for NULL, "" for empty string\\- NEVER use null in filter values - use IS NULL operator instead\\- Example: {"field":"City","operator":"IS NULL"} NOT {"field":"City","value":null}\\\\EXECUTION MODES:\\1. NATIVE MODE (ALWAYS USE THIS): Handles ALL queries including aggregations (SUM, AVG, COUNT), GROUP BY, sorting, and filtering\\2. ODATA MODE (DEPRECATED - DO NOT USE): Requires OAuth authentication which is not available\\\\IMPORTANT: Native mode now supports GROUP BY and aggregations - see examples below.\\\\SCHEMA REFERENCE (Native Mode - BC Table Field Names):\\\\MASTER DATA:\\Customer: No., Name, Name 2, Address, City, County, Post Code, Country/Region Code, Phone No., E-Mail, Contact, Balance (LCY), Balance Due (LCY), Sales (LCY), Credit Limit (LCY), Payment Terms Code, Salesperson Code, Customer Posting Group, Blocked\\Vendor: No., Name, Name 2, Address, City, County, Post Code, Country/Region Code, Phone No., E-Mail, Contact, Balance (LCY), Balance Due (LCY), Payment Terms Code, Purchaser Code, Vendor Posting Group, Blocked\\Item: No., Description, Description 2, Type, Base Unit of Measure, Inventory, Unit Price, Unit Cost, Last Direct Cost, Standard Cost, Sales (LCY), Vendor No., Item Category Code, Product Group Code, Gen. Prod. Posting Group, Blocked\\Employee: No., First Name, Middle Name, Last Name, Initials, Job Title, Search Name, Address, City, Post Code, Phone No., Mobile Phone No., E-Mail, Company E-Mail, Employment Date, Status, Birth Date\\Location: Code, Name, Address, City, Post Code, Contact, Phone No., Use As In-Transit, Use Cross-Docking, Require Put-away, Require Pick, Require Receive, Require Shipment\\Bank Account: No., Name, Bank Account No., IBAN, SWIFT Code, Currency Code, Balance (LCY), Balance at Date (LCY), Address, City, Post Code, Contact, Phone No.\\\\SALES DOCUMENTS:\\Sales Header: Document Type, No., Sell-to Customer No., Sell-to Customer Name, Sell-to Contact, Sell-to Address, Sell-to City, Bill-to Customer No., Bill-to Name, Ship-to Code, Ship-to Name, Ship-to Address, Ship-to City, Order Date, Posting Date, Document Date, Shipment Date, Due Date, Payment Terms Code, Payment Method Code, Shipment Method Code, Location Code, Salesperson Code, Currency Code, Amount, Amount Including VAT, Outstanding Amount, Shipped Not Invoiced, Status, External Document No., Your Reference, Requested Delivery Date\\Sales Line: Document Type, Document No., Line No., Type, No., Description, Location Code, Quantity, Unit of Measure Code, Unit Price, Line Discount %, Line Discount Amount, Amount, Amount Including VAT, Outstanding Quantity, Quantity Shipped, Quantity Invoiced, VAT %, Shipment Date, Work Type Code, Job No.\\Sales Invoice Header: No., Sell-to Customer No., Sell-to Customer Name, Bill-to Customer No., Bill-to Name, Order No., Posting Date, Document Date, Due Date, Payment Terms Code, Salesperson Code, Currency Code, Amount, Amount Including VAT, Remaining Amount, Closed, External Document No.\\Sales Invoice Line: Document No., Line No., Type, No., Description, Quantity, Unit Price, Line Discount %, Amount, Amount Including VAT, VAT %\\Sales Shipment Header: No., Sell-to Customer No., Sell-to Customer Name, Ship-to Name, Ship-to Address, Ship-to City, Order No., Order Date, Posting Date, Shipment Date, Location Code, Salesperson Code\\Sales Shipment Line: Document No., Line No., Type, No., Description, Quantity, Unit of Measure Code, Location Code\\Sales Cr.Memo Header: No., Sell-to Customer No., Sell-to Customer Name, Posting Date, Amount, Amount Including VAT, Remaining Amount, Applies-to Doc. Type, Applies-to Doc. No.\\Sales Cr.Memo Line: Document No., Line No., Type, No., Description, Quantity, Unit Price, Amount, Amount Including VAT\\\\PURCHASE DOCUMENTS:\\Purchase Header: Document Type, No., Buy-from Vendor No., Buy-from Vendor Name, Buy-from Contact, Buy-from Address, Buy-from City, Pay-to Vendor No., Pay-to Name, Ship-to Code, Ship-to Name, Order Date, Posting Date, Document Date, Expected Receipt Date, Due Date, Payment Terms Code, Payment Method Code, Location Code, Purchaser Code, Currency Code, Amount, Amount Including VAT, Outstanding Amount, Amt. Rcd. Not Invoiced, Status, Vendor Invoice No., Vendor Order No.\\Purchase Line: Document Type, Document No., Line No., Type, No., Description, Location Code, Quantity, Unit of Measure Code, Direct Unit Cost, Line Discount %, Line Discount Amount, Amount, Amount Including VAT, Outstanding Quantity, Quantity Received, Quantity Invoiced, VAT %, Expected Receipt Date, Job No.\\Purch. Inv. Header: No., Buy-from Vendor No., Buy-from Vendor Name, Pay-to Vendor No., Pay-to Name, Order No., Posting Date, Document Date, Due Date, Payment Terms Code, Purchaser Code, Currency Code, Amount, Amount Including VAT, Remaining Amount, Closed, Vendor Invoice No.\\Purch. Inv. Line: Document No., Line No., Type, No., Description, Quantity, Direct Unit Cost, Line Discount %, Amount, Amount Including VAT, VAT %\\Purch. Rcpt. Header: No., Buy-from Vendor No., Buy-from Vendor Name, Order No., Order Date, Posting Date, Expected Receipt Date, Location Code, Purchaser Code\\Purch. Rcpt. Line: Document No., Line No., Type, No., Description, Quantity, Unit of Measure Code, Location Code\\Purch. Cr. Memo Hdr.: No., Buy-from Vendor No., Buy-from Vendor Name, Posting Date, Amount, Amount Including VAT, Remaining Amount, Vendor Cr. Memo No.\\Purch. Cr. Memo Line: Document No., Line No., Type, No., Description, Quantity, Direct Unit Cost, Amount, Amount Including VAT\\\\LEDGER ENTRIES:\\G/L Entry: Entry No., G/L Account No., G/L Account Name, Posting Date, Document Type, Document No., Description, Amount, Debit Amount, Credit Amount, VAT Amount, Source Code, Source Type, Source No., User ID, Transaction No., Journal Batch Name, Journal Template Name, Global Dimension 1 Code, Global Dimension 2 Code, Gen. Posting Type, Gen. Bus. Posting Group, Gen. Prod. Posting Group\\Cust. Ledger Entry: Entry No., Customer No., Customer Name, Posting Date, Document Type, Document No., Description, Currency Code, Amount, Amount (LCY), Remaining Amount, Remaining Amt. (LCY), Original Amount, Original Amt. (LCY), Sales (LCY), Closed, Open, Due Date, Pmt. Discount Date, On Hold, Global Dimension 1 Code, Global Dimension 2 Code, Salesperson Code\\Vendor Ledger Entry: Entry No., Vendor No., Vendor Name, Posting Date, Document Type, Document No., Description, Currency Code, Amount, Amount (LCY), Remaining Amount, Remaining Amt. (LCY), Original Amount, Original Amt. (LCY), Purchase (LCY), Closed, Open, Due Date, Pmt. Discount Date, On Hold, Global Dimension 1 Code, Global Dimension 2 Code, Purchaser Code\\Item Ledger Entry: Entry No., Item No., Posting Date, Entry Type, Source Type, Source No., Document No., Document Type, Location Code, Quantity, Remaining Quantity, Invoiced Quantity, Sales Amount (Actual), Cost Amount (Actual), Unit Cost, Unit Price, Global Dimension 1 Code, Global Dimension 2 Code, Lot No., Serial No.\\Value Entry: Entry No., Item Ledger Entry No., Item No., Posting Date, Entry Type, Source Type, Source No., Document No., Location Code, Item Ledger Entry Quantity, Valued Quantity, Cost Amount (Actual), Cost Amount (Expected), Cost Posted to G/L, Sales Amount (Actual), Sales Amount (Expected), Invoiced Quantity\\Bank Account Ledger Entry: Entry No., Bank Account No., Posting Date, Document Type, Document No., Description, Amount, Amount (LCY), Remaining Amount, Debit Amount, Credit Amount, Open, Statement Status, Statement No., Statement Line No.\\\\FINANCE & DIMENSIONS:\\G/L Account: No., Name, Account Type, Account Category, Income/Balance, Debit/Credit, Balance, Net Change, Blocked\\Dimension: Code, Name, Description, Code Caption, Blocked\\Dimension Value: Dimension Code, Code, Name, Dimension Value Type, Totaling, Blocked, Indentation, Global Dimension No.\\Gen. Journal Line: Journal Template Name, Journal Batch Name, Line No., Account Type, Account No., Posting Date, Document Type, Document No., Description, Amount, Bal. Account Type, Bal. Account No., Currency Code, Applies-to Doc. Type, Applies-to Doc. No.\\Gen. Journal Batch: Journal Template Name, Name, Description\\\\TABLE RELATIONSHIPS (for joins and filters):\\\\SALES RELATIONSHIPS:\\- Sales Header → Customer: Sales Header."Sell-to Customer No." = Customer."No." (get customer details for sales order)\\- Sales Header → Customer: Sales Header."Bill-to Customer No." = Customer."No." (get billing customer)\\- Sales Line → Sales Header: Sales Line."Document No." = Sales Header."No." AND Sales Line."Document Type" = Sales Header."Document Type" (get lines for header)\\- Sales Line → Item: Sales Line."No." = Item."No." (when Type=Item, get item details)\\- Sales Line → Location: Sales Line."Location Code" = Location."Code" (get warehouse location)\\- Sales Invoice Header → Customer: Sales Invoice Header."Sell-to Customer No." = Customer."No."\\- Sales Invoice Line → Sales Invoice Header: Sales Invoice Line."Document No." = Sales Invoice Header."No."\\- Sales Invoice Line → Item: Sales Invoice Line."No." = Item."No." (when Type=Item)\\- Sales Shipment Header → Customer: Sales Shipment Header."Sell-to Customer No." = Customer."No."\\- Sales Shipment Line → Item: Sales Shipment Line."No." = Item."No." (when Type=Item)\\- Sales Cr.Memo Header → Customer: Sales Cr.Memo Header."Sell-to Customer No." = Customer."No."\\\\PURCHASE RELATIONSHIPS:\\- Purchase Header → Vendor: Purchase Header."Buy-from Vendor No." = Vendor."No." (get vendor details)\\- Purchase Header → Vendor: Purchase Header."Pay-to Vendor No." = Vendor."No." (get payee vendor)\\- Purchase Line → Purchase Header: Purchase Line."Document No." = Purchase Header."No." AND Purchase Line."Document Type" = Purchase Header."Document Type"\\- Purchase Line → Item: Purchase Line."No." = Item."No." (when Type=Item)\\- Purchase Line → Location: Purchase Line."Location Code" = Location."Code."\\- Purch. Inv. Header → Vendor: Purch. Inv. Header."Buy-from Vendor No." = Vendor."No."\\- Purch. Inv. Line → Purch. Inv. Header: Purch. Inv. Line."Document No." = Purch. Inv. Header."No."\\- Purch. Rcpt. Header → Vendor: Purch. Rcpt. Header."Buy-from Vendor No." = Vendor."No."\\- Purch. Rcpt. Line → Item: Purch. Rcpt. Line."No." = Item."No." (when Type=Item)\\\\LEDGER RELATIONSHIPS:\\- Cust. Ledger Entry → Customer: Cust. Ledger Entry."Customer No." = Customer."No." (get customer for ledger entry)\\- Vendor Ledger Entry → Vendor: Vendor Ledger Entry."Vendor No." = Vendor."No." (get vendor for ledger entry)\\- Item Ledger Entry → Item: Item Ledger Entry."Item No." = Item."No." (get item details)\\- Item Ledger Entry → Location: Item Ledger Entry."Location Code" = Location."Code" (get warehouse location)\\- Value Entry → Item Ledger Entry: Value Entry."Item Ledger Entry No." = Item Ledger Entry."Entry No." (get valuation for item movement)\\- Value Entry → Item: Value Entry."Item No." = Item."No."\\- G/L Entry → G/L Account: G/L Entry."G/L Account No." = G/L Account."No." (get account details)\\- Bank Account Ledger Entry → Bank Account: Bank Account Ledger Entry."Bank Account No." = Bank Account."No."\\\\MASTER DATA RELATIONSHIPS:\\- Item → Vendor: Item."Vendor No." = Vendor."No." (get default vendor for item)\\- Item → Location: Join via Item Ledger Entry (items can be in multiple locations)\\- Customer → Salesperson/Purchaser: Customer."Salesperson Code" = Salesperson/Purchaser."Code"\\- Vendor → Salesperson/Purchaser: Vendor."Purchaser Code" = Salesperson/Purchaser."Code"\\\\DIMENSION RELATIONSHIPS:\\- Dimension Value → Dimension: Dimension Value."Dimension Code" = Dimension."Code" (get dimension header)\\- Any table with "Global Dimension 1 Code" → Dimension Value (for first dimension)\\- Any table with "Global Dimension 2 Code" → Dimension Value (for second dimension)\\\\JOIN USAGE EXAMPLES:\\- "sales orders with customer names" → Query Sales Header, already includes "Sell-to Customer Name" field (no join needed)\\- "sales lines with item descriptions" → Query Sales Line, already includes "Description" field\\- "items from vendor X" → Filter Item where "Vendor No." = X\\- "customer ledger entries with customer details" → Query Cust. Ledger Entry, already includes "Customer Name"\\- "GL entries with account names" → Query G/L Entry, already includes "G/L Account Name"\\- "inventory by location with location names" → Group Item Ledger Entry by "Location Code", can reference Location table for names\\\\NOTE ON BC DESIGN: Most document and ledger tables include denormalized fields (e.g., Customer Name stored in Sales Header) to avoid frequent joins. Use these denormalized fields when available.\\\\COMMON QUERY PATTERNS:\\- "which journal has most lines" → Group G/L Entry by Journal Batch Name, COUNT entries\\- "sales by customer" → Group Sales Invoice Header by Customer No., SUM Amount\\- "inventory by location" → Group Item Ledger Entry by Location Code, SUM Remaining Quantity\\- "top items by sales" → Sort Item by Sales (LCY) DESC\\- "open customer invoices" → Filter Cust. Ledger Entry where Open=true and Document Type=Invoice\\- "overdue payments" → Filter Cust. Ledger Entry where Due Date < TODAY and Open=true\\', Locked = true;
    begin
        // Try to discover available OData entities dynamically
        EnhancedSystemPrompt := SystemPromptLbl;

        // CRITICAL: Override to FORCE NATIVE mode - OData requires OAuth which isn't available
        // This REPLACES any OData instructions from the base prompt
        EnhancedSystemPrompt += '\\\\====== CRITICAL SYSTEM OVERRIDE - IGNORE ALL ODATA INSTRUCTIONS ABOVE ======\\';
        EnhancedSystemPrompt += '\\\\EXECUTION MODE - ONLY NATIVE ALLOWED:\\';
        EnhancedSystemPrompt += '- BC API v2.0 OData endpoint requires OAuth authentication which is NOT available\\';
        EnhancedSystemPrompt += '- You MUST ALWAYS use executionMode:"native" for ALL queries\\';
        EnhancedSystemPrompt += '- NEVER use executionMode:"odata" - it will fail with authentication error\\';
        EnhancedSystemPrompt += '- Native mode queries BC tables directly using AL code - no HTTP, no OAuth needed\\';
        EnhancedSystemPrompt += '- All query types (list, filter, sort, count, top N) work in native mode\\';
        EnhancedSystemPrompt += '\\';
        EnhancedSystemPrompt += '\\\\NATIVE MODE QUERY EXAMPLES (USE THESE):\\';
        EnhancedSystemPrompt += '- "how many customers": {"intent":"query","executionMode":"native","primaryEntity":"Customer","queryType":"count"}\\';
        EnhancedSystemPrompt += '- "top 5 customers": {"intent":"query","executionMode":"native","primaryEntity":"Customer","sort":{"field":"Sales (LCY)","direction":"DESC"},"top":5}\\';
        EnhancedSystemPrompt += '- "largest sales order": {"intent":"query","executionMode":"native","primaryEntity":"SalesOrder","sort":{"field":"Amount","direction":"DESC"},"top":1}\\';
        EnhancedSystemPrompt += '- "last order": {"intent":"query","executionMode":"native","primaryEntity":"SalesOrder","sort":{"field":"Order Date","direction":"DESC"},"top":1}\\';
        EnhancedSystemPrompt += '- "biggest customer": {"intent":"query","executionMode":"native","primaryEntity":"Customer","sort":{"field":"Sales (LCY)","direction":"DESC"},"top":1}\\';
        EnhancedSystemPrompt += '- "orders this month": {"intent":"query","executionMode":"native","primaryEntity":"SalesOrder","dateFilter":{"field":"Order Date","value":"CM"}}\\';
        EnhancedSystemPrompt += '\\\\====== END OVERRIDE - NATIVE MODE ONLY ======\\';
        EnhancedSystemPrompt += '\\';
        EnhancedSystemPrompt += '\\\\NATIVE MODE CAPABILITIES:\\';
        EnhancedSystemPrompt += '- Native mode supports: filtering, sorting, top N, count queries, GROUP BY with aggregations\\';
        EnhancedSystemPrompt += '- Native mode does NOT support multi-table joins\\';
        EnhancedSystemPrompt += '- Aggregation functions: COUNT, SUM, AVG, MIN, MAX\\';
        EnhancedSystemPrompt += '- Can group by any field and aggregate on any numeric field\\';
        EnhancedSystemPrompt += '- Results can be sorted by aggregated values (e.g., highest count first)\\';
        EnhancedSystemPrompt += '\\';
        EnhancedSystemPrompt += '\\\\AVOIDING JOINS - USE DENORMALIZED FIELDS:\\';
        EnhancedSystemPrompt += '- BC design includes denormalized data in documents to avoid joins\\';
        EnhancedSystemPrompt += '- Sales Header already contains: Sell-to Customer Name, Bill-to Name, Ship-to Name (no Customer join needed)\\';
        EnhancedSystemPrompt += '- Sales Line already contains: Description (item description copied, no Item join needed)\\';
        EnhancedSystemPrompt += '- Purchase Header already contains: Buy-from Vendor Name, Pay-to Name (no Vendor join needed)\\';
        EnhancedSystemPrompt += '- Cust. Ledger Entry already contains: Customer Name (no Customer join needed)\\';
        EnhancedSystemPrompt += '- Vendor Ledger Entry already contains: Vendor Name (no Vendor join needed)\\';
        EnhancedSystemPrompt += '- G/L Entry already contains: G/L Account Name (no G/L Account join needed)\\';
        EnhancedSystemPrompt += '\\';
        EnhancedSystemPrompt += '\\\\WHEN JOINS ARE TRULY NEEDED:\\';
        EnhancedSystemPrompt += '- Getting additional fields not in the primary table (e.g., Customer."E-Mail" when querying Sales Header)\\';
        EnhancedSystemPrompt += '- Filtering by related table fields (e.g., "orders from London customers" needs Customer.City)\\';
        EnhancedSystemPrompt += '- Cross-referencing data (e.g., "items we never sold" needs Item LEFT JOIN Item Ledger Entry)\\';
        EnhancedSystemPrompt += '\\';
        EnhancedSystemPrompt += '\\\\HANDLING JOIN REQUIREMENTS:\\';
        EnhancedSystemPrompt += '- If query needs data from ONE table only: Use standard native query\\';
        EnhancedSystemPrompt += '- If query asks for denormalized field: Use the field directly, no join needed\\';
        EnhancedSystemPrompt += '- If query REQUIRES true join: Return {"intent":"unsupported","reason":"join","message":"This query requires joining multiple tables which is not yet supported. However, [suggest workaround if possible]"}\\';
        EnhancedSystemPrompt += '\\';
        EnhancedSystemPrompt += '\\\\JOIN WORKAROUND EXAMPLES:\\';
        EnhancedSystemPrompt += '- "sales orders from London customers" → Query Sales Header, filter by "Sell-to City" field (customer city is denormalized)\\';
        EnhancedSystemPrompt += '- "sales orders with customer names" → Query Sales Header, use "Sell-to Customer Name" field (already included)\\';
        EnhancedSystemPrompt += '- "items from vendor Fabrikam" → Query Item, filter by Vendor No. (relationship via foreign key, no join needed)\\';
        EnhancedSystemPrompt += '- "GL entries for account 1000" → Query G/L Entry, filter by "G/L Account No.", use "G/L Account Name" field (denormalized)\\';
        EnhancedSystemPrompt += '\\';
        EnhancedSystemPrompt += '\\\\QUERIES THAT NEED TRUE JOINS (mark as unsupported):\\';
        EnhancedSystemPrompt += '- "customers who never ordered" → Needs Customer LEFT JOIN Sales Header WHERE Sales Header IS NULL\\';
        EnhancedSystemPrompt += '- "items in inventory but never sold" → Needs Item LEFT JOIN Item Ledger Entry\\';
        EnhancedSystemPrompt += '- "orders where customer email contains @contoso" → Needs Sales Header JOIN Customer on customer fields not in Sales Header\\';
        EnhancedSystemPrompt += '\\';
        EnhancedSystemPrompt += '\\\\GROUP BY QUERY SYNTAX:\\';
        EnhancedSystemPrompt += '{"intent":"query","executionMode":"native","primaryEntity":"<entity>","groupBy":["<field>"],"aggregations":[{"function":"COUNT|SUM|AVG|MIN|MAX","field":"<field>","alias":"<name>"}],"sort":{"field":"<aggregation-alias>","direction":"DESC|ASC"},"top":N}\\';
        EnhancedSystemPrompt += '\\';
        EnhancedSystemPrompt += '\\\\GROUP BY EXAMPLES:\\';
        EnhancedSystemPrompt += '- "which GL journal has most lines": {"intent":"query","executionMode":"native","primaryEntity":"G/L Entry","groupBy":["Journal Batch Name"],"aggregations":[{"function":"COUNT","field":"*","alias":"lineCount"}],"sort":{"field":"lineCount","direction":"DESC"},"top":1}\\';
        EnhancedSystemPrompt += '- "sales by customer": {"intent":"query","executionMode":"native","primaryEntity":"SalesInvoice","groupBy":["Sell-to Customer No."],"aggregations":[{"function":"SUM","field":"Amount Including VAT","alias":"totalSales"}],"sort":{"field":"totalSales","direction":"DESC"},"top":10}\\';
        EnhancedSystemPrompt += '- "which customer has most orders": {"intent":"query","executionMode":"native","primaryEntity":"SalesOrder","groupBy":["Sell-to Customer No."],"aggregations":[{"function":"COUNT","field":"*","alias":"orderCount"}],"sort":{"field":"orderCount","direction":"DESC"},"top":1}\\';
        EnhancedSystemPrompt += '- "average order value by customer": {"intent":"query","executionMode":"native","primaryEntity":"SalesOrder","groupBy":["Sell-to Customer No."],"aggregations":[{"function":"AVG","field":"Amount","alias":"avgOrder"}],"sort":{"field":"avgOrder","direction":"DESC"},"top":10}\\';
        EnhancedSystemPrompt += '- "total purchases by vendor": {"intent":"query","executionMode":"native","primaryEntity":"PurchaseOrder","groupBy":["Buy-from Vendor No."],"aggregations":[{"function":"SUM","field":"Amount","alias":"totalPurchases"}],"sort":{"field":"totalPurchases","direction":"DESC"},"top":10}\\';
        EnhancedSystemPrompt += '- "how many items per category": {"intent":"query","executionMode":"native","primaryEntity":"Item","groupBy":["Item Category Code"],"aggregations":[{"function":"COUNT","field":"*","alias":"itemCount"}],"sort":{"field":"itemCount","direction":"DESC"}}\\';
        EnhancedSystemPrompt += '\\';
        EnhancedSystemPrompt += '\\\\AGGREGATION RULES:\\';
        EnhancedSystemPrompt += '- COUNT function: Use field:"*" to count records\\';
        EnhancedSystemPrompt += '- SUM/AVG/MIN/MAX: Use actual field name (must be numeric)\\';
        EnhancedSystemPrompt += '- Alias is used for sorting and in response text\\';
        EnhancedSystemPrompt += '- "which X has most Y" → groupBy X, COUNT Y, sort DESC, top:1\\';
        EnhancedSystemPrompt += '- "total X by Y" → groupBy Y, SUM X field\\';
        EnhancedSystemPrompt += '- "average X by Y" → groupBy Y, AVG X field\\';

        // Strengthen entity selection to avoid mis-routing queries (e.g., inventory questions going to customers)
        EnhancedSystemPrompt += '\\ENTITY SELECTION RULES:\\';
        EnhancedSystemPrompt += '- Choose entity from user nouns. Do NOT default to Customer unless the question clearly mentions customer/client/account.\\';
        EnhancedSystemPrompt += '- Inventory/stock/quantity/warehouse/parts/products/items → use ItemLedgerEntry (sum Remaining_Quantity/Quantity) — never Customer or Item inventory field directly.\\';
        EnhancedSystemPrompt += '- Locations/warehouses/facilities/sites → use Location entity ONLY. Never route to Customer.\\';
        EnhancedSystemPrompt += '- "How many" / "total" / "sum" for inventory → aggregate on ItemLedgerEntry (Remaining_Quantity or Quantity), not Item table.\\';
        EnhancedSystemPrompt += '- "How many locations" / "how many warehouses" / "how many facilities" → COUNT Location records ONLY. Not customers.\\';
        EnhancedSystemPrompt += '- Financial balances/AR/AP → Customer or Vendor as appropriate.\\';
        EnhancedSystemPrompt += '- If the noun is ambiguous, prefer the closest matching entity (inventory → Item/ItemLedgerEntry, locations → Location, orders → SalesOrder, purchase orders → PurchaseOrder, invoices → SalesInvoice).\\';

        // Add focused location examples to prevent misrouting
        EnhancedSystemPrompt += '\\LOCATIONS & WAREHOUSE EXAMPLES:\\';
        EnhancedSystemPrompt += '"How many locations do we have" → {"intent":"query","executionMode":"odata","odata":{"entity":"ODataV4/Company(''COMPANY'')/Locations","query":"$count=true","resultType":"count"},"responseTemplate":"There are {count} locations"}\\Reasoning: "How many locations" = COUNT Location entity via ODataV4 custom service, never customers.\\';
        EnhancedSystemPrompt += '"How many warehouses do we have" → {"intent":"query","executionMode":"odata","odata":{"entity":"ODataV4/Company(''COMPANY'')/Locations","query":"$count=true","resultType":"count"},"responseTemplate":"There are {count} warehouses"}\\Reasoning: "Warehouses" is synonym for locations; use Location entity via ODataV4.\\';
        EnhancedSystemPrompt += '"Show all locations" → {"intent":"query","executionMode":"odata","odata":{"entity":"ODataV4/Company(''COMPANY'')/Locations","query":"$top=50","resultType":"array"},"responseTemplate":"Locations"}\\Reasoning: List Location records via ODataV4 custom service.\\';
        EnhancedSystemPrompt += '"List locations with stock" → {"intent":"query","executionMode":"odata","odata":{"entity":"ODataV4/Company(''COMPANY'')/Locations","query":"$top=50","resultType":"array"},"responseTemplate":"Locations"}\\Reasoning: List Location records; filtering for stock would need additional logic.\\';
        EnhancedSystemPrompt += '"Which facilities do we have" → {"intent":"query","executionMode":"odata","odata":{"entity":"ODataV4/Company(''COMPANY'')/Locations","query":"$top=50","resultType":"array"},"responseTemplate":"Facilities"}\\Reasoning: "Facilities" = locations; use Location entity via ODataV4.\\';
        EnhancedSystemPrompt += '\\CRITICAL: Location entity uses custom ODataV4 endpoint: ODataV4/Company(''COMPANY'')/Locations (capital L)\\';
        EnhancedSystemPrompt += 'NOT available at standard api/v2.0 endpoint. Always use ODataV4 path for Location queries.\\';
        EnhancedSystemPrompt += 'For $count queries, use resultType:"count" and the response will have @odata.count property.\\';
        EnhancedSystemPrompt += '\\SUPERLATIVE QUERIES (biggest, largest, most expensive, highest):\\';
        EnhancedSystemPrompt += '"What''s the biggest sales order" → {"intent":"query","executionMode":"odata","odata":{"entity":"companies(COMPANY)/salesOrder","query":"$orderby=Amount desc&$top=1&$select=No,Sell_to_Customer_No,Amount,Order_Date","resultType":"single"},"responseTemplate":"Biggest sales order is {No} for {Amount} on {Order_Date}"}\\Reasoning: "Biggest" = highest amount, sort by Amount DESC, take top 1.\\';
        EnhancedSystemPrompt += '"Largest invoice" → {"intent":"query","executionMode":"odata","odata":{"entity":"companies(COMPANY)/salesInvoice","query":"$orderby=Amount_Including_VAT desc&$top=1","resultType":"single"},"responseTemplate":"Largest invoice: {No} for {Amount_Including_VAT}"}\\Reasoning: Superlative = top 1 sorted by value DESC.\\';
        EnhancedSystemPrompt += '"Most expensive item" → {"intent":"query","executionMode":"odata","odata":{"entity":"companies(COMPANY)/item","query":"$orderby=Unit_Price desc&$top=1","resultType":"single"},"responseTemplate":"Most expensive item: {Description} at {Unit_Price}"}\\Reasoning: Sort by price descending, take 1.\\';
        EnhancedSystemPrompt += '"Customer with highest balance" → {"intent":"query","executionMode":"odata","odata":{"entity":"companies(COMPANY)/customer","query":"$orderby=Balance_LCY desc&$top=1","resultType":"single"},"responseTemplate":"Customer with highest balance: {Name} ({Balance_LCY})"}\\Reasoning: Superlative query needs $top=1 and DESC sort.\\';
        EnhancedSystemPrompt += 'CRITICAL: "biggest", "largest", "highest", "most expensive" ALL require $orderby DESC and $top=1. Never return multiple records.\\';
        EnhancedSystemPrompt += 'Use resultType:"single" for superlatives (not "array") to indicate expecting one record.\\';

        // Add examples for standard BC ledger and posted document tables
        EnhancedSystemPrompt += '\\\\STANDARD BC TABLES - SALES DOCUMENTS (via Posted Ledgers):\\';
        EnhancedSystemPrompt += '"Show all sales invoices" → {"intent":"query","executionMode":"native","primaryEntity":"SalesInvoice","top":50}\\Reasoning: Use table 112 (Sales Invoice Header) - standard BC posted sales document.\\';
        EnhancedSystemPrompt += '"Unpaid sales invoices" → {"intent":"query","executionMode":"native","primaryEntity":"SalesInvoice","filters":[{"field":"Outstanding_Amount","operator":">","value":"0"}],"top":50}\\Reasoning: Query Sales Invoice Header (table 112) filtering Outstanding_Amount > 0.\\';
        EnhancedSystemPrompt += '"Total sales this month" → {"intent":"query","executionMode":"odata","odata":{"entity":"companies(COMPANY)/salesInvoiceHeader","query":"$apply=aggregate(Amount_Including_VAT with sum as Total)","resultType":"aggregation"},"responseTemplate":"Total sales this month is {value}"}\\Reasoning: Aggregate SUM on table 112.\\';
        EnhancedSystemPrompt += '"Top customers by revenue" → {"intent":"query","executionMode":"odata","odata":{"entity":"companies(COMPANY)/salesInvoiceHeader","query":"$apply=groupby((Sell_to_Customer_No),aggregate(Amount_Including_VAT with sum as Revenue))&$orderby=Revenue desc&$top=10","resultType":"array"},"responseTemplate":"Top customers by revenue"}\\Reasoning: Groupby customer on Sales Invoice Header.\\';

        EnhancedSystemPrompt += '\\\\STANDARD BC TABLES - PURCHASE DOCUMENTS:\\';
        EnhancedSystemPrompt += '"Show all purchase invoices" → {"intent":"query","executionMode":"native","primaryEntity":"PurchaseInvoice","top":50}\\Reasoning: Use table 122 (Purch. Inv. Header) - standard BC posted purchase document.\\';
        EnhancedSystemPrompt += '"Amount due to vendors" → {"intent":"query","executionMode":"odata","odata":{"entity":"companies(COMPANY)/purchaseInvoiceHeader","query":"$apply=aggregate(Amount_Including_VAT with sum as TotalDue)","resultType":"aggregation"},"responseTemplate":"Total amount due is {value}"}\\Reasoning: Sum table 122 Amount_Including_VAT.\\';
        EnhancedSystemPrompt += '"Overdue purchase invoices" → {"intent":"query","executionMode":"native","primaryEntity":"PurchaseInvoice","filters":[{"field":"Due_Date","operator":"<","value":"TODAY"}],"top":50}\\Reasoning: Filter table 122 by Due_Date < today.\\';

        EnhancedSystemPrompt += '\\\\STANDARD BC TABLES - LEDGER ENTRIES:\\';
        EnhancedSystemPrompt += '"Customer outstanding amounts" → {"intent":"query","executionMode":"odata","odata":{"entity":"companies(COMPANY)/custLedgerEntry","query":"$filter=Open eq true","resultType":"array"},"responseTemplate":"Open customer ledger entries"}\\Reasoning: Query table 21 (Cust. Ledger Entry) with Open=true filter.\\';
        EnhancedSystemPrompt += '"Total vendor payables" → {"intent":"query","executionMode":"odata","odata":{"entity":"companies(COMPANY)/vendorLedgerEntry","query":"$apply=aggregate(Amount with sum as Total)&$filter=Open eq true","resultType":"aggregation"},"responseTemplate":"Total vendor payables: {value}"}\\Reasoning: Sum table 25 (Vendor Ledger Entry) for open entries.\\';
        EnhancedSystemPrompt += '"Item ledger transactions" → {"intent":"query","executionMode":"native","primaryEntity":"ItemLedgerEntry","dateFilter":{"field":"Posting_Date","value":"CM"},"top":100}\\Reasoning: Query table 32 (Item Ledger Entry) for current month.\\';
        EnhancedSystemPrompt += '"G/L account balance" → {"intent":"query","executionMode":"odata","odata":{"entity":"companies(COMPANY)/glEntry","query":"$filter=G_L_Account_No eq ''1000''&$apply=aggregate(Amount with sum as Balance)","resultType":"aggregation"},"responseTemplate":"Account balance: {value}"}\\Reasoning: Sum table 17 (G/L Entry) by account number.\\';

        EnhancedSystemPrompt += '\\\\STANDARD BC TABLES - MASTER DATA:\\';
        EnhancedSystemPrompt += '"Top customers by sales" → {"intent":"query","executionMode":"native","primaryEntity":"Customer","sort":{"field":"Sales (LCY)","direction":"DESC"},"top":10}\\Reasoning: Query table 18 (Customer) sorted by Sales_LCY.\\';
        EnhancedSystemPrompt += '"Vendors in London" → {"intent":"query","executionMode":"native","primaryEntity":"Vendor","filters":[{"field":"City","operator":"=","value":"London"}],"top":50}\\Reasoning: Query table 23 (Vendor) with City filter.\\';
        EnhancedSystemPrompt += '"Items with low stock" → {"intent":"query","executionMode":"native","primaryEntity":"Item","filters":[{"field":"Inventory","operator":"<","value":"100"}],"top":50}\\Reasoning: Query table 27 (Item) with Inventory < 100.\\';
        EnhancedSystemPrompt += '"All warehouse locations" → {"intent":"query","executionMode":"native","primaryEntity":"Location","top":50}\\Reasoning: Query table 13 (Location) - all warehouse records.\\';

        // Add critical examples for "last/latest" queries
        EnhancedSystemPrompt += '\\\\CRITICAL: "LAST" AND "LATEST" QUERIES:\\';
        EnhancedSystemPrompt += '- "last order", "latest order", "most recent order" → sort by Order_Date DESC, top 1\\';
        EnhancedSystemPrompt += '- "last sales order", "last sales order in the system" → {"primaryEntity":"SalesOrder","sort":{"field":"Order_Date","direction":"DESC"},"top":1}\\';
        EnhancedSystemPrompt += '- "last purchase order", "last purchase order I created" → {"primaryEntity":"PurchaseOrder","sort":{"field":"Order_Date","direction":"DESC"},"top":1}\\';
        EnhancedSystemPrompt += '- "latest invoice" → {"primaryEntity":"SalesInvoice","sort":{"field":"Posting_Date","direction":"DESC"},"top":1}\\';
        EnhancedSystemPrompt += '- "most recent customer" → {"primaryEntity":"Customer","sort":{"field":"No.","direction":"DESC"},"top":1}\\';
        EnhancedSystemPrompt += '- When user asks for "THE last" or "THE latest" or "most recent" → ALWAYS set top:1 and sort by relevant date field DESC\\';

        // Add comprehensive schema context
        EnhancedSystemPrompt += '\\\\' + GetSchemaContext();

        // Add instructions for using published web services
        EnhancedSystemPrompt += '\\\\USING PUBLISHED WEB SERVICES:\\';
        EnhancedSystemPrompt += 'The schema above includes PUBLISHED WEB SERVICES with actual field names.\\';
        EnhancedSystemPrompt += 'When a query matches a published service, USE IT with the ODataV4/ path shown.\\';
        EnhancedSystemPrompt += 'Example: If schema shows "Service: Power_BI_Purchase_Hdr_Vendor" with fields "No, Item_No, Vendor_No"\\';
        EnhancedSystemPrompt += 'Then for "purchase orders with vendors" use:';
        EnhancedSystemPrompt += ' {"intent":"query","executionMode":"odata","odata":{"entity":"ODataV4/Power_BI_Purchase_Hdr_Vendor","query":"$top=50&$select=No,Item_No,Vendor_No,Name","resultType":"array"}}\\';
        EnhancedSystemPrompt += 'CRITICAL: ODataV4/ paths do NOT use Company() segment - just "ODataV4/ServiceName"\\';
        EnhancedSystemPrompt += 'Standard API paths still use companies(COMPANY)/ prefix.\\';
        EnhancedSystemPrompt += 'Published web services often provide pre-joined data (e.g., orders WITH vendor/customer details already joined).\\';
        EnhancedSystemPrompt += 'Check the published services schema first - if it has the fields you need, use it!\\';

        SystemMessage.Add('role', 'system');
        SystemMessage.Add('content', EnhancedSystemPrompt);

        UserMessage.Add('role', 'user');
        UserMessage.Add('content', QueryText);

        MessagesArray.Add(SystemMessage);
        MessagesArray.Add(UserMessage);

        MaxTokens := Setup."Max Tokens";
        if MaxTokens = 0 then
            MaxTokens := 500;

        RequestJson.Add('model', GetModelName());
        RequestJson.Add('messages', MessagesArray);
        RequestJson.Add('temperature', 0.2);
        RequestJson.Add('max_tokens', MaxTokens);

        // Enable prompt caching for Azure OpenAI
        // System prompt (with schema) will be cached and reused across queries
        // Saves ~90% of system prompt tokens on subsequent requests
        RequestJson.Add('seed', 42); // Deterministic responses + enables caching

        exit(RequestJson);
    end;

    local procedure GetModelName(): Text
    begin
        if Setup."Model Name" <> '' then
            exit(Setup."Model Name");

        case Setup."AI Backend Type" of
            Setup."AI Backend Type"::LocalLLM:
                exit('gpt-3.5-turbo');
            Setup."AI Backend Type"::AzureOpenAI:
                exit('gpt-4o');
            Setup."AI Backend Type"::OpenAI:
                exit('gpt-4o-mini');
            else
                exit('gpt-4o-mini');
        end;
    end;

    local procedure GetSchemaContext(): Text
    var
        SchemaContext: Codeunit "NXR Schema Context";
    begin
        exit(SchemaContext.GetSchemaContext());
    end;

    local procedure ParseAIResponse(ResponseJson: JsonObject; var Intent: Record "NXR Voice Query Intent" temporary): Boolean
    var
        ChoicesToken: JsonToken;
        ChoicesArray: JsonArray;
        FirstChoice: JsonToken;
        MessageToken: JsonToken;
        ContentToken: JsonToken;
        ContentText: Text;
        IntentJson: JsonObject;
        EntityToken: JsonToken;
        TopNToken: JsonToken;
        SpecificFilterToken: JsonToken;
        FullStructuredQueryTxt: Text;
    begin
        if not ResponseJson.Get('choices', ChoicesToken) then
            exit(false);

        ChoicesArray := ChoicesToken.AsArray();
        if not ChoicesArray.Get(0, FirstChoice) then
            exit(false);

        if not FirstChoice.AsObject().Get('message', MessageToken) then
            exit(false);

        if not MessageToken.AsObject().Get('content', ContentToken) then
            exit(false);

        ContentText := ContentToken.AsValue().AsText();

        // Clean up response (remove markdown code blocks if present)
        ContentText := CleanJsonResponse(ContentText);

        if not IntentJson.ReadFrom(ContentText) then
            exit(false);

        Intent.Init();
        Intent."Query Text" := '';

        if IntentJson.Get('primaryEntity', EntityToken) then
            MapEntityFromText(EntityToken.AsValue().AsText(), Intent)
        else if IntentJson.Get('entity', EntityToken) then
            MapEntityFromText(EntityToken.AsValue().AsText(), Intent);

        if IntentJson.Get('top', TopNToken) then
            Intent."Top N" := TopNToken.AsValue().AsInteger()
        else if IntentJson.Get('topN', TopNToken) then
            Intent."Top N" := TopNToken.AsValue().AsInteger();

        if IntentJson.Get('specificFilter', SpecificFilterToken) then
            Intent."Specific Filter" := SpecificFilterToken.AsValue().AsText();

        // CRITICAL FIX: Store the FULL structured query JSON for the query executor
        // The query executor needs filters, linkedEntity, dateFilter, sort - not just entity and top!
        IntentJson.WriteTo(FullStructuredQueryTxt);
        Intent."Structured Data" := CopyStr(FullStructuredQueryTxt, 1, MaxStrLen(Intent."Structured Data"));

        exit(true);
    end;

    local procedure CleanJsonResponse(ResponseText: Text): Text
    var
        StartPos: Integer;
        EndPos: Integer;
    begin
        // Remove markdown code blocks
        if ResponseText.Contains('```json') then begin
            StartPos := ResponseText.IndexOf('```json') + 7;
            EndPos := ResponseText.LastIndexOf('```');
            if (StartPos > 0) and (EndPos > StartPos) then
                ResponseText := ResponseText.Substring(StartPos, EndPos - StartPos);
        end else if ResponseText.Contains('```') then begin
            StartPos := ResponseText.IndexOf('```') + 3;
            EndPos := ResponseText.LastIndexOf('```');
            if (StartPos > 0) and (EndPos > StartPos) then
                ResponseText := ResponseText.Substring(StartPos, EndPos - StartPos);
        end;

        exit(ResponseText.Trim());
    end;

    local procedure MapEntityFromText(EntityText: Text; var Intent: Record "NXR Voice Query Intent" temporary)
    var
        EntityLower: Text;
    begin
        EntityLower := LowerCase(EntityText);
        // Remove spaces and handle variations
        EntityLower := EntityLower.Replace(' ', '');

        case EntityLower of
            // Master Data
            'customer':
                Intent.Entity := Intent.Entity::Customer;
            'contact':
                Intent.Entity := Intent.Entity::Contact;
            'salesperson':
                Intent.Entity := Intent.Entity::Salesperson;
            'item':
                Intent.Entity := Intent.Entity::Item;
            'itemcategory':
                Intent.Entity := Intent.Entity::ItemCategory;
            'vendor':
                Intent.Entity := Intent.Entity::Vendor;
            'purchaser':
                Intent.Entity := Intent.Entity::Purchaser;
            'employee':
                Intent.Entity := Intent.Entity::Employee;
            'location':
                Intent.Entity := Intent.Entity::Location;
            'resource':
                Intent.Entity := Intent.Entity::Resource;
            'glaccount', 'gaccount':
                Intent.Entity := Intent.Entity::GLAccount;
            'bankaccount':
                Intent.Entity := Intent.Entity::BankAccount;
            'currency':
                Intent.Entity := Intent.Entity::Currency;
            'paymentterms':
                Intent.Entity := Intent.Entity::PaymentTerms;
            'paymentmethod':
                Intent.Entity := Intent.Entity::PaymentMethod;
            'fixedasset':
                Intent.Entity := Intent.Entity::FixedAsset;
            'shipmentmethod':
                Intent.Entity := Intent.Entity::ShipmentMethod;
            'shippingagent':
                Intent.Entity := Intent.Entity::ShippingAgent;
            'countryregion', 'country':
                Intent.Entity := Intent.Entity::CountryRegion;

            // Sales Documents
            'salesorder':
                Intent.Entity := Intent.Entity::SalesOrder;
            'salesinvoice':
                Intent.Entity := Intent.Entity::SalesInvoice;
            'salesquote':
                Intent.Entity := Intent.Entity::SalesQuote;
            'salesshipment', 'salesshipments':
                Intent.Entity := Intent.Entity::SalesShipment;
            'salescreditmemo':
                Intent.Entity := Intent.Entity::SalesCreditMemo;
            'salesreturnorder':
                Intent.Entity := Intent.Entity::SalesReturnOrder;
            'salesinvoiceheader', 'salesi nvoiceheaders':
                Intent.Entity := Intent.Entity::SalesInvoice;

            // Purchase Documents
            'purchaseorder':
                Intent.Entity := Intent.Entity::PurchaseOrder;
            'purchasequote':
                Intent.Entity := Intent.Entity::PurchaseQuote;
            'purchaseinvoice':
                Intent.Entity := Intent.Entity::PurchaseInvoice;
            'purchasereceipt', 'purchasereceipts':
                Intent.Entity := Intent.Entity::PurchaseReceipt;
            'purchasecreditmemo':
                Intent.Entity := Intent.Entity::PurchaseCreditMemo;
            'purchasereturnorder':
                Intent.Entity := Intent.Entity::PurchaseReturnOrder;
            // Ledger Entries
            'itemledgerentry', 'itemledgerentries':
                Intent.Entity := Intent.Entity::ItemLedgerEntry;
            'customerledgerentry', 'customerledgerentries':
                Intent.Entity := Intent.Entity::CustomerLedgerEntry;
            'vendorledgerentry', 'vendorledgerentries':
                Intent.Entity := Intent.Entity::VendorLedgerEntry;
            'glentry', 'glentries', 'generalledgerentry', 'generalledgerentries':
                Intent.Entity := Intent.Entity::GLEntry;
            'valueentry', 'valueentries':
                Intent.Entity := Intent.Entity::ValueEntry;
            'bankaccountledgerentry', 'bankaccountledgerentries':
                Intent.Entity := Intent.Entity::BankAccountLedgerEntry;

            // Transfer Orders
            'transferorder', 'transferorders':
                Intent.Entity := Intent.Entity::TransferOrder;

            // Production & Assembly
            'productionorder', 'productionorders':
                Intent.Entity := Intent.Entity::ProductionOrder;
            'assemblyorder', 'assemblyorders':
                Intent.Entity := Intent.Entity::AssemblyOrder;

            // Service
            'serviceorder':
                Intent.Entity := Intent.Entity::ServiceOrder;

            // Jobs
            'job', 'jobs':
                Intent.Entity := Intent.Entity::Job;
            'jobtask':
                Intent.Entity := Intent.Entity::JobTask;
            'jobplanningline', 'jobplanninglines':
                Intent.Entity := Intent.Entity::JobPlanningLine;
            'jobledgerentry', 'jobledgerentries':
                Intent.Entity := Intent.Entity::JobLedgerEntry;
        end;
    end;

    local procedure BuildOpenAIRequestWithHistory(QueryText: Text; ConversationHistory: JsonArray): JsonObject
    var
        RequestJson: JsonObject;
        MessagesArray: JsonArray;
        SystemMessage: JsonObject;
        UserMessage: JsonObject;
        HistoryToken: JsonToken;
        i: Integer;
        EnhancedSystemPrompt: Text;
    begin
        EnhancedSystemPrompt := GetSystemPrompt();

        // Add system message
        SystemMessage.Add('role', 'system');
        SystemMessage.Add('content', EnhancedSystemPrompt);
        MessagesArray.Add(SystemMessage);

        // Add conversation history (up to last 10 messages)
        for i := 0 to ConversationHistory.Count() - 1 do begin
            if ConversationHistory.Get(i, HistoryToken) then
                MessagesArray.Add(HistoryToken);
        end;

        // Add current user message
        UserMessage.Add('role', 'user');
        UserMessage.Add('content', QueryText);
        MessagesArray.Add(UserMessage);

        RequestJson.Add('messages', MessagesArray);
        RequestJson.Add('temperature', 0.1);
        RequestJson.Add('max_tokens', 2000);

        exit(RequestJson);
    end;

    local procedure BuildFollowUpRequest(PromptText: Text; ConversationHistory: JsonArray; var RequestJson: JsonObject)
    var
        MessagesArray: JsonArray;
        SystemMessage: JsonObject;
        UserMessage: JsonObject;
        HistoryToken: JsonToken;
        i: Integer;
    begin
        // Simple system message for follow-up generation
        SystemMessage.Add('role', 'system');
        SystemMessage.Add('content', 'You are a helpful assistant that suggests relevant follow-up questions.');
        MessagesArray.Add(SystemMessage);

        // Include limited history for context (last 4 messages = 2 exchanges)
        if ConversationHistory.Count() > 4 then
            i := ConversationHistory.Count() - 4
        else
            i := 0;

        while i < ConversationHistory.Count() do begin
            if ConversationHistory.Get(i, HistoryToken) then
                MessagesArray.Add(HistoryToken);
            i += 1;
        end;

        // Add follow-up generation prompt
        UserMessage.Add('role', 'user');
        UserMessage.Add('content', PromptText);
        MessagesArray.Add(UserMessage);

        RequestJson.Add('messages', MessagesArray);
        RequestJson.Add('temperature', 0.7);  // Higher temperature for creative suggestions
        RequestJson.Add('max_tokens', 150);
    end;

    local procedure PrepareRequestFromJson(var RequestContent: HttpContent; RequestJson: JsonObject)
    var
        ContentHeaders: HttpHeaders;
        RequestText: Text;
    begin
        RequestJson.WriteTo(RequestText);
        RequestContent.WriteFrom(RequestText);
        AddContentTypeHeader(RequestContent);
    end;

    local procedure AddContentTypeHeader(var RequestContent: HttpContent)
    var
        ContentHeaders: HttpHeaders;
    begin
        RequestContent.GetHeaders(ContentHeaders);
        ContentHeaders.Clear();
        ContentHeaders.Add('Content-Type', 'application/json');
    end;

    local procedure ExtractFollowUpText(ResponseJson: JsonObject): Text
    var
        ChoicesToken: JsonToken;
        ChoicesArray: JsonArray;
        FirstChoiceToken: JsonToken;
        FirstChoice: JsonObject;
        MessageToken: JsonToken;
        MessageObj: JsonObject;
        ContentToken: JsonToken;
    begin
        if not ResponseJson.Get('choices', ChoicesToken) then
            exit('');

        ChoicesArray := ChoicesToken.AsArray();
        if not ChoicesArray.Get(0, FirstChoiceToken) then
            exit('');

        FirstChoice := FirstChoiceToken.AsObject();
        if not FirstChoice.Get('message', MessageToken) then
            exit('');

        MessageObj := MessageToken.AsObject();
        if not MessageObj.Get('content', ContentToken) then
            exit('');

        exit(ContentToken.AsValue().AsText());
    end;

    local procedure GetSystemPrompt(): Text
    var
        SystemPromptLbl: Label 'You are a Business Central query analyzer. Parse natural language into structured queries. Prefer single-table queries. Use native mode for all queries.', Locked = true;
    begin
        // Simplified for history calls - full prompt already in first message
        exit(SystemPromptLbl);
    end;
}
