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
        DebugInfo: Text;
    begin
        exit(AnalyzeQueryWithAIDebug(QueryText, Intent, DebugInfo));
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
        SystemPromptLbl: Label 'You are a Business Central query analyzer. Your job is to interpret natural language business questions and translate them into structured read-only database queries that return sensible, meaningful results.\\\\KEY PRINCIPLES:\\- Understand business intent, not just literal words\\- "Top customers" means highest sales volume, not first records\\- "Best" means highest value/performance metric\\- Choose appropriate sorting to make results meaningful\\- Always return read-only queries (SELECT, no INSERT/UPDATE/DELETE)\\- ALWAYS extract numbers from queries, whether written as digits (5, 10) or words (five, ten, three)\\\\NUMBER PARSING:\\- "five" → 5, "ten" → 10, "three" → 3, etc.\\- "top five", "top 5", "best 5", "give me 5" all mean "top": 5\\- If no number specified but query says "top/best/biggest", default to 10\\\\FILTER CONSTRUCTION RULES:\\1. Use EXACT field names from schema (case-sensitive for OData)\\2. Empty strings: Use '''' (two single quotes) NOT null or empty\\3. Null checks: Use IS NULL or IS NOT NULL, never = null\\4. Text filters: Use single quotes - City eq ''London''\\5. Number filters: No quotes - Balance_LCY gt 1000\\6. Combine filters with AND/OR - City eq ''London'' and Balance_LCY gt 1000\\7. Partial text match (OData): Use contains(Name,''text'') or startswith(Name,''text'')\\8. Partial text match (Native): Use filter with wildcards - Name LIKE ''%text%''\\\\DATE FILTER SYNTAX (Business Central):\\- Today: T or 0D (zero days from today)\\- Yesterday: -1D (one day before today)\\- Tomorrow: 1D (one day after today)\\- This week: CW (current week)\\- This month: CM (current month)\\- This year: CY (current year)\\- Last 7 days: -7D..0D or T-7D..T\\- Last 30 days: -30D..0D or T-30D..T\\- Next 30 days: 0D..30D or T..T+30D\\- Specific date: 2024-01-15 (YYYY-MM-DD format)\\- Date range: 2024-01-01..2024-12-31\\- From date onwards: 2024-01-01.. (no end date)\\- Up to date: ..2024-12-31 (no start date)\\\\DATE QUERY EXAMPLES:\\- "this year" → dateFilter: {"field":"Order_Date","value":"CY"}\\- "this month" → dateFilter: {"field":"Posting_Date","value":"CM"}\\- "today" → dateFilter: {"field":"Order_Date","value":"T"}\\- "yesterday" → dateFilter: {"field":"Order_Date","value":"-1D"}\\- "last 7 days" → dateFilter: {"field":"Order_Date","value":"T-7D..T"}\\- "last month" → dateFilter: {"field":"Order_Date","value":"CM-1"} or calculate range\\- "next week" → dateFilter: {"field":"Order_Date","value":"CW+1"}\\\\NULL vs EMPTY STRING:\\- Database NULL: Field has no value, use "IS NULL" check\\- Empty string '''': Field has empty text value, use = ''''\\- In JSON output: Use null for NULL, "" for empty string\\- NEVER use null in filter values - use IS NULL operator instead\\- Example: {"field":"City","operator":"IS NULL"} NOT {"field":"City","value":null}\\\\EXECUTION MODES:\\1. NATIVE MODE (default): For simple queries, use standard BC table queries\\2. ODATA MODE: For aggregations (SUM, AVG, COUNT), complex joins, or grouping\\\\SCHEMA REFERENCE (Native & OData):\\Customer: No. (Code20), Name (Text100), Balance_LCY/Balance (LCY) (Decimal), Sales_LCY/Sales (LCY) (Decimal), City (Text30), Country_Region_Code (Code10)\\Item: No. (Code20), Description (Text100), Inventory (Decimal), Unit_Price/Unit Price (Decimal), Unit_Cost (Decimal), Item_Category_Code (Code20), Base_Unit_of_Measure (Code10)\\Vendor: No. (Code20), Name (Text100), Balance_LCY/Balance (LCY) (Decimal), City (Text30), Country_Region_Code (Code10)\\Employee: No. (Code20), First_Name (Text30), Last_Name (Text30), Job_Title (Text30), E_Mail (Text80)\\SalesOrder: No. (Code20), Sell_to_Customer_No. (Code20), Order_Date (Date), Status (Open|Released), Amount (Decimal)\\SalesOrderLine: Document_No. (Code20), Line_No. (Integer), Item_No. (Code20), Description (Text100), Quantity (Decimal), Unit_Price (Decimal), Amount (Decimal)\\SalesInvoice: No. (Code20), Posting_Date (Date), Amount_Including_VAT (Decimal), Sell_to_Customer_No. (Code20)\\PurchaseOrder: No. (Code20), Buy_from_Vendor_No. (Code20), Order_Date (Date), Status (Open|Released), Amount (Decimal)\\PurchaseOrderLine: Document_No. (Code20), Line_No. (Integer), Item_No. (Code20), Description (Text100), Quantity (Decimal), Direct_Unit_Cost (Decimal), Amount (Decimal)\\ServiceOrder: No. (Code20), Customer_No. (Code20), Order_Date (Date), Status (Open|Released), Amount (Decimal)\\ServiceOrderLine: Document_No. (Code20), Line_No. (Integer), Item_No. (Code20), Description (Text100), Quantity (Decimal)\\Location: Code (Code10), Name (Text100), Use_As_In_Transit (Boolean)\\ItemLedgerEntry: Entry_No. (Integer), Item_No. (Code20), Location_Code (Code10), Quantity (Decimal), Remaining_Quantity (Decimal), Posting_Date (Date), Entry_Type (Purchase|Sale|Transfer)\\GeneralLedgerEntry: Entry_No. (Integer), G_L_Account_No. (Code20), Posting_Date (Date), Amount (Decimal), Description (Text100)\\CustomerLedgerEntry: Entry_No. (Integer), Customer_No. (Code20), Posting_Date (Date), Document_Type (Invoice|Payment|Credit Memo), Amount (Decimal), Remaining_Amount (Decimal)\\VendorLedgerEntry: Entry_No. (Integer), Vendor_No. (Code20), Posting_Date (Date), Document_Type (Invoice|Payment|Credit Memo), Amount (Decimal), Remaining_Amount (Decimal)\\\\LOCATION QUERIES (for inventory management):\\- "locations with stock" → Query Location table, filter where there are ItemLedgerEntry records with Remaining_Quantity > 0\\- "how many locations" → Count Location records\\- "which warehouses" → List Location records (warehouse is a synonym for location)\\\\ODATA ENTITIES (for advanced queries):\\- companies(COMPANY)/customer\\- companies(COMPANY)/vendor\\- companies(COMPANY)/item\\- companies(COMPANY)/salesOrder\\- companies(COMPANY)/salesOrderLine\\- companies(COMPANY)/salesInvoice\\- companies(COMPANY)/purchaseOrder\\- companies(COMPANY)/purchaseOrderLine\\- companies(COMPANY)/employee\\- companies(COMPANY)/location\\Note: Use SINGULAR names (customer, vendor, item) - BC API v2.0 convention\\\\ODATA SYNTAX:\\- Filter: $filter=City eq ''London'' and Balance_LCY gt 1000\\- Date filter: $filter=Order_Date ge 2024-01-01 and Order_Date le 2024-12-31\\- Sort: $orderby=Balance_LCY desc\\- Top: $top=10\\- Select: $select=No,Name,City\\- Aggregate: $apply=aggregate(Balance_LCY with sum as TotalBalance)\\- Group: $apply=groupby((City),aggregate(Sales_LCY with sum as CityTotal))\\- Contains: $filter=contains(Name,''text'')\\- Null check: $filter=City ne null\\\\NATIVE MODE EXAMPLES:\\"Top 10 customers" → {"intent":"query","executionMode":"native","primaryEntity":"Customer","sort":{"field":"Sales (LCY)","direction":"DESC"},"top":10}\\Reasoning: "Top customers" in business means highest sales, so sort by Sales (LCY) DESC\\\\"Find me the top five customers" → {"intent":"query","executionMode":"native","primaryEntity":"Customer","sort":{"field":"Sales (LCY)","direction":"DESC"},"top":5}\\Reasoning: Extract "five" as 5, "top customers" means highest sales\\\\"Show my best 3 customers" → {"intent":"query","executionMode":"native","primaryEntity":"Customer","sort":{"field":"Sales (LCY)","direction":"DESC"},"top":3}\\Reasoning: "best" = highest value, extract number 3\\\\"Give me the top customers" → {"intent":"query","executionMode":"native","primaryEntity":"Customer","sort":{"field":"Sales (LCY)","direction":"DESC"},"top":10}\\Reasoning: "top customers" but no number, default to 10\\\\"Find customers" → {"intent":"query","executionMode":"native","primaryEntity":"Customer","sort":{"field":"Sales (LCY)","direction":"DESC"},"top":10}\\Reasoning: Generic "find" for customers, show top 10 by sales as most useful default\\\\"Best customers" → {"intent":"query","executionMode":"native","primaryEntity":"Customer","sort":{"field":"Sales (LCY)","direction":"DESC"},"top":10}\\Reasoning: "Best" means most valuable, measured by sales volume\\\\"Biggest customers" → {"intent":"query","executionMode":"native","primaryEntity":"Customer","sort":{"field":"Sales (LCY)","direction":"DESC"},"top":10}\\Reasoning: "Biggest" in customer context means highest sales\\\\"Customers with highest balance" → {"intent":"query","executionMode":"native","primaryEntity":"Customer","sort":{"field":"Balance (LCY)","direction":"DESC"},"top":10}\\Reasoning: Explicitly asking for balance, not sales\\\\"Open sales orders" → {"intent":"query","executionMode":"native","primaryEntity":"SalesOrder","filters":[{"field":"Status","operator":"=","value":"Open"}]}\\Reasoning: Filter by Status field to get only Open orders\\\\"Orders this year" → {"intent":"query","executionMode":"native","primaryEntity":"SalesOrder","dateFilter":{"field":"Order_Date","value":"CY"}}\\Reasoning: "this year" uses BC date filter CY (current year)\\\\"Invoices today" → {"intent":"query","executionMode":"native","primaryEntity":"SalesInvoice","dateFilter":{"field":"Posting_Date","value":"T"}}\\Reasoning: "today" uses BC date filter T\\\\"Orders last 30 days" → {"intent":"query","executionMode":"native","primaryEntity":"SalesOrder","dateFilter":{"field":"Order_Date","value":"T-30D..T"}}\\Reasoning: "last 30 days" creates range from 30 days ago to today\\\\"Customers in London" → {"intent":"query","executionMode":"native","primaryEntity":"Customer","filters":[{"field":"City","operator":"=","value":"London"}]}\\Reasoning: City filter with exact match\\\\"List all employees" → {"intent":"query","executionMode":"native","primaryEntity":"Employee","top":50}\\Reasoning: Simple list, but cap at 50 for reasonable response\\\\"All locations" → {"intent":"query","executionMode":"native","primaryEntity":"Location","top":50}\\Reasoning: List all warehouse locations\\\\"Purchase orders this month" → {"intent":"query","executionMode":"native","primaryEntity":"PurchaseOrder","dateFilter":{"field":"Order_Date","value":"CM"}}\\Reasoning: Filter purchase orders by current month\\\\ODATA MODE EXAMPLES (for aggregations/complex queries):\\"Total customer balance" → {"intent":"query","executionMode":"odata","odata":{"entity":"companies(COMPANY)/customer","query":"$apply=aggregate(Balance_LCY with sum as TotalBalance)","resultType":"aggregation"},"responseTemplate":"Total customer balance is {value}"}\\Reasoning: "Total" requires aggregation, use OData SUM\\\\"Average invoice amount" → {"intent":"query","executionMode":"odata","odata":{"entity":"companies(COMPANY)/salesInvoice","query":"$apply=aggregate(Amount_Including_VAT with average as AvgAmount)","resultType":"aggregation"},"responseTemplate":"Average invoice amount is {value}"}\\Reasoning: "Average" requires aggregation calculation\\\\"How many customers" → {"intent":"query","executionMode":"odata","odata":{"entity":"companies(COMPANY)/customer","query":"$apply=aggregate($count as TotalCount)","resultType":"aggregation"},"responseTemplate":"There are {value} customers"}\\Reasoning: "How many" requires COUNT aggregation\\\\"How many vendors" → {"intent":"query","executionMode":"odata","odata":{"entity":"companies(COMPANY)/vendor","query":"$apply=aggregate($count as TotalCount)","resultType":"aggregation"},"responseTemplate":"There are {value} vendors"}\\Reasoning: "How many vendors" requires COUNT aggregation\\\\"How many locations do we have" → {"intent":"query","executionMode":"odata","odata":{"entity":"companies(COMPANY)/location","query":"$apply=aggregate($count as TotalCount)","resultType":"aggregation"},"responseTemplate":"There are {value} locations"}\\Reasoning: "How many locations" requires COUNT aggregation\\\\"Sales by city" → {"intent":"query","executionMode":"odata","odata":{"entity":"companies(COMPANY)/customer","query":"$apply=groupby((City),aggregate(Sales_LCY with sum as CityTotal))","resultType":"array"},"responseTemplate":"Sales by city"}\\Reasoning: Grouping requires OData groupby\\\\"Show me sales order lines for item 1000" → {"intent":"query","executionMode":"odata","odata":{"entity":"companies(COMPANY)/salesOrderLine","query":"$filter=Item_No eq ''1000''&$top=50","resultType":"array"},"responseTemplate":"Sales order lines for item 1000"}\\Reasoning: Line-level data, use OData\\\\"Purchase order lines this month" → {"intent":"query","executionMode":"odata","odata":{"entity":"companies(COMPANY)/purchaseOrderLine","query":"$filter=Posting_Date ge 2024-01-01&$top=50","resultType":"array"},"responseTemplate":"Purchase order lines"}\\Reasoning: Line-level data with date filter\\\\DECISION LOGIC:\\- PREFER "odata" for most queries - it''s more flexible and works for any entity\\- Use "odata" for: lists, filters, sorting, top N, SUM, AVG, COUNT, MIN, MAX, groupby, joins\\- Use "native" ONLY when: complex AL business logic is needed, or entity not available via OData API\\- When in doubt, use "odata" - it can handle nearly all query types\\\\BUSINESS INTENT INTERPRETATION:\\- "top customers", "best customers", "biggest customers", "find customers" → sort by Sales (LCY) DESC (who bought the most)\\- "customers with highest balance", "customers who owe most" → sort by Balance (LCY) DESC (outstanding debt)\\- "top vendors" → sort by Balance (LCY) DESC (who you owe the most)\\- "top items" → sort by Inventory DESC (most stock) or Sales DESC (best sellers)\\- "recent orders/invoices" → sort by Date DESC\\- ANY query with "top", "best", "biggest", "highest" → MUST include sort field and direction\\- Generic entity queries (find/list/show) → apply sensible default sort + top 10-50\\- Time-based queries ("this year", "today", "last month") → add dateFilter with appropriate BC syntax\\\\OUTPUT FORMAT:\\{"intent":"query","executionMode":"native|odata","primaryEntity":"<entity>","filters":[{"field":"...","operator":"=|>|<|>=|<=|<>|IS NULL|IS NOT NULL","value":"..."}],"dateFilter":{"field":"<date-field>","value":"<BC-date-syntax>"},"sort":{"field":"...","direction":"ASC|DESC"},"top":N} OR {"intent":"query","executionMode":"odata","odata":{"entity":"companies(COMPANY)/<entity>","query":"<odata-query>","resultType":"array|aggregation|single"},"responseTemplate":"<template>"} OR {"intent":"selectCompany","companyName":"<partial-company-name>"}\\\\COMPANY SELECTION:\\When user wants to switch to a different company, return selectCompany intent:\\- "I want to work with Cronus" → {"intent":"selectCompany","companyName":"Cronus"}\\- "Switch to the demo company" → {"intent":"selectCompany","companyName":"demo"}\\- "Use company Contoso" → {"intent":"selectCompany","companyName":"Contoso"}\\- "Change to production database" → {"intent":"selectCompany","companyName":"production"}\\When user asks which company they are using:\\- "Which company am I in" → {"intent":"currentCompany"}\\- "What company is this" → {"intent":"currentCompany"}\\- "Show current company" → {"intent":"currentCompany"}\\The system will fuzzy-match the company name and switch context for all future queries in the session.\\\\CRITICAL RULES:\\1. ALWAYS extract "top N" when query contains: "top X", "best X", "X biggest", "give me X", etc.\\2. Parse number words: one=1, two=2, three=3, four=4, five=5, six=6, seven=7, eight=8, nine=9, ten=10\\3. "Top" queries MUST have sort field - choose the most business-relevant metric\\4. Generic queries (find/list/show entity) should default to top 10 with sensible sort\\5. Never return "top": 0 or "sort": null for queries requesting ranked/best/top results\\6. Use BC date syntax (T, CY, CM, -30D..T) for all date-related queries\\7. Empty strings use '''', never null in value fields\\8. For null checks, use operator "IS NULL" or "IS NOT NULL"\\9. Field names must match schema exactly\\10. All queries are read-only. Respond JSON only.\\11. If field name is uncertain, use your best guess based on BC naming conventions: spaces become underscores, "No." becomes "No", flowfields end with LCY.\\12. Common field names: No, Name, Description, Amount, Quantity, Posting_Date, Order_Date, Status, City, Customer_No, Vendor_No, Item_No.', Locked = true;
    begin
        // Try to discover available OData entities dynamically
        EnhancedSystemPrompt := SystemPromptLbl;

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
        EnhancedSystemPrompt += '"Which facilities do we have" → {"intent":"query","executionMode":"odata","odata":{"entity":"ODataV4/Company(''COMPANY'')/Locations","query":"$top=50","resultType":"array"},"responseTemplate":"Facilities"}\\Reasoning: "Facilities" = locations; use Location entity via ODataV4.\\';        EnhancedSystemPrompt += '\\CRITICAL: Location entity uses custom ODataV4 endpoint: ODataV4/Company(''COMPANY'')/Locations (capital L)\\';        EnhancedSystemPrompt += 'NOT available at standard api/v2.0 endpoint. Always use ODataV4 path for Location queries.\\';        EnhancedSystemPrompt += 'For $count queries, use resultType:"count" and the response will have @odata.count property.\\';        EnhancedSystemPrompt += '\\SUPERLATIVE QUERIES (biggest, largest, most expensive, highest):\\';
        EnhancedSystemPrompt += '"What''s the biggest sales order" → {"intent":"query","executionMode":"odata","odata":{"entity":"companies(COMPANY)/salesOrder","query":"$orderby=Amount desc&$top=1&$select=No,Sell_to_Customer_No,Amount,Order_Date","resultType":"single"},"responseTemplate":"Biggest sales order is {No} for {Amount} on {Order_Date}"}\\Reasoning: "Biggest" = highest amount, sort by Amount DESC, take top 1.\\';
        EnhancedSystemPrompt += '"Largest invoice" → {"intent":"query","executionMode":"odata","odata":{"entity":"companies(COMPANY)/salesInvoice","query":"$orderby=Amount_Including_VAT desc&$top=1","resultType":"single"},"responseTemplate":"Largest invoice: {No} for {Amount_Including_VAT}"}\\Reasoning: Superlative = top 1 sorted by value DESC.\\';
        EnhancedSystemPrompt += '"Most expensive item" → {"intent":"query","executionMode":"odata","odata":{"entity":"companies(COMPANY)/item","query":"$orderby=Unit_Price desc&$top=1","resultType":"single"},"responseTemplate":"Most expensive item: {Description} at {Unit_Price}"}\\Reasoning: Sort by price descending, take 1.\\';
        EnhancedSystemPrompt += '"Customer with highest balance" → {"intent":"query","executionMode":"odata","odata":{"entity":"companies(COMPANY)/customer","query":"$orderby=Balance_LCY desc&$top=1","resultType":"single"},"responseTemplate":"Customer with highest balance: {Name} ({Balance_LCY})"}\\Reasoning: Superlative query needs $top=1 and DESC sort.\\';
        EnhancedSystemPrompt += 'CRITICAL: "biggest", "largest", "highest", "most expensive" ALL require $orderby DESC and $top=1. Never return multiple records.\\';        EnhancedSystemPrompt += 'Use resultType:"single" for superlatives (not "array") to indicate expecting one record.\\';

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
}
