/// <summary>
/// Integration tests for NXR Voice Assistant query processing
/// Tests complete query flow: natural language → AI → entity detection → query execution → response
/// Each test captures the full query, AI structured response, and final text output
/// </summary>
codeunit 50692 "NXR Voice Query Integ. Tests"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        IsInitialized: Boolean;
        Setup: Record "NXR Voice Assistant Setup";
        AssistantMgt: Codeunit "NXR Voice Assistant Mgt.";

    // ============================================================================
    // CUSTOMER QUERIES
    // ============================================================================

    [Test]
    procedure TestQuery_ListAllCustomers()
    var
        QueryText: Text;
        Response: Text;
    begin
        // [SCENARIO] User asks to list all customers
        Initialize();

        // [GIVEN] Query: "Show me customers"
        QueryText := 'Show me customers';

        // [WHEN] Processing the query
        Response := AssistantMgt.ProcessQuery(QueryText, '', '');

        // [THEN] Response should mention customers found
        // Expected AI Response: {"intent":"query","executionMode":"native","primaryEntity":"Customer"}
        // Expected Output: "I found X Customers."
        LogTestResult('List All Customers', QueryText, Response);
        if not (StrPos(LowerCase(Response), 'customer') > 0) then
            Error('Response should mention customers: %1', Response);
    end;

    [Test]
    procedure TestQuery_Top5Customers()
    var
        QueryText: Text;
        Response: Text;
    begin
        // [SCENARIO] User asks for top 5 customers
        Initialize();

        // [GIVEN] Query: "Who are my top 5 customers?"
        QueryText := 'Who are my top 5 customers?';

        // [WHEN] Processing the query
        Response := AssistantMgt.ProcessQuery(QueryText, '', '');

        // [THEN] Response should mention top customers
        // Expected AI Response: {"intent":"query","executionMode":"native","primaryEntity":"Customer","sort":{"field":"Sales (LCY)","direction":"DESC"},"top":5}
        // Expected Output: "Here are your top 5 customers by sales..."
        LogTestResult('Top 5 Customers', QueryText, Response);
        if not ((StrPos(LowerCase(Response), 'top') > 0) or (StrPos(LowerCase(Response), 'customer') > 0)) then
            Error('Response should mention top customers: %1', Response);
    end;

    [Test]
    procedure TestQuery_CustomersInLondon()
    var
        QueryText: Text;
        Response: Text;
    begin
        // [SCENARIO] User asks for customers in a specific city
        Initialize();

        // [GIVEN] Query: "Show me customers in London"
        QueryText := 'Show me customers in London';

        // [WHEN] Processing the query
        Response := AssistantMgt.ProcessQuery(QueryText, '', '');

        // [THEN] Response should mention customers
        // Expected AI Response: {"intent":"query","executionMode":"native","primaryEntity":"Customer","filters":[{"field":"City","operator":"=","value":"London"}]}
        // Expected Output: "Found X customer(s)..."
        LogTestResult('Customers in London', QueryText, Response);
        if not (StrPos(LowerCase(Response), 'customer') > 0) then
            Error('Response should mention customers: %1', Response);
    end;

    [Test]
    procedure TestQuery_CustomersHighestBalance()
    var
        QueryText: Text;
        Response: Text;
    begin
        // [SCENARIO] User asks which customers have highest balance
        Initialize();

        // [GIVEN] Query: "Which customers have highest balance"
        QueryText := 'Which customers have highest balance';

        // [WHEN] Processing the query
        Response := AssistantMgt.ProcessQuery(QueryText, '', '');

        // [THEN] Response should mention customers with balance info
        // Expected AI Response: {"intent":"query","executionMode":"native","primaryEntity":"Customer","sort":{"field":"Balance (LCY)","direction":"DESC"},"top":10}
        // Expected Output: "Here are your top X customers by balance..."
        LogTestResult('Customers Highest Balance', QueryText, Response);
        if not ((StrPos(LowerCase(Response), 'customer') > 0) and (StrPos(LowerCase(Response), 'balance') > 0)) then
            Error('Response should mention customers and balance: %1', Response);
    end;

    // ============================================================================
    // VENDOR QUERIES
    // ============================================================================

    [Test]
    procedure TestQuery_Top5Vendors()
    var
        QueryText: Text;
        Response: Text;
    begin
        // [SCENARIO] User asks for top 5 vendors
        Initialize();

        // [GIVEN] Query: "Who are my top 5 vendors?"
        QueryText := 'Who are my top 5 vendors?';

        // [WHEN] Processing the query
        Response := AssistantMgt.ProcessQuery(QueryText, '', '');

        // [THEN] Response should mention exactly 5 vendors (not 6!)
        // Expected AI Response: {"intent":"query","executionMode":"native","primaryEntity":"Vendor","sort":{"field":"Balance (LCY)","direction":"DESC"},"top":5}
        // Expected Output: "Top 5 vendors..."
        LogTestResult('Top 5 Vendors', QueryText, Response);
        // Verify it says "5" not "6" (bug fix validation)
        if StrPos(Response, 'Top 6') > 0 then
            Error('Should say Top 5, not Top 6: %1', Response);
        if not (StrPos(LowerCase(Response), 'vendor') > 0) then
            Error('Response should mention vendors: %1', Response);
    end;

    [Test]
    procedure TestQuery_ListAllVendors()
    var
        QueryText: Text;
        Response: Text;
    begin
        // [SCENARIO] User asks to list all vendors
        Initialize();

        // [GIVEN] Query: "Show me vendors"
        QueryText := 'Show me vendors';

        // [WHEN] Processing the query
        Response := AssistantMgt.ProcessQuery(QueryText, '', '');

        // [THEN] Response should mention vendors
        // Expected AI Response: {"intent":"query","executionMode":"native","primaryEntity":"Vendor"}
        // Expected Output: "I found X Vendors."
        LogTestResult('List All Vendors', QueryText, Response);
        if not (StrPos(LowerCase(Response), 'vendor') > 0) then
            Error('Response should mention vendors: %1', Response);
    end;

    // ============================================================================
    // ITEM QUERIES
    // ============================================================================

    [Test]
    procedure TestQuery_ItemsLowInventory()
    var
        QueryText: Text;
        Response: Text;
    begin
        // [SCENARIO] User asks for items with low inventory (OData query)
        Initialize();

        // [GIVEN] Query: "Show me items with inventory below 10"
        QueryText := 'Show me items with inventory below 10';

        // [WHEN] Processing the query
        Response := AssistantMgt.ProcessQuery(QueryText, '', '');

        // [THEN] Response should mention items (not customers!)
        // Expected AI Response: {"intent":"query","executionMode":"odata","odata":{"entity":"companies(COMPANY)/items","query":"$filter=Inventory lt 10","resultType":"array"},"responseTemplate":"Items with inventory below 10"}
        // Expected Output: Should mention items or OData error (not "5 Customers")
        LogTestResult('Items Low Inventory', QueryText, Response);
        // This should NOT fall back to saying "5 Customers" (bug fix validation)
        if StrPos(LowerCase(Response), 'customer') > 0 then
            Error('OData fallback bug: Should mention items, not customers: %1', Response);
    end;

    [Test]
    procedure TestQuery_ListAllItems()
    var
        QueryText: Text;
        Response: Text;
    begin
        // [SCENARIO] User asks to list all items
        Initialize();

        // [GIVEN] Query: "Show me items"
        QueryText := 'Show me items';

        // [WHEN] Processing the query
        Response := AssistantMgt.ProcessQuery(QueryText, '', '');

        // [THEN] Response should mention items
        // Expected AI Response: {"intent":"query","executionMode":"native","primaryEntity":"Item"}
        // Expected Output: "I found X Items."
        LogTestResult('List All Items', QueryText, Response);
        if not (StrPos(LowerCase(Response), 'item') > 0) then
            Error('Response should mention items: %1', Response);
    end;

    // ============================================================================
    // SALES ORDER QUERIES
    // ============================================================================

    [Test]
    procedure TestQuery_OrdersThisWeek()
    var
        QueryText: Text;
        Response: Text;
    begin
        // [SCENARIO] User asks for sales orders from this week
        Initialize();

        // [GIVEN] Query: "Show me orders from this week"
        QueryText := 'Show me orders from this week';

        // [WHEN] Processing the query
        Response := AssistantMgt.ProcessQuery(QueryText, '', '');

        // [THEN] Response should mention orders
        // Expected AI Response: {"intent":"query","executionMode":"native","primaryEntity":"SalesOrder","dateRange":"ThisWeek"}
        // Expected Output: "I found X SalesOrders." or "Here are orders from this week"
        LogTestResult('Orders This Week', QueryText, Response);
        if not ((StrPos(LowerCase(Response), 'order') > 0) or (StrPos(LowerCase(Response), 'sales') > 0)) then
            Error('Response should mention orders: %1', Response);
    end;

    [Test]
    procedure TestQuery_Top10Orders()
    var
        QueryText: Text;
        Response: Text;
    begin
        // [SCENARIO] User asks for top 10 orders
        Initialize();

        // [GIVEN] Query: "Show me top 10 sales orders"
        QueryText := 'Show me top 10 sales orders';

        // [WHEN] Processing the query
        Response := AssistantMgt.ProcessQuery(QueryText, '', '');

        // [THEN] Response should mention orders
        // Expected AI Response: {"intent":"query","executionMode":"native","primaryEntity":"SalesOrder","top":10}
        // Expected Output: "Here are the top 10 SalesOrders."
        LogTestResult('Top 10 Orders', QueryText, Response);
        if not (StrPos(LowerCase(Response), 'order') > 0) then
            Error('Response should mention orders: %1', Response);
    end;

    [Test]
    procedure TestQuery_LastSalesOrderNumber()
    var
        QueryText: Text;
        Response: Text;
    begin
        // [SCENARIO] User asks for the last sales order number
        Initialize();

        // [GIVEN] Query: "What is the last sales order number"
        QueryText := 'What is the last sales order number';

        // [WHEN] Processing the query
        Response := AssistantMgt.ProcessQuery(QueryText, '', '');

        // [THEN] Response should focus on a single sales order, not totals
        LogTestResult('Last Sales Order Number', QueryText, Response);
        if (StrPos(LowerCase(Response), 'order') = 0) then
            Error('Response should mention order: %1', Response);
        if (StrPos(LowerCase(Response), 'open orders totalling') > 0) then
            Error('Response should not return open order totals: %1', Response);
    end;

    [Test]
    procedure TestQuery_BiggestSalesOrder()
    var
        QueryText: Text;
        Response: Text;
    begin
        // [SCENARIO] User asks for the biggest sales order
        Initialize();

        // [GIVEN] Query: "What is the biggest sales order"
        QueryText := 'What is the biggest sales order';

        // [WHEN] Processing the query
        Response := AssistantMgt.ProcessQuery(QueryText, '', '');

        // [THEN] Response should mention sales order
        LogTestResult('Biggest Sales Order', QueryText, Response);
        if (StrPos(LowerCase(Response), 'order') = 0) then
            Error('Response should mention order: %1', Response);
    end;

    [Test]
    procedure TestQuery_LatestInvoice()
    var
        QueryText: Text;
        Response: Text;
    begin
        // [SCENARIO] User asks for the latest invoice
        Initialize();

        // [GIVEN] Query: "Latest invoice"
        QueryText := 'Latest invoice';

        // [WHEN] Processing the query
        Response := AssistantMgt.ProcessQuery(QueryText, '', '');

        // [THEN] Response should mention invoice
        LogTestResult('Latest Invoice', QueryText, Response);
        if (StrPos(LowerCase(Response), 'invoice') = 0) then
            Error('Response should mention invoice: %1', Response);
    end;

    [Test]
    procedure TestQuery_LocationCount()
    var
        QueryText: Text;
        Response: Text;
    begin
        // [SCENARIO] User asks how many locations exist
        Initialize();

        // [GIVEN] Query: "How many locations do we have"
        QueryText := 'How many locations do we have';

        // [WHEN] Processing the query
        Response := AssistantMgt.ProcessQuery(QueryText, '', '');

        // [THEN] Response should mention locations
        LogTestResult('Count Locations', QueryText, Response);
        if (StrPos(LowerCase(Response), 'location') = 0) then
            Error('Response should mention locations: %1', Response);
    end;

    // ============================================================================
    // COMPLEX/ODATA QUERIES
    // ============================================================================

    [Test]
    procedure TestQuery_CustomersBoughtBicycles()
    var
        QueryText: Text;
        Response: Text;
    begin
        // [SCENARIO] User asks for customers who bought specific items (OData query)
        Initialize();

        // [GIVEN] Query: "Find customers who bought bicycles"
        QueryText := 'Find customers who bought bicycles';

        // [WHEN] Processing the query
        Response := AssistantMgt.ProcessQuery(QueryText, '', '');

        // [THEN] Response should relate to the query
        // Expected AI Response: {"intent":"query","executionMode":"odata","odata":{"entity":"companies(COMPANY)/salesOrderLines","query":"$filter=contains(Description,'bicycle')&$top=50","resultType":"array"},"responseTemplate":"Customers who bought bicycles"}
        // Expected Output: Should process OData or return meaningful error (not "5 Customers")
        LogTestResult('Customers Bought Bicycles', QueryText, Response);
        // Should NOT fall back to generic customer query (bug fix validation)
        if (StrPos(Response, 'I found 5 Customers') > 0) then
            Error('OData fallback bug detected: %1', Response);
    end;

    [Test]
    procedure TestQuery_CountCustomers()
    var
        QueryText: Text;
        Response: Text;
    begin
        // [SCENARIO] User asks how many customers exist (aggregation query)
        Initialize();

        // [GIVEN] Query: "How many customers are there in the database"
        QueryText := 'How many customers are there in the database';

        // [WHEN] Processing the query
        Response := AssistantMgt.ProcessQuery(QueryText, '', '');

        // [THEN] Response should provide a count or explain aggregation limitation
        // Expected AI Response: {"intent":"query","executionMode":"odata","odata":{"entity":"companies(COMPANY)/customers","query":"$apply=aggregate($count as TotalCount)","resultType":"aggregation"},"responseTemplate":"There are {value} customers"}
        // Expected Output: "There are X customers" or OData error
        LogTestResult('Count Customers', QueryText, Response);
        if StrPos(LowerCase(Response), 'customer') = 0 then
            Error('Response should mention customers: %1', Response);
    end;

    // ============================================================================
    // COMPANY SELECTION QUERIES
    // ============================================================================

    [Test]
    procedure TestQuery_SwitchCompany()
    var
        QueryText: Text;
        Response: Text;
    begin
        // [SCENARIO] User asks to switch to a different company
        Initialize();

        // [GIVEN] Query: "Switch to company Cronus"
        QueryText := 'Switch to company Cronus';

        // [WHEN] Processing the query
        Response := AssistantMgt.ProcessQuery(QueryText, '', '');

        // [THEN] Response should acknowledge company switch or list available companies
        // Expected AI Response: {"intent":"selectCompany","companyName":"Cronus"}
        // Expected Output: "Switched to company X" or "Available companies: ..."
        LogTestResult('Switch Company', QueryText, Response);
        if not (StrPos(LowerCase(Response), 'company') > 0) then
            Error('Response should mention company: %1', Response);
    end;

    [Test]
    procedure TestQuery_CurrentCompany()
    var
        QueryText: Text;
        Response: Text;
    begin
        // [SCENARIO] User asks which company they're working in
        Initialize();

        // [GIVEN] Query: "Which company am I working in"
        QueryText := 'Which company am I working in';

        // [WHEN] Processing the query
        Response := AssistantMgt.ProcessQuery(QueryText, '', '');

        // [THEN] Response should state the current company
        // Expected AI Response: {"intent":"currentCompany"}
        // Expected Output: "You are currently working in company X"
        LogTestResult('Current Company', QueryText, Response);
        if not (StrPos(LowerCase(Response), 'company') > 0) then
            Error('Response should mention company: %1', Response);
    end;

    // ============================================================================
    // EDGE CASES AND ERROR HANDLING
    // ============================================================================

    [Test]
    procedure TestQuery_UnrecognizedQuery()
    var
        QueryText: Text;
        Response: Text;
    begin
        // [SCENARIO] User asks something the system doesn't understand
        Initialize();

        // [GIVEN] Query: "Make me a sandwich"
        QueryText := 'Make me a sandwich';

        // [WHEN] Processing the query
        Response := AssistantMgt.ProcessQuery(QueryText, '', '');

        // [THEN] Response should indicate it didn't understand
        // Expected Output: "I didn't understand that query"
        LogTestResult('Unrecognized Query', QueryText, Response);
        if not ((StrPos(LowerCase(Response), 'didn''t understand') > 0) or (StrPos(LowerCase(Response), 'don''t understand') > 0)) then
            Error('Response should indicate lack of understanding: %1', Response);
    end;

    [Test]
    procedure TestQuery_EmptyQuery()
    var
        QueryText: Text;
        Response: Text;
    begin
        // [SCENARIO] User submits an empty query
        Initialize();

        // [GIVEN] Query: ""
        QueryText := '';

        // [WHEN] Processing the query
        Response := AssistantMgt.ProcessQuery(QueryText, '', '');

        // [THEN] Response should handle gracefully
        // Expected Output: Error or "I didn't understand"
        LogTestResult('Empty Query', QueryText, Response);
        // Should not crash (no error = success)
    end;

    // ============================================================================
    // DATE/TIME QUERIES
    // ============================================================================

    [Test]
    procedure TestQuery_OrdersToday()
    var
        QueryText: Text;
        Response: Text;
    begin
        // [SCENARIO] User asks for orders from today
        Initialize();

        // [GIVEN] Query: "Show me orders from today"
        QueryText := 'Show me orders from today';

        // [WHEN] Processing the query
        Response := AssistantMgt.ProcessQuery(QueryText, '', '');

        // [THEN] Response should mention today's orders
        // Expected AI Response: {"intent":"query","executionMode":"native","primaryEntity":"SalesOrder","dateFilter":"today"}
        // Expected Output: "I found X SalesOrders from today"
        LogTestResult('Orders Today', QueryText, Response);
        if not (StrPos(LowerCase(Response), 'order') > 0) then
            Error('Response should mention orders: %1', Response);
    end;

    [Test]
    procedure TestQuery_OrdersThisMonth()
    var
        QueryText: Text;
        Response: Text;
    begin
        // [SCENARIO] User asks for orders from this month
        Initialize();

        // [GIVEN] Query: "Show me orders from this month"
        QueryText := 'Show me orders from this month';

        // [WHEN] Processing the query
        Response := AssistantMgt.ProcessQuery(QueryText, '', '');

        // [THEN] Response should mention monthly orders
        // Expected AI Response: {"intent":"query","executionMode":"native","primaryEntity":"SalesOrder","dateRange":"ThisMonth"}
        // Expected Output: "I found X SalesOrders from this month"
        LogTestResult('Orders This Month', QueryText, Response);
        if not (StrPos(LowerCase(Response), 'order') > 0) then
            Error('Response should mention orders: %1', Response);
    end;

    // ============================================================================
    // SORTING AND RANKING QUERIES
    // ============================================================================

    [Test]
    procedure TestQuery_BestSellingCustomer()
    var
        QueryText: Text;
        Response: Text;
    begin
        // [SCENARIO] User asks for the best selling customer
        Initialize();

        // [GIVEN] Query: "Who is my best selling customer"
        QueryText := 'Who is my best selling customer';

        // [WHEN] Processing the query
        Response := AssistantMgt.ProcessQuery(QueryText, '', '');

        // [THEN] Response should mention top customer
        // Expected AI Response: {"intent":"query","executionMode":"native","primaryEntity":"Customer","sort":{"field":"Sales (LCY)","direction":"DESC"},"top":1}
        // Expected Output: "Top customer: X" or "I found 1 Customer"
        LogTestResult('Best Selling Customer', QueryText, Response);
        if not (StrPos(LowerCase(Response), 'customer') > 0) then
            Error('Response should mention customer: %1', Response);
    end;

    [Test]
    procedure TestQuery_LowestInventoryItems()
    var
        QueryText: Text;
        Response: Text;
    begin
        // [SCENARIO] User asks for items with lowest inventory
        Initialize();

        // [GIVEN] Query: "Which items have the lowest inventory"
        QueryText := 'Which items have the lowest inventory';

        // [WHEN] Processing the query
        Response := AssistantMgt.ProcessQuery(QueryText, '', '');

        // [THEN] Response should mention items
        // Expected AI Response: {"intent":"query","executionMode":"native","primaryEntity":"Item","sort":{"field":"Inventory","direction":"ASC"},"top":10}
        // Expected Output: "Here are items with lowest inventory"
        LogTestResult('Lowest Inventory Items', QueryText, Response);
        if not (StrPos(LowerCase(Response), 'item') > 0) then
            Error('Response should mention items: %1', Response);
    end;

    // ============================================================================
    // HELPER METHODS
    // ============================================================================

    local procedure Initialize()
    begin
        if IsInitialized then
            exit;

        // Setup debug mode for detailed output
        if not Setup.Get() then begin
            Setup.Init();
            Setup."Primary Key" := '';
            Setup."Debug Mode" := true;
            Setup.Insert(true);
        end else begin
            Setup."Debug Mode" := true;
            Setup.Modify(true);
        end;

        IsInitialized := true;
        Commit();
    end;

    local procedure LogTestResult(TestName: Text; QueryText: Text; Response: Text)
    var
        LogMessage: Text;
    begin
        // Format test results for easy copy/paste analysis
        LogMessage := '\===============================================\';
        LogMessage += 'TEST: ' + TestName + '\';
        LogMessage += 'QUERY: ' + QueryText + '\';
        LogMessage += 'RESPONSE:\' + Response + '\';
        LogMessage += '===============================================\';

        // Output to test log
        Message(LogMessage);
    end;
}
