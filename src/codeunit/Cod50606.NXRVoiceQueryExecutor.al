/// <summary>
/// Executes structured queries against Business Central entities (customers, items, vendors, sales orders).
/// Translates intent records into actual BC table queries and returns formatted results.
/// </summary>
codeunit 50606 "NXR Voice Query Executor"
{
    /// <summary>
    /// Executes a query based on the analyzed intent and returns results.
    /// </summary>
    /// <param name="Intent">The analyzed query intent containing entity type, filters, and parameters.</param>
    /// <param name="ResultData">JSON object containing the query results.</param>
    /// <param name="RecordCount">Number of records returned by the query.</param>
    /// <returns>True if the query executed successfully, false otherwise.</returns>
    procedure ExecuteQuery(Intent: Record "NXR Voice Query Intent" temporary; var ResultData: JsonObject; var RecordCount: Integer): Boolean
    begin
        case Intent.Entity of
            // Master Data
            Intent.Entity::Customer:
                exit(QueryCustomers(Intent, ResultData, RecordCount));
            Intent.Entity::Vendor:
                exit(QueryVendors(Intent, ResultData, RecordCount));
            Intent.Entity::Item:
                exit(QueryItems(Intent, ResultData, RecordCount));
            Intent.Entity::Contact:
                exit(QueryContacts(Intent, ResultData, RecordCount));
            Intent.Entity::Employee:
                exit(QueryEmployees(Intent, ResultData, RecordCount));
            Intent.Entity::Location:
                exit(QueryLocations(Intent, ResultData, RecordCount));
            Intent.Entity::Resource:
                exit(QueryResources(Intent, ResultData, RecordCount));
            Intent.Entity::GLAccount:
                exit(QueryGLAccounts(Intent, ResultData, RecordCount));
            Intent.Entity::BankAccount:
                exit(QueryBankAccounts(Intent, ResultData, RecordCount));
            // Sales Documents
            Intent.Entity::SalesOrder:
                exit(QuerySalesOrders(Intent, ResultData, RecordCount));
            Intent.Entity::SalesQuote:
                exit(QuerySalesQuotes(Intent, ResultData, RecordCount));
            Intent.Entity::SalesInvoice:
                exit(QuerySalesInvoices(Intent, ResultData, RecordCount));
            Intent.Entity::SalesCreditMemo:
                exit(QuerySalesCreditMemos(Intent, ResultData, RecordCount));
            Intent.Entity::SalesShipment:
                exit(QuerySalesShipments(Intent, ResultData, RecordCount));
            // Purchase Documents
            Intent.Entity::PurchaseOrder:
                exit(QueryPurchaseOrders(Intent, ResultData, RecordCount));
            Intent.Entity::PurchaseQuote:
                exit(QueryPurchaseQuotes(Intent, ResultData, RecordCount));
            Intent.Entity::PurchaseInvoice:
                exit(QueryPurchaseInvoices(Intent, ResultData, RecordCount));
            Intent.Entity::PurchaseCreditMemo:
                exit(QueryPurchaseCreditMemos(Intent, ResultData, RecordCount));
            Intent.Entity::PurchaseReceipt:
                exit(QueryPurchaseReceipts(Intent, ResultData, RecordCount));
            // Ledger Entries
            Intent.Entity::GLEntry:
                exit(QueryGLEntries(Intent, ResultData, RecordCount));
            Intent.Entity::CustomerLedgerEntry:
                exit(QueryCustomerLedgerEntries(Intent, ResultData, RecordCount));
            Intent.Entity::VendorLedgerEntry:
                exit(QueryVendorLedgerEntries(Intent, ResultData, RecordCount));
            Intent.Entity::ItemLedgerEntry:
                exit(QueryItemLedgerEntries(Intent, ResultData, RecordCount));
            // Jobs
            Intent.Entity::Job:
                exit(QueryJobs(Intent, ResultData, RecordCount));
        end;
        exit(false);
    end;

    local procedure QueryCustomers(Intent: Record "NXR Voice Query Intent" temporary; var ResultData: JsonObject; var RecordCount: Integer): Boolean
    var
        Customer: Record Customer;
        ResultArray: JsonArray;
        CustomerJson: JsonObject;
    begin
        // Apply filters
        if Intent."Specific Filter" <> '' then
            Customer.SetFilter("No.", '@' + Intent."Specific Filter" + '*');

        // Apply top N with sorting by balance
        if Intent."Top N" > 0 then begin
            Customer.SetCurrentKey("Balance (LCY)");
            Customer.Ascending(false);
        end;

        // Execute query
        if not Customer.FindSet() then
            exit(true);

        RecordCount := 0;
        repeat
            RecordCount += 1;
            if (Intent."Top N" > 0) and (RecordCount > Intent."Top N") then
                break;

            Clear(CustomerJson);
            CustomerJson.Add('no', Customer."No.");
            CustomerJson.Add('name', Customer.Name);
            Customer.CalcFields("Balance (LCY)", "Sales (LCY)");
            CustomerJson.Add('balance', Customer."Balance (LCY)");
            CustomerJson.Add('salesLCY', Customer."Sales (LCY)");
            ResultArray.Add(CustomerJson);
        until Customer.Next() = 0;

        ResultData.Add('customers', ResultArray);
        exit(true);
    end;

    local procedure QuerySalesOrders(Intent: Record "NXR Voice Query Intent" temporary; var ResultData: JsonObject; var RecordCount: Integer): Boolean
    var
        SalesHeader: Record "Sales Header";
        ResultArray: JsonArray;
        OrderJson: JsonObject;
        StartDate: Date;
        EndDate: Date;
    begin
        SalesHeader.SetRange("Document Type", SalesHeader."Document Type"::Order);

        // Apply date filters
        if Intent."Date Filter" <> 0D then
            SalesHeader.SetRange("Order Date", Intent."Date Filter")
        else if Intent."Date Range" <> Intent."Date Range"::None then begin
            GetDateRange(Intent."Date Range", StartDate, EndDate);
            SalesHeader.SetRange("Order Date", StartDate, EndDate);
        end;

        // Apply specific filter
        if Intent."Specific Filter" <> '' then
            SalesHeader.SetFilter("No.", '@' + Intent."Specific Filter" + '*');

        // Execute query
        if not SalesHeader.FindSet() then
            exit(true);

        RecordCount := 0;
        repeat
            RecordCount += 1;
            if (Intent."Top N" > 0) and (RecordCount > Intent."Top N") then
                break;

            Clear(OrderJson);
            OrderJson.Add('no', SalesHeader."No.");
            OrderJson.Add('orderDate', Format(SalesHeader."Order Date"));
            OrderJson.Add('customerName', SalesHeader."Sell-to Customer Name");
            SalesHeader.CalcFields(Amount);
            OrderJson.Add('amount', SalesHeader.Amount);
            ResultArray.Add(OrderJson);
        until SalesHeader.Next() = 0;

        ResultData.Add('salesOrders', ResultArray);
        exit(true);
    end;

    local procedure QueryItems(Intent: Record "NXR Voice Query Intent" temporary; var ResultData: JsonObject; var RecordCount: Integer): Boolean
    var
        Item: Record Item;
        ResultArray: JsonArray;
        ItemJson: JsonObject;
    begin
        // Apply specific filter
        if Intent."Specific Filter" <> '' then
            Item.SetFilter("No.", '@' + Intent."Specific Filter" + '*');

        // Apply top N with inventory ordering
        if Intent."Top N" > 0 then begin
            Item.SetCurrentKey(Inventory);
            Item.Ascending(false);
        end;

        // Execute query
        if not Item.FindSet() then
            exit(true);

        RecordCount := 0;
        repeat
            RecordCount += 1;
            if (Intent."Top N" > 0) and (RecordCount > Intent."Top N") then
                break;

            Clear(ItemJson);
            ItemJson.Add('no', Item."No.");
            ItemJson.Add('description', Item.Description);
            Item.CalcFields(Inventory);
            ItemJson.Add('inventory', Item.Inventory);
            ItemJson.Add('unitPrice', Item."Unit Price");
            ResultArray.Add(ItemJson);
        until Item.Next() = 0;

        ResultData.Add('items', ResultArray);
        exit(true);
    end;

    local procedure QuerySalesInvoices(Intent: Record "NXR Voice Query Intent" temporary; var ResultData: JsonObject; var RecordCount: Integer): Boolean
    var
        SalesInvoiceHeader: Record "Sales Invoice Header";
        ResultArray: JsonArray;
        InvoiceJson: JsonObject;
        StartDate: Date;
        EndDate: Date;
    begin
        // Apply date filters
        if Intent."Date Filter" <> 0D then
            SalesInvoiceHeader.SetRange("Posting Date", Intent."Date Filter")
        else if Intent."Date Range" <> Intent."Date Range"::None then begin
            GetDateRange(Intent."Date Range", StartDate, EndDate);
            SalesInvoiceHeader.SetRange("Posting Date", StartDate, EndDate);
        end;

        // Apply specific filter
        if Intent."Specific Filter" <> '' then
            SalesInvoiceHeader.SetFilter("No.", Intent."Specific Filter");

        // Execute query
        if not SalesInvoiceHeader.FindSet() then
            exit(true);

        RecordCount := 0;
        repeat
            RecordCount += 1;
            if (Intent."Top N" > 0) and (RecordCount > Intent."Top N") then
                break;

            Clear(InvoiceJson);
            InvoiceJson.Add('no', SalesInvoiceHeader."No.");
            InvoiceJson.Add('postingDate', Format(SalesInvoiceHeader."Posting Date"));
            InvoiceJson.Add('customerName', SalesInvoiceHeader."Sell-to Customer Name");
            SalesInvoiceHeader.CalcFields("Amount Including VAT");
            InvoiceJson.Add('amount', SalesInvoiceHeader."Amount Including VAT");
            ResultArray.Add(InvoiceJson);
        until SalesInvoiceHeader.Next() = 0;

        ResultData.Add('salesInvoices', ResultArray);
        exit(true);
    end;

    local procedure QueryVendors(Intent: Record "NXR Voice Query Intent" temporary; var ResultData: JsonObject; var RecordCount: Integer): Boolean
    var
        Vendor: Record Vendor;
        ResultArray: JsonArray;
        VendorJson: JsonObject;
    begin
        // Apply specific filter
        if Intent."Specific Filter" <> '' then
            Vendor.SetFilter("No.", '@' + Intent."Specific Filter" + '*');

        // Apply top N
        if Intent."Top N" > 0 then begin
            Vendor.SetCurrentKey("Balance (LCY)");
            Vendor.Ascending(false);
        end;

        // Execute query
        if not Vendor.FindSet() then
            exit(true);

        RecordCount := 0;
        repeat
            // Check TopN limit before processing
            if (Intent."Top N" > 0) and (RecordCount >= Intent."Top N") then
                break;

            RecordCount += 1;
            Clear(VendorJson);
            VendorJson.Add('no', Vendor."No.");
            VendorJson.Add('name', Vendor.Name);
            Vendor.CalcFields("Balance (LCY)");
            VendorJson.Add('balance', Vendor."Balance (LCY)");
            ResultArray.Add(VendorJson);
        until Vendor.Next() = 0;

        ResultData.Add('vendors', ResultArray);
        exit(true);
    end;

    local procedure GetDateRange(DateRange: Enum "NXR Voice Date Range"; var StartDate: Date; var EndDate: Date)
    begin
        EndDate := Today;
        case DateRange of
            DateRange::ThisWeek:
                StartDate := CalcDate('<-CW>', Today);
            DateRange::ThisMonth:
                StartDate := CalcDate('<-CM>', Today);
            DateRange::ThisYear:
                StartDate := CalcDate('<-CY>', Today);
            DateRange::LastWeek:
                begin
                    StartDate := CalcDate('<-CW-1W>', Today);
                    EndDate := CalcDate('<CW-1W>', Today);
                end;
            DateRange::LastMonth:
                begin
                    StartDate := CalcDate('<-CM-1M>', Today);
                    EndDate := CalcDate('<CM-1M>', Today);
                end;
        end;
    end;

    // ========== ADDITIONAL MASTER DATA QUERIES ==========

    local procedure QueryContacts(Intent: Record "NXR Voice Query Intent" temporary; var ResultData: JsonObject; var RecordCount: Integer): Boolean
    var
        Contact: Record Contact;
        ResultArray: JsonArray;
        ContactJson: JsonObject;
    begin
        if Intent."Specific Filter" <> '' then
            Contact.SetFilter("No.", '@' + Intent."Specific Filter" + '*');

        if not Contact.FindSet() then
            exit(true);

        RecordCount := 0;
        repeat
            RecordCount += 1;
            if (Intent."Top N" > 0) and (RecordCount > Intent."Top N") then break;
            Clear(ContactJson);
            ContactJson.Add('no', Contact."No.");
            ContactJson.Add('name', Contact.Name);
            ContactJson.Add('companyName', Contact."Company Name");
            ContactJson.Add('phoneNo', Contact."Phone No.");
            ContactJson.Add('email', Contact."E-Mail");
            ResultArray.Add(ContactJson);
        until Contact.Next() = 0;

        ResultData.Add('contacts', ResultArray);
        exit(true);
    end;

    local procedure QueryEmployees(Intent: Record "NXR Voice Query Intent" temporary; var ResultData: JsonObject; var RecordCount: Integer): Boolean
    var
        Employee: Record Employee;
        ResultArray: JsonArray;
        EmployeeJson: JsonObject;
    begin
        if Intent."Specific Filter" <> '' then
            Employee.SetFilter("No.", '@' + Intent."Specific Filter" + '*');

        if not Employee.FindSet() then
            exit(true);

        RecordCount := 0;
        repeat
            RecordCount += 1;
            if (Intent."Top N" > 0) and (RecordCount > Intent."Top N") then break;
            Clear(EmployeeJson);
            EmployeeJson.Add('no', Employee."No.");
            EmployeeJson.Add('firstName', Employee."First Name");
            EmployeeJson.Add('lastName', Employee."Last Name");
            EmployeeJson.Add('jobTitle', Employee."Job Title");
            ResultArray.Add(EmployeeJson);
        until Employee.Next() = 0;

        ResultData.Add('employees', ResultArray);
        exit(true);
    end;

    local procedure QueryLocations(Intent: Record "NXR Voice Query Intent" temporary; var ResultData: JsonObject; var RecordCount: Integer): Boolean
    var
        Location: Record Location;
        ResultArray: JsonArray;
        LocationJson: JsonObject;
    begin
        if Intent."Specific Filter" <> '' then
            Location.SetFilter(Code, '@' + Intent."Specific Filter" + '*');

        if not Location.FindSet() then
            exit(true);

        RecordCount := 0;
        repeat
            RecordCount += 1;
            if (Intent."Top N" > 0) and (RecordCount > Intent."Top N") then break;
            Clear(LocationJson);
            LocationJson.Add('code', Location.Code);
            LocationJson.Add('name', Location.Name);
            LocationJson.Add('city', Location.City);
            ResultArray.Add(LocationJson);
        until Location.Next() = 0;

        ResultData.Add('locations', ResultArray);
        exit(true);
    end;

    local procedure QueryResources(Intent: Record "NXR Voice Query Intent" temporary; var ResultData: JsonObject; var RecordCount: Integer): Boolean
    var
        Resource: Record Resource;
        ResultArray: JsonArray;
        ResourceJson: JsonObject;
    begin
        if Intent."Specific Filter" <> '' then
            Resource.SetFilter("No.", '@' + Intent."Specific Filter" + '*');

        if not Resource.FindSet() then
            exit(true);

        RecordCount := 0;
        repeat
            RecordCount += 1;
            if (Intent."Top N" > 0) and (RecordCount > Intent."Top N") then break;
            Clear(ResourceJson);
            ResourceJson.Add('no', Resource."No.");
            ResourceJson.Add('name', Resource.Name);
            ResourceJson.Add('type', Format(Resource.Type));
            ResourceJson.Add('unitPrice', Resource."Unit Price");
            ResultArray.Add(ResourceJson);
        until Resource.Next() = 0;

        ResultData.Add('resources', ResultArray);
        exit(true);
    end;

    local procedure QueryGLAccounts(Intent: Record "NXR Voice Query Intent" temporary; var ResultData: JsonObject; var RecordCount: Integer): Boolean
    var
        GLAccount: Record "G/L Account";
        ResultArray: JsonArray;
        AccountJson: JsonObject;
    begin
        if Intent."Specific Filter" <> '' then
            GLAccount.SetFilter("No.", '@' + Intent."Specific Filter" + '*');

        if not GLAccount.FindSet() then
            exit(true);

        RecordCount := 0;
        repeat
            RecordCount += 1;
            if (Intent."Top N" > 0) and (RecordCount > Intent."Top N") then break;
            Clear(AccountJson);
            AccountJson.Add('no', GLAccount."No.");
            AccountJson.Add('name', GLAccount.Name);
            GLAccount.CalcFields(Balance);
            AccountJson.Add('balance', GLAccount.Balance);
            ResultArray.Add(AccountJson);
        until GLAccount.Next() = 0;

        ResultData.Add('glAccounts', ResultArray);
        exit(true);
    end;

    local procedure QueryBankAccounts(Intent: Record "NXR Voice Query Intent" temporary; var ResultData: JsonObject; var RecordCount: Integer): Boolean
    var
        BankAccount: Record "Bank Account";
        ResultArray: JsonArray;
        BankJson: JsonObject;
    begin
        if Intent."Specific Filter" <> '' then
            BankAccount.SetFilter("No.", '@' + Intent."Specific Filter" + '*');

        if not BankAccount.FindSet() then
            exit(true);

        RecordCount := 0;
        repeat
            RecordCount += 1;
            if (Intent."Top N" > 0) and (RecordCount > Intent."Top N") then break;
            Clear(BankJson);
            BankJson.Add('no', BankAccount."No.");
            BankJson.Add('name', BankAccount.Name);
            BankAccount.CalcFields("Balance (LCY)");
            BankJson.Add('balance', BankAccount."Balance (LCY)");
            ResultArray.Add(BankJson);
        until BankAccount.Next() = 0;

        ResultData.Add('bankAccounts', ResultArray);
        exit(true);
    end;

    // ========== ADDITIONAL SALES DOCUMENT QUERIES ==========

    local procedure QuerySalesQuotes(Intent: Record "NXR Voice Query Intent" temporary; var ResultData: JsonObject; var RecordCount: Integer): Boolean
    var
        SalesHeader: Record "Sales Header";
        ResultArray: JsonArray;
        QuoteJson: JsonObject;
        StartDate, EndDate : Date;
    begin
        SalesHeader.SetRange("Document Type", SalesHeader."Document Type"::Quote);
        if Intent."Date Filter" <> 0D then
            SalesHeader.SetRange("Document Date", Intent."Date Filter")
        else if Intent."Date Range" <> Intent."Date Range"::None then begin
            GetDateRange(Intent."Date Range", StartDate, EndDate);
            SalesHeader.SetRange("Document Date", StartDate, EndDate);
        end;

        if not SalesHeader.FindSet() then exit(true);

        RecordCount := 0;
        repeat
            RecordCount += 1;
            if (Intent."Top N" > 0) and (RecordCount > Intent."Top N") then break;
            Clear(QuoteJson);
            QuoteJson.Add('no', SalesHeader."No.");
            QuoteJson.Add('documentDate', Format(SalesHeader."Document Date"));
            QuoteJson.Add('customerName', SalesHeader."Sell-to Customer Name");
            SalesHeader.CalcFields(Amount);
            QuoteJson.Add('amount', SalesHeader.Amount);
            ResultArray.Add(QuoteJson);
        until SalesHeader.Next() = 0;

        ResultData.Add('salesQuotes', ResultArray);
        exit(true);
    end;

    local procedure QuerySalesCreditMemos(Intent: Record "NXR Voice Query Intent" temporary; var ResultData: JsonObject; var RecordCount: Integer): Boolean
    var
        SalesCrMemoHeader: Record "Sales Cr.Memo Header";
        ResultArray: JsonArray;
        CreditJson: JsonObject;
        StartDate, EndDate : Date;
    begin
        if Intent."Date Filter" <> 0D then
            SalesCrMemoHeader.SetRange("Posting Date", Intent."Date Filter")
        else if Intent."Date Range" <> Intent."Date Range"::None then begin
            GetDateRange(Intent."Date Range", StartDate, EndDate);
            SalesCrMemoHeader.SetRange("Posting Date", StartDate, EndDate);
        end;

        if not SalesCrMemoHeader.FindSet() then exit(true);

        RecordCount := 0;
        repeat
            RecordCount += 1;
            if (Intent."Top N" > 0) and (RecordCount > Intent."Top N") then break;
            Clear(CreditJson);
            CreditJson.Add('no', SalesCrMemoHeader."No.");
            CreditJson.Add('postingDate', Format(SalesCrMemoHeader."Posting Date"));
            CreditJson.Add('customerName', SalesCrMemoHeader."Sell-to Customer Name");
            SalesCrMemoHeader.CalcFields("Amount Including VAT");
            CreditJson.Add('amount', SalesCrMemoHeader."Amount Including VAT");
            ResultArray.Add(CreditJson);
        until SalesCrMemoHeader.Next() = 0;

        ResultData.Add('salesCreditMemos', ResultArray);
        exit(true);
    end;

    local procedure QuerySalesShipments(Intent: Record "NXR Voice Query Intent" temporary; var ResultData: JsonObject; var RecordCount: Integer): Boolean
    var
        SalesShipmentHeader: Record "Sales Shipment Header";
        ResultArray: JsonArray;
        ShipmentJson: JsonObject;
        StartDate, EndDate : Date;
    begin
        if Intent."Date Filter" <> 0D then
            SalesShipmentHeader.SetRange("Posting Date", Intent."Date Filter")
        else if Intent."Date Range" <> Intent."Date Range"::None then begin
            GetDateRange(Intent."Date Range", StartDate, EndDate);
            SalesShipmentHeader.SetRange("Posting Date", StartDate, EndDate);
        end;

        if not SalesShipmentHeader.FindSet() then exit(true);

        RecordCount := 0;
        repeat
            RecordCount += 1;
            if (Intent."Top N" > 0) and (RecordCount > Intent."Top N") then break;
            Clear(ShipmentJson);
            ShipmentJson.Add('no', SalesShipmentHeader."No.");
            ShipmentJson.Add('postingDate', Format(SalesShipmentHeader."Posting Date"));
            ShipmentJson.Add('customerName', SalesShipmentHeader."Sell-to Customer Name");
            ResultArray.Add(ShipmentJson);
        until SalesShipmentHeader.Next() = 0;

        ResultData.Add('salesShipments', ResultArray);
        exit(true);
    end;

    // ========== PURCHASE DOCUMENT QUERIES ==========

    local procedure QueryPurchaseOrders(Intent: Record "NXR Voice Query Intent" temporary; var ResultData: JsonObject; var RecordCount: Integer): Boolean
    var
        PurchaseHeader: Record "Purchase Header";
        ResultArray: JsonArray;
        OrderJson: JsonObject;
        StartDate, EndDate : Date;
    begin
        PurchaseHeader.SetRange("Document Type", PurchaseHeader."Document Type"::Order);
        if Intent."Date Filter" <> 0D then
            PurchaseHeader.SetRange("Order Date", Intent."Date Filter")
        else if Intent."Date Range" <> Intent."Date Range"::None then begin
            GetDateRange(Intent."Date Range", StartDate, EndDate);
            PurchaseHeader.SetRange("Order Date", StartDate, EndDate);
        end;

        if not PurchaseHeader.FindSet() then exit(true);

        RecordCount := 0;
        repeat
            RecordCount += 1;
            if (Intent."Top N" > 0) and (RecordCount > Intent."Top N") then break;
            Clear(OrderJson);
            OrderJson.Add('no', PurchaseHeader."No.");
            OrderJson.Add('orderDate', Format(PurchaseHeader."Order Date"));
            OrderJson.Add('vendorName', PurchaseHeader."Buy-from Vendor Name");
            PurchaseHeader.CalcFields(Amount);
            OrderJson.Add('amount', PurchaseHeader.Amount);
            ResultArray.Add(OrderJson);
        until PurchaseHeader.Next() = 0;

        ResultData.Add('purchaseOrders', ResultArray);
        exit(true);
    end;

    local procedure QueryPurchaseQuotes(Intent: Record "NXR Voice Query Intent" temporary; var ResultData: JsonObject; var RecordCount: Integer): Boolean
    var
        PurchaseHeader: Record "Purchase Header";
        ResultArray: JsonArray;
        QuoteJson: JsonObject;
    begin
        PurchaseHeader.SetRange("Document Type", PurchaseHeader."Document Type"::Quote);
        if not PurchaseHeader.FindSet() then exit(true);

        RecordCount := 0;
        repeat
            RecordCount += 1;
            if (Intent."Top N" > 0) and (RecordCount > Intent."Top N") then break;
            Clear(QuoteJson);
            QuoteJson.Add('no', PurchaseHeader."No.");
            QuoteJson.Add('documentDate', Format(PurchaseHeader."Document Date"));
            QuoteJson.Add('vendorName', PurchaseHeader."Buy-from Vendor Name");
            ResultArray.Add(QuoteJson);
        until PurchaseHeader.Next() = 0;

        ResultData.Add('purchaseQuotes', ResultArray);
        exit(true);
    end;

    local procedure QueryPurchaseInvoices(Intent: Record "NXR Voice Query Intent" temporary; var ResultData: JsonObject; var RecordCount: Integer): Boolean
    var
        PurchInvHeader: Record "Purch. Inv. Header";
        ResultArray: JsonArray;
        InvoiceJson: JsonObject;
        StartDate, EndDate : Date;
    begin
        if Intent."Date Filter" <> 0D then
            PurchInvHeader.SetRange("Posting Date", Intent."Date Filter")
        else if Intent."Date Range" <> Intent."Date Range"::None then begin
            GetDateRange(Intent."Date Range", StartDate, EndDate);
            PurchInvHeader.SetRange("Posting Date", StartDate, EndDate);
        end;

        if not PurchInvHeader.FindSet() then exit(true);

        RecordCount := 0;
        repeat
            RecordCount += 1;
            if (Intent."Top N" > 0) and (RecordCount > Intent."Top N") then break;
            Clear(InvoiceJson);
            InvoiceJson.Add('no', PurchInvHeader."No.");
            InvoiceJson.Add('postingDate', Format(PurchInvHeader."Posting Date"));
            InvoiceJson.Add('vendorName', PurchInvHeader."Buy-from Vendor Name");
            PurchInvHeader.CalcFields("Amount Including VAT");
            InvoiceJson.Add('amount', PurchInvHeader."Amount Including VAT");
            ResultArray.Add(InvoiceJson);
        until PurchInvHeader.Next() = 0;

        ResultData.Add('purchaseInvoices', ResultArray);
        exit(true);
    end;

    local procedure QueryPurchaseCreditMemos(Intent: Record "NXR Voice Query Intent" temporary; var ResultData: JsonObject; var RecordCount: Integer): Boolean
    var
        PurchCrMemoHdr: Record "Purch. Cr. Memo Hdr.";
        ResultArray: JsonArray;
        CreditJson: JsonObject;
    begin
        if not PurchCrMemoHdr.FindSet() then exit(true);

        RecordCount := 0;
        repeat
            RecordCount += 1;
            if (Intent."Top N" > 0) and (RecordCount > Intent."Top N") then break;
            Clear(CreditJson);
            CreditJson.Add('no', PurchCrMemoHdr."No.");
            CreditJson.Add('postingDate', Format(PurchCrMemoHdr."Posting Date"));
            CreditJson.Add('vendorName', PurchCrMemoHdr."Buy-from Vendor Name");
            ResultArray.Add(CreditJson);
        until PurchCrMemoHdr.Next() = 0;

        ResultData.Add('purchaseCreditMemos', ResultArray);
        exit(true);
    end;

    local procedure QueryPurchaseReceipts(Intent: Record "NXR Voice Query Intent" temporary; var ResultData: JsonObject; var RecordCount: Integer): Boolean
    var
        PurchRcptHeader: Record "Purch. Rcpt. Header";
        ResultArray: JsonArray;
        ReceiptJson: JsonObject;
    begin
        if not PurchRcptHeader.FindSet() then exit(true);

        RecordCount := 0;
        repeat
            RecordCount += 1;
            if (Intent."Top N" > 0) and (RecordCount > Intent."Top N") then break;
            Clear(ReceiptJson);
            ReceiptJson.Add('no', PurchRcptHeader."No.");
            ReceiptJson.Add('postingDate', Format(PurchRcptHeader."Posting Date"));
            ReceiptJson.Add('vendorName', PurchRcptHeader."Buy-from Vendor Name");
            ResultArray.Add(ReceiptJson);
        until PurchRcptHeader.Next() = 0;

        ResultData.Add('purchaseReceipts', ResultArray);
        exit(true);
    end;

    // ========== LEDGER ENTRY QUERIES ==========

    local procedure QueryGLEntries(Intent: Record "NXR Voice Query Intent" temporary; var ResultData: JsonObject; var RecordCount: Integer): Boolean
    var
        GLEntry: Record "G/L Entry";
        ResultArray: JsonArray;
        EntryJson: JsonObject;
        StartDate, EndDate : Date;
    begin
        if Intent."Date Filter" <> 0D then
            GLEntry.SetRange("Posting Date", Intent."Date Filter")
        else if Intent."Date Range" <> Intent."Date Range"::None then begin
            GetDateRange(Intent."Date Range", StartDate, EndDate);
            GLEntry.SetRange("Posting Date", StartDate, EndDate);
        end;

        if not GLEntry.FindSet() then exit(true);

        RecordCount := 0;
        repeat
            RecordCount += 1;
            if (Intent."Top N" > 0) and (RecordCount > Intent."Top N") then break;
            Clear(EntryJson);
            EntryJson.Add('entryNo', GLEntry."Entry No.");
            EntryJson.Add('postingDate', Format(GLEntry."Posting Date"));
            EntryJson.Add('glAccountNo', GLEntry."G/L Account No.");
            EntryJson.Add('amount', GLEntry.Amount);
            EntryJson.Add('description', GLEntry.Description);
            ResultArray.Add(EntryJson);
        until GLEntry.Next() = 0;

        ResultData.Add('glEntries', ResultArray);
        exit(true);
    end;

    local procedure QueryCustomerLedgerEntries(Intent: Record "NXR Voice Query Intent" temporary; var ResultData: JsonObject; var RecordCount: Integer): Boolean
    var
        CustLedgerEntry: Record "Cust. Ledger Entry";
        ResultArray: JsonArray;
        EntryJson: JsonObject;
    begin
        if not CustLedgerEntry.FindSet() then exit(true);

        RecordCount := 0;
        repeat
            RecordCount += 1;
            if (Intent."Top N" > 0) and (RecordCount > Intent."Top N") then break;
            Clear(EntryJson);
            EntryJson.Add('entryNo', CustLedgerEntry."Entry No.");
            EntryJson.Add('customerNo', CustLedgerEntry."Customer No.");
            EntryJson.Add('postingDate', Format(CustLedgerEntry."Posting Date"));
            CustLedgerEntry.CalcFields(Amount, "Remaining Amount");
            EntryJson.Add('amount', CustLedgerEntry.Amount);
            EntryJson.Add('remainingAmount', CustLedgerEntry."Remaining Amount");
            ResultArray.Add(EntryJson);
        until CustLedgerEntry.Next() = 0;

        ResultData.Add('customerLedgerEntries', ResultArray);
        exit(true);
    end;

    local procedure QueryVendorLedgerEntries(Intent: Record "NXR Voice Query Intent" temporary; var ResultData: JsonObject; var RecordCount: Integer): Boolean
    var
        VendorLedgerEntry: Record "Vendor Ledger Entry";
        ResultArray: JsonArray;
        EntryJson: JsonObject;
    begin
        if not VendorLedgerEntry.FindSet() then exit(true);

        RecordCount := 0;
        repeat
            RecordCount += 1;
            if (Intent."Top N" > 0) and (RecordCount > Intent."Top N") then break;
            Clear(EntryJson);
            EntryJson.Add('entryNo', VendorLedgerEntry."Entry No.");
            EntryJson.Add('vendorNo', VendorLedgerEntry."Vendor No.");
            EntryJson.Add('postingDate', Format(VendorLedgerEntry."Posting Date"));
            VendorLedgerEntry.CalcFields(Amount, "Remaining Amount");
            EntryJson.Add('amount', VendorLedgerEntry.Amount);
            EntryJson.Add('remainingAmount', VendorLedgerEntry."Remaining Amount");
            ResultArray.Add(EntryJson);
        until VendorLedgerEntry.Next() = 0;

        ResultData.Add('vendorLedgerEntries', ResultArray);
        exit(true);
    end;

    local procedure QueryItemLedgerEntries(Intent: Record "NXR Voice Query Intent" temporary; var ResultData: JsonObject; var RecordCount: Integer): Boolean
    var
        ItemLedgerEntry: Record "Item Ledger Entry";
        ResultArray: JsonArray;
        EntryJson: JsonObject;
    begin
        if not ItemLedgerEntry.FindSet() then exit(true);

        RecordCount := 0;
        repeat
            RecordCount += 1;
            if (Intent."Top N" > 0) and (RecordCount > Intent."Top N") then break;
            Clear(EntryJson);
            EntryJson.Add('entryNo', ItemLedgerEntry."Entry No.");
            EntryJson.Add('itemNo', ItemLedgerEntry."Item No.");
            EntryJson.Add('postingDate', Format(ItemLedgerEntry."Posting Date"));
            EntryJson.Add('quantity', ItemLedgerEntry.Quantity);
            EntryJson.Add('locationCode', ItemLedgerEntry."Location Code");
            ResultArray.Add(EntryJson);
        until ItemLedgerEntry.Next() = 0;

        ResultData.Add('itemLedgerEntries', ResultArray);
        exit(true);
    end;

    // ========== JOB QUERIES ==========

    local procedure QueryJobs(Intent: Record "NXR Voice Query Intent" temporary; var ResultData: JsonObject; var RecordCount: Integer): Boolean
    var
        Job: Record Job;
        ResultArray: JsonArray;
        JobJson: JsonObject;
    begin
        if Intent."Specific Filter" <> '' then
            Job.SetFilter("No.", '@' + Intent."Specific Filter" + '*');

        if not Job.FindSet() then exit(true);

        RecordCount := 0;
        repeat
            RecordCount += 1;
            if (Intent."Top N" > 0) and (RecordCount > Intent."Top N") then break;
            Clear(JobJson);
            JobJson.Add('no', Job."No.");
            JobJson.Add('description', Job.Description);
            JobJson.Add('status', Format(Job.Status));
            JobJson.Add('billToCustomerNo', Job."Bill-to Customer No.");
            ResultArray.Add(JobJson);
        until Job.Next() = 0;

        ResultData.Add('jobs', ResultArray);
        exit(true);
    end;
}
