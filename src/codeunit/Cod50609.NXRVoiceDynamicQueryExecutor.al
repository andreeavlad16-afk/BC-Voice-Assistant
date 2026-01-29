/// <summary>
/// Advanced query executor that handles complex linked entity queries.
/// Supports joins between customers, items, vendors via transactional tables (sales/purchase lines).
/// </summary>
codeunit 50609 "NXR Voice Dynamic Query Exec."
{
    // Dynamic query executor that handles linked entity queries
    // Supports Customer<->Item, Vendor<->Item relationships via transactional tables

    /// <summary>
    /// Executes a structured query from JSON, supporting linked entity relationships.
    /// </summary>
    /// <param name="QueryJson">JSON object containing the structured query with intent, entities, and filters.</param>
    /// <param name="ResultData">JSON object containing the query results.</param>
    /// <param name="RecordCount">Number of records returned.</param>
    /// <param name="ResponseText">Natural language response text for the user.</param>
    /// <returns>True if execution succeeded, false otherwise.</returns>
    procedure ExecuteStructuredQuery(QueryJson: JsonObject; var ResultData: JsonObject; var RecordCount: Integer; var ResponseText: Text): Boolean
    var
        Intent: Text;
        PrimaryEntity: Text;
        LinkedEntity: JsonToken;
    begin
        Intent := GetJsonText(QueryJson, 'intent');
        PrimaryEntity := GetJsonText(QueryJson, 'primaryEntity');

        // Check for linked entity query (joins)
        if QueryJson.Get('linkedEntity', LinkedEntity) then begin
            if LinkedEntity.IsObject() then
                exit(ExecuteLinkedQuery(PrimaryEntity, LinkedEntity.AsObject(), QueryJson, ResultData, RecordCount, ResponseText))
            else
                exit(ExecuteSimpleQuery(PrimaryEntity, QueryJson, ResultData, RecordCount, ResponseText));
        end else
            exit(ExecuteSimpleQuery(PrimaryEntity, QueryJson, ResultData, RecordCount, ResponseText));
    end;

    // ============================================================================
    // LINKED ENTITY QUERIES (Joins via transactional tables)
    // ============================================================================
    local procedure ExecuteLinkedQuery(PrimaryEntity: Text; LinkedEntityJson: JsonObject; QueryJson: JsonObject; var ResultData: JsonObject; var RecordCount: Integer; var ResponseText: Text): Boolean
    var
        LinkedEntityName: Text;
    begin
        LinkedEntityName := GetJsonText(LinkedEntityJson, 'entity');

        case true of
            // Customer -> Item: Find customers who bought specific items
            (PrimaryEntity = 'Customer') and (LinkedEntityName = 'Item'):
                exit(FindCustomersWhoOrderedItem(LinkedEntityJson, QueryJson, ResultData, RecordCount, ResponseText));

            // Item -> Customer: Find items ordered by specific customer
            (PrimaryEntity = 'Item') and (LinkedEntityName = 'Customer'):
                exit(FindItemsOrderedByCustomer(LinkedEntityJson, QueryJson, ResultData, RecordCount, ResponseText));

            // Vendor -> Item: Find vendors who supply specific items
            (PrimaryEntity = 'Vendor') and (LinkedEntityName = 'Item'):
                exit(FindVendorsWhoSupplyItem(LinkedEntityJson, QueryJson, ResultData, RecordCount, ResponseText));

            // Item -> Vendor: Find items supplied by specific vendor
            (PrimaryEntity = 'Item') and (LinkedEntityName = 'Vendor'):
                exit(FindItemsFromVendor(LinkedEntityJson, QueryJson, ResultData, RecordCount, ResponseText));

            else
                // Fallback to simple query
                exit(ExecuteSimpleQuery(PrimaryEntity, QueryJson, ResultData, RecordCount, ResponseText));
        end;
    end;

    local procedure FindCustomersWhoOrderedItem(LinkedEntityJson: JsonObject; QueryJson: JsonObject; var ResultData: JsonObject; var RecordCount: Integer; var ResponseText: Text): Boolean
    var
        SalesLine: Record "Sales Line";
        SalesInvoiceLine: Record "Sales Invoice Line";
        Customer: Record Customer;
        Item: Record Item;
        FilterToken: JsonToken;
        FilterObj: JsonObject;
        ItemFilter: Text;
        CustomerNos: List of [Code[20]];
        CustomerNo: Code[20];
        ResultArray: JsonArray;
        CustomerJson: JsonObject;
        TopN: Integer;
        TotalAmount: Decimal;
        ItemDescription: Text;
    begin
        // Get the item filter from linked entity
        if LinkedEntityJson.Get('filter', FilterToken) then begin
            if FilterToken.IsObject() then begin
                FilterObj := FilterToken.AsObject();
                ItemFilter := GetJsonText(FilterObj, 'Description');
            end;
            if ItemFilter = '' then
                ItemFilter := GetJsonText(FilterObj, 'No.');
        end;

        // Find the item(s) matching the filter
        if ItemFilter <> '' then begin
            Item.SetFilter(Description, '@*' + ItemFilter + '*');
            if not Item.FindFirst() then begin
                Item.Reset();
                Item.SetFilter("No.", '@*' + ItemFilter + '*');
                if not Item.FindFirst() then begin
                    ResponseText := StrSubstNo('I could not find any items matching "%1".', ItemFilter);
                    exit(true);
                end;
            end;
            ItemDescription := Item.Description;
        end;

        // Search in Sales Lines (open orders)
        SalesLine.SetRange("Document Type", SalesLine."Document Type"::Order);
        if ItemFilter <> '' then
            SalesLine.SetFilter("No.", Item."No.");

        if SalesLine.FindSet() then
            repeat
                if not CustomerNos.Contains(SalesLine."Sell-to Customer No.") then
                    CustomerNos.Add(SalesLine."Sell-to Customer No.");
            until SalesLine.Next() = 0;

        // Also search in Posted Sales Invoice Lines (historical)
        if ItemFilter <> '' then
            SalesInvoiceLine.SetFilter("No.", Item."No.");

        if SalesInvoiceLine.FindSet() then
            repeat
                if not CustomerNos.Contains(SalesInvoiceLine."Sell-to Customer No.") then
                    CustomerNos.Add(SalesInvoiceLine."Sell-to Customer No.");
            until SalesInvoiceLine.Next() = 0;

        // Get TopN if specified
        TopN := GetJsonInteger(QueryJson, 'top');
        if TopN = 0 then
            TopN := 10; // Default limit

        // Build result with customer details
        RecordCount := 0;
        foreach CustomerNo in CustomerNos do begin
            if Customer.Get(CustomerNo) then begin
                RecordCount += 1;
                if RecordCount > TopN then
                    break;

                Clear(CustomerJson);
                CustomerJson.Add('no', Customer."No.");
                CustomerJson.Add('name', Customer.Name);
                CustomerJson.Add('city', Customer.City);
                Customer.CalcFields("Balance (LCY)", "Sales (LCY)");
                CustomerJson.Add('balance', Customer."Balance (LCY)");
                CustomerJson.Add('sales', Customer."Sales (LCY)");
                TotalAmount += Customer."Sales (LCY)";
                ResultArray.Add(CustomerJson);
            end;
        end;

        ResultData.Add('customers', ResultArray);
        ResultData.Add('totalSales', TotalAmount);

        // Build natural language response
        if RecordCount = 0 then
            ResponseText := StrSubstNo('No customers have ordered %1.', ItemDescription)
        else if RecordCount = 1 then
            ResponseText := StrSubstNo('1 customer has ordered %1: %2.', ItemDescription, GetFirstCustomerName(ResultArray))
        else
            ResponseText := StrSubstNo('%1 customers have ordered %2. Top customers: %3.', RecordCount, ItemDescription, GetTopCustomerNames(ResultArray, 3));

        exit(true);
    end;

    local procedure FindItemsOrderedByCustomer(LinkedEntityJson: JsonObject; QueryJson: JsonObject; var ResultData: JsonObject; var RecordCount: Integer; var ResponseText: Text): Boolean
    var
        SalesLine: Record "Sales Line";
        SalesInvoiceLine: Record "Sales Invoice Line";
        Customer: Record Customer;
        Item: Record Item;
        FilterToken: JsonToken;
        FilterObj: JsonObject;
        CustomerFilter: Text;
        ItemNos: List of [Code[20]];
        ItemNo: Code[20];
        ResultArray: JsonArray;
        ItemJson: JsonObject;
        TopN: Integer;
        CustomerName: Text;
    begin
        // Get the customer filter
        if LinkedEntityJson.Get('filter', FilterToken) then begin
            if FilterToken.IsObject() then begin
                FilterObj := FilterToken.AsObject();
                CustomerFilter := GetJsonText(FilterObj, 'No.');
                if CustomerFilter = '' then
                    CustomerFilter := GetJsonText(FilterObj, 'Name');
            end;
        end;

        // Find the customer
        if CustomerFilter <> '' then begin
            Customer.SetFilter(Name, '@*' + CustomerFilter + '*');
            if not Customer.FindFirst() then begin
                Customer.Reset();
                Customer.SetFilter("No.", '@*' + CustomerFilter + '*');
                if not Customer.FindFirst() then begin
                    ResponseText := StrSubstNo('I could not find a customer matching "%1".', CustomerFilter);
                    exit(true);
                end;
            end;
            CustomerName := Customer.Name;
        end;

        // Search in Sales Lines
        SalesLine.SetRange("Document Type", SalesLine."Document Type"::Order);
        if CustomerFilter <> '' then
            SalesLine.SetRange("Sell-to Customer No.", Customer."No.");
        SalesLine.SetFilter(Type, '%1', SalesLine.Type::Item);

        if SalesLine.FindSet() then
            repeat
                if (SalesLine."No." <> '') and (not ItemNos.Contains(SalesLine."No.")) then
                    ItemNos.Add(SalesLine."No.");
            until SalesLine.Next() = 0;

        // Also check posted invoices
        if CustomerFilter <> '' then
            SalesInvoiceLine.SetRange("Sell-to Customer No.", Customer."No.");
        SalesInvoiceLine.SetFilter(Type, '%1', SalesInvoiceLine.Type::Item);

        if SalesInvoiceLine.FindSet() then
            repeat
                if (SalesInvoiceLine."No." <> '') and (not ItemNos.Contains(SalesInvoiceLine."No.")) then
                    ItemNos.Add(SalesInvoiceLine."No.");
            until SalesInvoiceLine.Next() = 0;

        // Get TopN
        TopN := GetJsonInteger(QueryJson, 'top');
        if TopN = 0 then
            TopN := 10;

        // Build result
        RecordCount := 0;
        foreach ItemNo in ItemNos do begin
            if Item.Get(ItemNo) then begin
                RecordCount += 1;
                if RecordCount > TopN then
                    break;

                Clear(ItemJson);
                ItemJson.Add('no', Item."No.");
                ItemJson.Add('description', Item.Description);
                ItemJson.Add('unitPrice', Item."Unit Price");
                Item.CalcFields(Inventory);
                ItemJson.Add('inventory', Item.Inventory);
                ResultArray.Add(ItemJson);
            end;
        end;

        ResultData.Add('items', ResultArray);

        if RecordCount = 0 then
            ResponseText := StrSubstNo('Customer %1 has not ordered any items.', CustomerName)
        else if RecordCount = 1 then
            ResponseText := StrSubstNo('%1 has ordered 1 item: %2.', CustomerName, GetFirstItemDescription(ResultArray))
        else
            ResponseText := StrSubstNo('%1 has ordered %2 different items, including %3.', CustomerName, RecordCount, GetTopItemDescriptions(ResultArray, 3));

        exit(true);
    end;

    local procedure FindVendorsWhoSupplyItem(LinkedEntityJson: JsonObject; QueryJson: JsonObject; var ResultData: JsonObject; var RecordCount: Integer; var ResponseText: Text): Boolean
    var
        PurchaseLine: Record "Purchase Line";
        Vendor: Record Vendor;
        Item: Record Item;
        FilterToken: JsonToken;
        FilterObj: JsonObject;
        ItemFilter: Text;
        VendorNos: List of [Code[20]];
        VendorNo: Code[20];
        ResultArray: JsonArray;
        VendorJson: JsonObject;
        TopN: Integer;
        ItemDescription: Text;
        InventoryFilter: Text;
    begin
        // Get item filter
        if LinkedEntityJson.Get('filter', FilterToken) then begin
            if FilterToken.IsObject() then begin
                FilterObj := FilterToken.AsObject();
                ItemFilter := GetJsonText(FilterObj, 'Description');
                if ItemFilter = '' then
                    ItemFilter := GetJsonText(FilterObj, 'No.');
                InventoryFilter := GetJsonText(FilterObj, 'Inventory');
            end;
        end;

        // Handle "items with low stock" query
        if (InventoryFilter <> '') or (ItemFilter = '') then begin
            // Find items with low inventory and their vendors
            if InventoryFilter.StartsWith('<') then
                Item.SetFilter(Inventory, InventoryFilter)
            else
                Item.SetFilter(Inventory, '<10'); // Default low stock threshold

            if Item.FindSet() then
                repeat
                    // Find vendors for this item via purchase lines
                    PurchaseLine.SetRange(Type, PurchaseLine.Type::Item);
                    PurchaseLine.SetRange("No.", Item."No.");
                    if PurchaseLine.FindSet() then
                        repeat
                            if not VendorNos.Contains(PurchaseLine."Buy-from Vendor No.") then
                                VendorNos.Add(PurchaseLine."Buy-from Vendor No.");
                        until PurchaseLine.Next() = 0;
                until Item.Next() = 0;

            ItemDescription := 'low stock items';
        end else begin
            // Find specific item
            Item.SetFilter(Description, '@*' + ItemFilter + '*');
            if not Item.FindFirst() then begin
                Item.Reset();
                Item.SetFilter("No.", '@*' + ItemFilter + '*');
                if not Item.FindFirst() then begin
                    ResponseText := StrSubstNo('I could not find any items matching "%1".', ItemFilter);
                    exit(true);
                end;
            end;
            ItemDescription := Item.Description;

            // Find vendors via purchase lines
            PurchaseLine.SetRange(Type, PurchaseLine.Type::Item);
            PurchaseLine.SetRange("No.", Item."No.");
            if PurchaseLine.FindSet() then
                repeat
                    if not VendorNos.Contains(PurchaseLine."Buy-from Vendor No.") then
                        VendorNos.Add(PurchaseLine."Buy-from Vendor No.");
                until PurchaseLine.Next() = 0;
        end;

        // Get TopN
        TopN := GetJsonInteger(QueryJson, 'top');
        if TopN = 0 then
            TopN := 10;

        // Build result
        RecordCount := 0;
        foreach VendorNo in VendorNos do begin
            if Vendor.Get(VendorNo) then begin
                RecordCount += 1;
                if RecordCount > TopN then
                    break;

                Clear(VendorJson);
                VendorJson.Add('no', Vendor."No.");
                VendorJson.Add('name', Vendor.Name);
                VendorJson.Add('city', Vendor.City);
                Vendor.CalcFields("Balance (LCY)");
                VendorJson.Add('balance', Vendor."Balance (LCY)");
                ResultArray.Add(VendorJson);
            end;
        end;

        ResultData.Add('vendors', ResultArray);

        if RecordCount = 0 then
            ResponseText := StrSubstNo('No vendors found supplying %1.', ItemDescription)
        else if RecordCount = 1 then
            ResponseText := StrSubstNo('1 vendor supplies %1: %2.', ItemDescription, GetFirstVendorName(ResultArray))
        else
            ResponseText := StrSubstNo('%1 vendors supply %2: %3.', RecordCount, ItemDescription, GetTopVendorNames(ResultArray, 3));

        exit(true);
    end;

    local procedure FindItemsFromVendor(LinkedEntityJson: JsonObject; QueryJson: JsonObject; var ResultData: JsonObject; var RecordCount: Integer; var ResponseText: Text): Boolean
    var
        PurchaseLine: Record "Purchase Line";
        Vendor: Record Vendor;
        Item: Record Item;
        FilterToken: JsonToken;
        FilterObj: JsonObject;
        VendorFilter: Text;
        ItemNos: List of [Code[20]];
        ItemNo: Code[20];
        ResultArray: JsonArray;
        ItemJson: JsonObject;
        TopN: Integer;
        VendorName: Text;
    begin
        // Get vendor filter
        if LinkedEntityJson.Get('filter', FilterToken) then begin
            if FilterToken.IsObject() then begin
                FilterObj := FilterToken.AsObject();
                VendorFilter := GetJsonText(FilterObj, 'Name');
                if VendorFilter = '' then
                    VendorFilter := GetJsonText(FilterObj, 'No.');
            end;
        end;

        // Find vendor
        if VendorFilter <> '' then begin
            Vendor.SetFilter(Name, '@*' + VendorFilter + '*');
            if not Vendor.FindFirst() then begin
                Vendor.Reset();
                Vendor.SetFilter("No.", '@*' + VendorFilter + '*');
                if not Vendor.FindFirst() then begin
                    ResponseText := StrSubstNo('I could not find a vendor matching "%1".', VendorFilter);
                    exit(true);
                end;
            end;
            VendorName := Vendor.Name;
        end;

        // Find items from this vendor via purchase lines
        PurchaseLine.SetRange(Type, PurchaseLine.Type::Item);
        if VendorFilter <> '' then
            PurchaseLine.SetRange("Buy-from Vendor No.", Vendor."No.");

        if PurchaseLine.FindSet() then
            repeat
                if (PurchaseLine."No." <> '') and (not ItemNos.Contains(PurchaseLine."No.")) then
                    ItemNos.Add(PurchaseLine."No.");
            until PurchaseLine.Next() = 0;

        // Get TopN
        TopN := GetJsonInteger(QueryJson, 'top');
        if TopN = 0 then
            TopN := 10;

        // Build result
        RecordCount := 0;
        foreach ItemNo in ItemNos do begin
            if Item.Get(ItemNo) then begin
                RecordCount += 1;
                if RecordCount > TopN then
                    break;

                Clear(ItemJson);
                ItemJson.Add('no', Item."No.");
                ItemJson.Add('description', Item.Description);
                ItemJson.Add('unitPrice', Item."Unit Price");
                ItemJson.Add('unitCost', Item."Unit Cost");
                Item.CalcFields(Inventory);
                ItemJson.Add('inventory', Item.Inventory);
                ResultArray.Add(ItemJson);
            end;
        end;

        ResultData.Add('items', ResultArray);

        if RecordCount = 0 then
            ResponseText := StrSubstNo('No items found from vendor %1.', VendorName)
        else if RecordCount = 1 then
            ResponseText := StrSubstNo('We buy 1 item from %1: %2.', VendorName, GetFirstItemDescription(ResultArray))
        else
            ResponseText := StrSubstNo('We buy %1 items from %2, including %3.', RecordCount, VendorName, GetTopItemDescriptions(ResultArray, 3));

        exit(true);
    end;

    // ============================================================================
    // SIMPLE ENTITY QUERIES
    // ============================================================================
    local procedure ExecuteSimpleQuery(PrimaryEntity: Text; QueryJson: JsonObject; var ResultData: JsonObject; var RecordCount: Integer; var ResponseText: Text): Boolean
    begin
        case PrimaryEntity of
            'Customer':
                exit(QueryCustomers(QueryJson, ResultData, RecordCount, ResponseText));
            'Item':
                exit(QueryItems(QueryJson, ResultData, RecordCount, ResponseText));
            'Vendor':
                exit(QueryVendors(QueryJson, ResultData, RecordCount, ResponseText));
            'Employee':
                exit(QueryEmployees(QueryJson, ResultData, RecordCount, ResponseText));
            'SalesOrder':
                exit(QuerySalesOrders(QueryJson, ResultData, RecordCount, ResponseText));
            'SalesInvoice':
                exit(QuerySalesInvoices(QueryJson, ResultData, RecordCount, ResponseText));
            'Location':
                exit(QueryLocations(QueryJson, ResultData, RecordCount, ResponseText));
            'PurchaseOrder':
                exit(QueryPurchaseOrders(QueryJson, ResultData, RecordCount, ResponseText));
            else begin
                ResponseText := 'I don''t know how to query that type of data yet.';
                exit(false);
            end;
        end;
    end;

    local procedure QueryCustomers(QueryJson: JsonObject; var ResultData: JsonObject; var RecordCount: Integer; var ResponseText: Text): Boolean
    var
        Customer: Record Customer;
        ResultArray: JsonArray;
        CustomerJson: JsonObject;
        TopN: Integer;
        SortField: Text;
        SortDir: Text;
        TotalBalance: Decimal;
        TotalSales: Decimal;
        DebugJson: Text;
        DebugInfo: Text;
        Setup: Record "NXR Voice Assistant Setup";
    begin
        // DEBUG: Capture what JSON we received (if debug mode enabled)
        if Setup.Get() and Setup."Debug Mode" then begin
            QueryJson.WriteTo(DebugJson);
            DebugInfo := '\\\\[DEBUG] QueryCustomers received JSON: ' + DebugJson;
        end;

        ApplyFiltersFromJson(QueryJson, Customer);

        // Handle sorting
        SortField := GetSortField(QueryJson);
        SortDir := GetSortDirection(QueryJson);

        if Setup.Get() and Setup."Debug Mode" then
            DebugInfo += '\\[DEBUG] Initial SortField=' + SortField + ', SortDir=' + SortDir;

        TopN := GetJsonInteger(QueryJson, 'top');

        if Setup.Get() and Setup."Debug Mode" then
            DebugInfo += '\\[DEBUG] Initial TopN=' + Format(TopN);

        // Apply intelligent default sorting if none specified
        // For customers, the most meaningful default is by Sales (LCY) DESC
        if SortField = '' then begin
            SortField := 'Sales (LCY)';
            SortDir := 'DESC';
            if Setup.Get() and Setup."Debug Mode" then
                DebugInfo += '\\[DEBUG] Applied default sort - SortField=' + SortField + ', SortDir=' + SortDir;
        end;

        // Apply default top limit if not specified (prevents returning too many records)
        if TopN = 0 then
            TopN := 10;

        if SortField <> '' then begin
            case SortField of
                'Balance (LCY)', 'balance':
                    Customer.SetCurrentKey("Balance (LCY)");
                'Sales (LCY)', 'sales':
                    Customer.SetCurrentKey("Sales (LCY)");
                'Name', 'name':
                    Customer.SetCurrentKey(Name);
            end;
            Customer.Ascending(SortDir <> 'DESC');
        end;

        if not Customer.FindSet() then begin
            ResponseText := 'No customers found matching your criteria.';
            RecordCount := 0;
            exit(true);
        end;

        RecordCount := 0;
        repeat
            RecordCount += 1;
            if RecordCount > TopN then
                break;

            Clear(CustomerJson);
            CustomerJson.Add('no', Customer."No.");
            CustomerJson.Add('name', Customer.Name);
            CustomerJson.Add('city', Customer.City);
            Customer.CalcFields("Balance (LCY)", "Sales (LCY)");
            CustomerJson.Add('balance', Customer."Balance (LCY)");
            CustomerJson.Add('sales', Customer."Sales (LCY)");
            TotalBalance += Customer."Balance (LCY)";
            TotalSales += Customer."Sales (LCY)";
            ResultArray.Add(CustomerJson);
        until Customer.Next() = 0;

        ResultData.Add('customers', ResultArray);
        ResultData.Add('totalBalance', TotalBalance);
        ResultData.Add('totalSales', TotalSales);

        // Prepend debug info to response if debug mode enabled
        if Setup.Get() and Setup."Debug Mode" then
            ResponseText := DebugInfo;

        if RecordCount = 1 then
            ResponseText += StrSubstNo('\\Found 1 customer: %1.', GetFirstCustomerName(ResultArray))
        else begin
            // Show what the results are sorted by for clarity
            if (SortField = 'Sales (LCY)') or (SortField = 'sales') then
                ResponseText += StrSubstNo('\\Here are your top %1 customers by sales. Total sales: %2. Top: %3.', RecordCount, Format(TotalSales, 0, '<Precision,2:2><Standard Format,0>'), GetTopCustomerNames(ResultArray, 3))
            else if (SortField = 'Balance (LCY)') or (SortField = 'balance') then
                ResponseText += StrSubstNo('\\Here are your top %1 customers by balance. Total balance: %2. Top: %3.', RecordCount, Format(TotalBalance, 0, '<Precision,2:2><Standard Format,0>'), GetTopCustomerNames(ResultArray, 3))
            else
                ResponseText += StrSubstNo('\\Found %1 customers. Total sales: %2, balance: %3.', RecordCount, Format(TotalSales, 0, '<Precision,2:2><Standard Format,0>'), Format(TotalBalance, 0, '<Precision,2:2><Standard Format,0>'))
        end;

        exit(true);
    end;

    local procedure QueryItems(QueryJson: JsonObject; var ResultData: JsonObject; var RecordCount: Integer; var ResponseText: Text): Boolean
    var
        Item: Record Item;
        ResultArray: JsonArray;
        ItemJson: JsonObject;
        TopN: Integer;
        SortField: Text;
        SortDir: Text;
        LowStockCount: Integer;
        Setup: Record "NXR Voice Assistant Setup";
        DebugJson: Text;
        DebugInfo: Text;
    begin
        // DEBUG: Capture query JSON
        if Setup.Get() and Setup."Debug Mode" then begin
            QueryJson.WriteTo(DebugJson);
            DebugInfo := '\\\\[DEBUG] QueryItems received JSON: ' + DebugJson;
        end;

        ApplyFiltersFromJson(QueryJson, Item);

        SortField := GetSortField(QueryJson);
        SortDir := GetSortDirection(QueryJson);

        TopN := GetJsonInteger(QueryJson, 'top');

        if Setup.Get() and Setup."Debug Mode" then
            DebugInfo += '\\[DEBUG] Initial - SortField=' + SortField + ', SortDir=' + SortDir + ', TopN=' + Format(TopN);

        // Apply intelligent default sorting if none specified
        if SortField = '' then begin
            SortField := 'Inventory';
            SortDir := 'DESC';
            if Setup.Get() and Setup."Debug Mode" then
                DebugInfo += '\\[DEBUG] Applied defaults - SortField=' + SortField + ', SortDir=' + SortDir;
        end;

        // Apply default top limit if not specified
        if TopN = 0 then
            TopN := 10;

        if SortField <> '' then begin
            case SortField of
                'Inventory', 'inventory':
                    Item.SetCurrentKey(Inventory);
                'Unit Price', 'price':
                    Item.SetCurrentKey("Unit Price");
                'Description', 'description':
                    Item.SetCurrentKey(Description);
            end;
            Item.Ascending(SortDir <> 'DESC');
        end;

        if not Item.FindSet() then begin
            ResponseText := 'No items found matching your criteria.';
            RecordCount := 0;
            exit(true);
        end;

        RecordCount := 0;
        repeat
            RecordCount += 1;
            if RecordCount > TopN then
                break;

            Clear(ItemJson);
            ItemJson.Add('no', Item."No.");
            ItemJson.Add('description', Item.Description);
            ItemJson.Add('unitPrice', Item."Unit Price");
            Item.CalcFields(Inventory);
            ItemJson.Add('inventory', Item.Inventory);
            if Item.Inventory < Item."Reorder Point" then
                LowStockCount += 1;
            ResultArray.Add(ItemJson);
        until Item.Next() = 0;

        ResultData.Add('items', ResultArray);
        ResultData.Add('lowStockCount', LowStockCount);

        // Prepend debug info to response if debug mode enabled
        if Setup.Get() and Setup."Debug Mode" then
            ResponseText := DebugInfo;

        if RecordCount = 1 then
            ResponseText += StrSubstNo('\\Found 1 item: %1.', GetFirstItemDescription(ResultArray))
        else if LowStockCount > 0 then
            ResponseText += StrSubstNo('\\Found %1 items. %2 items are below reorder point.', RecordCount, LowStockCount)
        else
            ResponseText += StrSubstNo('\\Found %1 items.', RecordCount);

        exit(true);
    end;

    local procedure QueryVendors(QueryJson: JsonObject; var ResultData: JsonObject; var RecordCount: Integer; var ResponseText: Text): Boolean
    var
        Vendor: Record Vendor;
        ResultArray: JsonArray;
        VendorJson: JsonObject;
        TopN: Integer;
        SortField: Text;
        SortDir: Text;
        TotalOwed: Decimal;
    begin
        ApplyFiltersFromJson(QueryJson, Vendor);

        // Handle sorting
        SortField := GetSortField(QueryJson);
        SortDir := GetSortDirection(QueryJson);
        if SortField <> '' then begin
            case SortField of
                'Balance (LCY)', 'balance':
                    Vendor.SetCurrentKey("Balance (LCY)");
                'Name', 'name':
                    Vendor.SetCurrentKey(Name);
            end;
            Vendor.Ascending(SortDir <> 'DESC');
        end else begin
            // Default: Sort by balance descending for meaningful "top" results
            Vendor.SetCurrentKey("Balance (LCY)");
            Vendor.Ascending(false);
        end;

        TopN := GetJsonInteger(QueryJson, 'top');
        if TopN = 0 then
            TopN := 10;

        if not Vendor.FindSet() then begin
            ResponseText := 'No vendors found.';
            RecordCount := 0;
            exit(true);
        end;

        RecordCount := 0;
        repeat
            RecordCount += 1;
            if RecordCount > TopN then
                break;

            Clear(VendorJson);
            VendorJson.Add('no', Vendor."No.");
            VendorJson.Add('name', Vendor.Name);
            VendorJson.Add('city', Vendor.City);
            Vendor.CalcFields("Balance (LCY)");
            VendorJson.Add('balance', Vendor."Balance (LCY)");
            TotalOwed += Vendor."Balance (LCY)";
            ResultArray.Add(VendorJson);
        until Vendor.Next() = 0;

        ResultData.Add('vendors', ResultArray);
        ResultData.Add('totalOwed', TotalOwed);

        if RecordCount = 1 then
            ResponseText := StrSubstNo('Found 1 vendor: %1. Total owed: %2.', GetFirstVendorName(ResultArray), Format(TotalOwed, 0, '<Precision,2:2><Standard Format,0>'))
        else if TopN < 100 then
            ResponseText := StrSubstNo('Top %1 vendors. Total owed: %2. Top vendors: %3.', RecordCount, Format(TotalOwed, 0, '<Precision,2:2><Standard Format,0>'), GetTopVendorNames(ResultArray, 3))
        else
            ResponseText := StrSubstNo('Found %1 vendors. Total owed: %2.', RecordCount, Format(TotalOwed, 0, '<Precision,2:2><Standard Format,0>'));

        exit(true);
    end;

    local procedure QuerySalesOrders(QueryJson: JsonObject; var ResultData: JsonObject; var RecordCount: Integer; var ResponseText: Text): Boolean
    var
        SalesHeader: Record "Sales Header";
        ResultArray: JsonArray;
        OrderJson: JsonObject;
        TopN: Integer;
        StartDate: Date;
        EndDate: Date;
        TotalAmount: Decimal;
        DateFilterValue: Text;
    begin
        SalesHeader.SetRange("Document Type", SalesHeader."Document Type"::Order);

        // Apply date filter
        DateFilterValue := GetDateFilterValue(QueryJson);
        if DateFilterValue <> '' then begin
            GetDateRangeFromText(DateFilterValue, StartDate, EndDate);
            if StartDate <> 0D then
                SalesHeader.SetRange("Order Date", StartDate, EndDate);
        end;

        TopN := GetJsonInteger(QueryJson, 'top');
        if TopN = 0 then
            TopN := 50;

        if not SalesHeader.FindSet() then begin
            if DateFilterValue <> '' then
                ResponseText := StrSubstNo('No orders found for %1.', DateFilterValue)
            else
                ResponseText := 'No open orders found.';
            RecordCount := 0;
            exit(true);
        end;

        RecordCount := 0;
        repeat
            RecordCount += 1;
            if RecordCount > TopN then
                break;

            Clear(OrderJson);
            OrderJson.Add('no', SalesHeader."No.");
            OrderJson.Add('orderDate', Format(SalesHeader."Order Date"));
            OrderJson.Add('customerName', SalesHeader."Sell-to Customer Name");
            SalesHeader.CalcFields(Amount);
            OrderJson.Add('amount', SalesHeader.Amount);
            TotalAmount += SalesHeader.Amount;
            ResultArray.Add(OrderJson);
        until SalesHeader.Next() = 0;

        ResultData.Add('orders', ResultArray);
        ResultData.Add('totalAmount', TotalAmount);

        if DateFilterValue <> '' then
            ResponseText := StrSubstNo('Found %1 orders for %2 totalling %3.', RecordCount, DateFilterValue, Format(TotalAmount, 0, '<Precision,2:2><Standard Format,0>'))
        else
            ResponseText := StrSubstNo('Found %1 open orders totalling %2.', RecordCount, Format(TotalAmount, 0, '<Precision,2:2><Standard Format,0>'));

        exit(true);
    end;

    local procedure QuerySalesInvoices(QueryJson: JsonObject; var ResultData: JsonObject; var RecordCount: Integer; var ResponseText: Text): Boolean
    var
        SalesInvoiceHeader: Record "Sales Invoice Header";
        ResultArray: JsonArray;
        InvoiceJson: JsonObject;
        TopN: Integer;
        StartDate: Date;
        EndDate: Date;
        TotalAmount: Decimal;
        DateFilterValue: Text;
    begin
        DateFilterValue := GetDateFilterValue(QueryJson);
        if DateFilterValue <> '' then begin
            GetDateRangeFromText(DateFilterValue, StartDate, EndDate);
            if StartDate <> 0D then
                SalesInvoiceHeader.SetRange("Posting Date", StartDate, EndDate);
        end;

        TopN := GetJsonInteger(QueryJson, 'top');
        if TopN = 0 then
            TopN := 50;

        if not SalesInvoiceHeader.FindSet() then begin
            if DateFilterValue <> '' then
                ResponseText := StrSubstNo('No invoices found for %1.', DateFilterValue)
            else
                ResponseText := 'No invoices found.';
            RecordCount := 0;
            exit(true);
        end;

        RecordCount := 0;
        repeat
            RecordCount += 1;
            if RecordCount > TopN then
                break;

            Clear(InvoiceJson);
            InvoiceJson.Add('no', SalesInvoiceHeader."No.");
            InvoiceJson.Add('postingDate', Format(SalesInvoiceHeader."Posting Date"));
            InvoiceJson.Add('customerName', SalesInvoiceHeader."Sell-to Customer Name");
            SalesInvoiceHeader.CalcFields("Amount Including VAT");
            InvoiceJson.Add('amount', SalesInvoiceHeader."Amount Including VAT");
            TotalAmount += SalesInvoiceHeader."Amount Including VAT";
            ResultArray.Add(InvoiceJson);
        until SalesInvoiceHeader.Next() = 0;

        ResultData.Add('invoices', ResultArray);
        ResultData.Add('totalAmount', TotalAmount);

        if DateFilterValue <> '' then
            ResponseText := StrSubstNo('Found %1 invoices for %2 totalling %3.', RecordCount, DateFilterValue, Format(TotalAmount, 0, '<Precision,2:2><Standard Format,0>'))
        else
            ResponseText := StrSubstNo('Found %1 invoices totalling %2.', RecordCount, Format(TotalAmount, 0, '<Precision,2:2><Standard Format,0>'));

        exit(true);
    end;

    local procedure QueryEmployees(QueryJson: JsonObject; var ResultData: JsonObject; var RecordCount: Integer; var ResponseText: Text): Boolean
    var
        Employee: Record Employee;
        ResultArray: JsonArray;
        EmployeeJson: JsonObject;
        TopN: Integer;
        SortField: Text;
        SortDir: Text;
        CompanyFilter: Text;
    begin
        ApplyFiltersFromJson(QueryJson, Employee);

        // Handle sorting
        SortField := GetSortField(QueryJson);
        SortDir := GetSortDirection(QueryJson);
        if SortField <> '' then begin
            case SortField of
                'Last Name', 'lastname':
                    Employee.SetCurrentKey("Last Name");
                'First Name', 'firstname':
                    Employee.SetCurrentKey("First Name");
            end;
            Employee.Ascending(SortDir <> 'DESC');
        end else begin
            // Default: Sort by last name for alphabetical listing
            Employee.SetCurrentKey("Last Name");
            Employee.Ascending(true);
        end;

        TopN := GetJsonInteger(QueryJson, 'top');
        if TopN = 0 then
            TopN := 50;

        if not Employee.FindSet() then begin
            ResponseText := 'No employees found matching your criteria.';
            RecordCount := 0;
            exit(true);
        end;

        RecordCount := 0;
        repeat
            RecordCount += 1;
            if RecordCount > TopN then
                break;

            Clear(EmployeeJson);
            EmployeeJson.Add('no', Employee."No.");
            EmployeeJson.Add('firstName', Employee."First Name");
            EmployeeJson.Add('lastName', Employee."Last Name");
            EmployeeJson.Add('jobTitle', Employee."Job Title");
            EmployeeJson.Add('email', Employee."E-Mail");
            ResultArray.Add(EmployeeJson);
        until Employee.Next() = 0;

        ResultData.Add('employees', ResultArray);

        if RecordCount = 1 then
            ResponseText := StrSubstNo('Found 1 employee: %1 %2.', GetFirstEmployeeFirstName(ResultArray), GetFirstEmployeeLastName(ResultArray))
        else
            ResponseText := StrSubstNo('Found %1 employees.', RecordCount);

        exit(true);
    end;

    local procedure QueryLocations(QueryJson: JsonObject; var ResultData: JsonObject; var RecordCount: Integer; var ResponseText: Text): Boolean
    var
        Location: Record Location;
        ResultArray: JsonArray;
        LocationJson: JsonObject;
        TopN: Integer;
        SortField: Text;
        SortDir: Text;
    begin
        ApplyFiltersFromJson(QueryJson, Location);

        // Handle sorting
        SortField := GetSortField(QueryJson);
        SortDir := GetSortDirection(QueryJson);
        if SortField <> '' then begin
            case SortField of
                'Name', 'name':
                    Location.SetCurrentKey(Name);
                'Code', 'code':
                    Location.SetCurrentKey(Code);
            end;
            Location.Ascending(SortDir <> 'DESC');
        end else begin
            // Default: Sort by code
            Location.SetCurrentKey(Code);
            Location.Ascending(true);
        end;

        TopN := GetJsonInteger(QueryJson, 'top');
        if TopN = 0 then
            TopN := 50;

        if not Location.FindSet() then begin
            ResponseText := 'No locations found matching your criteria.';
            RecordCount := 0;
            exit(true);
        end;

        RecordCount := 0;
        repeat
            RecordCount += 1;
            if RecordCount > TopN then
                break;

            Clear(LocationJson);
            LocationJson.Add('code', Location.Code);
            LocationJson.Add('name', Location.Name);
            LocationJson.Add('useAsInTransit', Location."Use As In-Transit");
            ResultArray.Add(LocationJson);
        until Location.Next() = 0;

        ResultData.Add('locations', ResultArray);

        if RecordCount = 1 then
            ResponseText := StrSubstNo('Found 1 location: %1.', GetFirstLocationName(ResultArray))
        else
            ResponseText := StrSubstNo('Found %1 locations.', RecordCount);

        exit(true);
    end;

    local procedure QueryPurchaseOrders(QueryJson: JsonObject; var ResultData: JsonObject; var RecordCount: Integer; var ResponseText: Text): Boolean
    var
        PurchaseHeader: Record "Purchase Header";
        ResultArray: JsonArray;
        OrderJson: JsonObject;
        TopN: Integer;
        StartDate: Date;
        EndDate: Date;
        TotalAmount: Decimal;
        DateFilterValue: Text;
    begin
        PurchaseHeader.SetRange("Document Type", PurchaseHeader."Document Type"::Order);

        // Apply date filter
        DateFilterValue := GetDateFilterValue(QueryJson);
        if DateFilterValue <> '' then begin
            GetDateRangeFromText(DateFilterValue, StartDate, EndDate);
            if StartDate <> 0D then
                PurchaseHeader.SetRange("Order Date", StartDate, EndDate);
        end;

        TopN := GetJsonInteger(QueryJson, 'top');
        if TopN = 0 then
            TopN := 50;

        if not PurchaseHeader.FindSet() then begin
            if DateFilterValue <> '' then
                ResponseText := StrSubstNo('No purchase orders found for %1.', DateFilterValue)
            else
                ResponseText := 'No open purchase orders found.';
            RecordCount := 0;
            exit(true);
        end;

        RecordCount := 0;
        repeat
            RecordCount += 1;
            if RecordCount > TopN then
                break;

            Clear(OrderJson);
            OrderJson.Add('no', PurchaseHeader."No.");
            OrderJson.Add('orderDate', Format(PurchaseHeader."Order Date"));
            OrderJson.Add('vendorName', PurchaseHeader."Buy-from Vendor Name");
            PurchaseHeader.CalcFields(Amount);
            OrderJson.Add('amount', PurchaseHeader.Amount);
            TotalAmount += PurchaseHeader.Amount;
            ResultArray.Add(OrderJson);
        until PurchaseHeader.Next() = 0;

        ResultData.Add('purchaseOrders', ResultArray);
        ResultData.Add('totalAmount', TotalAmount);

        if RecordCount = 1 then
            ResponseText := StrSubstNo('Found 1 purchase order. Total: %1.', Format(TotalAmount, 0, '<Precision,2:2><Standard Format,0>'))
        else
            ResponseText := StrSubstNo('Found %1 purchase orders. Total: %2.', RecordCount, Format(TotalAmount, 0, '<Precision,2:2><Standard Format,0>'));

        exit(true);
    end;

    // ============================================================================
    // HELPER FUNCTIONS
    // ============================================================================
    local procedure GetJsonText(JObject: JsonObject; PropertyName: Text): Text
    var
        JToken: JsonToken;
    begin
        if JObject.Get(PropertyName, JToken) then
            if JToken.IsValue() then
                exit(JToken.AsValue().AsText());
        exit('');
    end;

    local procedure GetJsonInteger(JObject: JsonObject; PropertyName: Text): Integer
    var
        JToken: JsonToken;
    begin
        if JObject.Get(PropertyName, JToken) then
            if JToken.IsValue() then
                exit(JToken.AsValue().AsInteger());
        exit(0);
    end;

    local procedure GetSortField(QueryJson: JsonObject): Text
    var
        SortToken: JsonToken;
        SortObj: JsonObject;
    begin
        if QueryJson.Get('sort', SortToken) then begin
            if SortToken.IsObject() then begin
                SortObj := SortToken.AsObject();
                exit(GetJsonText(SortObj, 'field'));
            end;
        end;
        exit('');
    end;

    local procedure GetSortDirection(QueryJson: JsonObject): Text
    var
        SortToken: JsonToken;
        SortObj: JsonObject;
    begin
        if QueryJson.Get('sort', SortToken) then begin
            if SortToken.IsObject() then begin
                SortObj := SortToken.AsObject();
                exit(GetJsonText(SortObj, 'direction'));
            end;
        end;
        exit('');
    end;

    local procedure GetDateFilterValue(QueryJson: JsonObject): Text
    var
        DateToken: JsonToken;
        DateObj: JsonObject;
    begin
        if QueryJson.Get('dateFilter', DateToken) then begin
            if DateToken.IsObject() then begin
                DateObj := DateToken.AsObject();
                exit(GetJsonText(DateObj, 'value'));
            end;
        end;
        exit('');
    end;

    local procedure GetDateRangeFromText(DateText: Text; var StartDate: Date; var EndDate: Date)
    begin
        EndDate := Today;
        case LowerCase(DateText) of
            'today':
                StartDate := Today;
            'yesterday':
                begin
                    StartDate := Today - 1;
                    EndDate := Today - 1;
                end;
            'this week':
                StartDate := CalcDate('<-CW>', Today);
            'last week':
                begin
                    StartDate := CalcDate('<-CW-1W>', Today);
                    EndDate := CalcDate('<CW-1W>', Today);
                end;
            'this month':
                StartDate := CalcDate('<-CM>', Today);
            'last month':
                begin
                    StartDate := CalcDate('<-CM-1M>', Today);
                    EndDate := CalcDate('<CM-1M>', Today);
                end;
            'this quarter':
                StartDate := CalcDate('<-CQ>', Today);
            'this year':
                StartDate := CalcDate('<-CY>', Today);
            'last year':
                begin
                    StartDate := CalcDate('<-CY-1Y>', Today);
                    EndDate := CalcDate('<CY-1Y>', Today);
                end;
            else
                StartDate := 0D;
        end;
    end;

    local procedure ParseDateValue(DateValue: Text): Date
    begin
        // Parse special date keywords that AI might send
        case UpperCase(DateValue) of
            'TODAY':
                exit(Today);
            'YESTERDAY':
                exit(Today - 1);
            'STARTOFMONTH', 'FIRSTDAYOFMONTH':
                exit(CalcDate('<-CM>', Today));
            'ENDOFMONTH', 'LASTDAYOFMONTH':
                exit(CalcDate('<CM>', Today));
            'STARTOFWEEK':
                exit(CalcDate('<-CW>', Today));
            'ENDOFWEEK':
                exit(CalcDate('<CW>', Today));
            'STARTOFYEAR', 'FIRSTDAYOFYEAR':
                exit(CalcDate('<-CY>', Today));
            'ENDOFYEAR', 'LASTDAYOFYEAR':
                exit(CalcDate('<CY>', Today));
            'STARTOFQUARTER':
                exit(CalcDate('<-CQ>', Today));
            else
                exit(0D); // Invalid or actual date string
        end;
    end;

    local procedure ApplyFiltersFromJson(QueryJson: JsonObject; var RecRef: RecordRef)
    begin
        // TODO: Implement generic filter application from JSON
    end;

    local procedure ApplyFiltersFromJson(QueryJson: JsonObject; var Customer: Record Customer)
    var
        FiltersToken: JsonToken;
        FiltersArray: JsonArray;
        FilterToken: JsonToken;
        FilterObj: JsonObject;
        FieldName: Text;
        Operator: Text;
        FilterValue: Text;
        i: Integer;
    begin
        if not QueryJson.Get('filters', FiltersToken) then
            exit;

        if not FiltersToken.IsArray() then
            exit;

        FiltersArray := FiltersToken.AsArray();
        for i := 0 to FiltersArray.Count - 1 do begin
            FiltersArray.Get(i, FilterToken);
            if FilterToken.IsObject() then begin
                FilterObj := FilterToken.AsObject();
                FieldName := GetJsonText(FilterObj, 'field');
                Operator := GetJsonText(FilterObj, 'operator');
                FilterValue := GetJsonText(FilterObj, 'value');

                case FieldName of
                    'City':
                        Customer.SetFilter(City, '@*' + FilterValue + '*');
                    'Balance (LCY)':
                        Customer.SetFilter("Balance (LCY)", Operator + FilterValue);
                end;
            end;
        end;
    end;

    local procedure ApplyFiltersFromJson(QueryJson: JsonObject; var Item: Record Item)
    var
        FiltersToken: JsonToken;
        FiltersArray: JsonArray;
        FilterToken: JsonToken;
        FilterObj: JsonObject;
        FieldName: Text;
        Operator: Text;
        FilterValue: Text;
        i: Integer;
    begin
        if not QueryJson.Get('filters', FiltersToken) then
            exit;

        if not FiltersToken.IsArray() then
            exit;

        FiltersArray := FiltersToken.AsArray();
        for i := 0 to FiltersArray.Count - 1 do begin
            FiltersArray.Get(i, FilterToken);
            if FilterToken.IsObject() then begin
                FilterObj := FilterToken.AsObject();
                FieldName := GetJsonText(FilterObj, 'field');
                Operator := GetJsonText(FilterObj, 'operator');
                FilterValue := GetJsonText(FilterObj, 'value');

                case FieldName of
                    'Inventory':
                        Item.SetFilter(Inventory, Operator + FilterValue);
                    'Description':
                        Item.SetFilter(Description, '@*' + FilterValue + '*');
                    'Item Category Code':
                        Item.SetFilter("Item Category Code", FilterValue);
                end;
            end;
        end;
    end;

    local procedure ApplyFiltersFromJson(QueryJson: JsonObject; var Vendor: Record Vendor)
    var
        FiltersToken: JsonToken;
        FiltersArray: JsonArray;
        FilterToken: JsonToken;
        FilterObj: JsonObject;
        FieldName: Text;
        Operator: Text;
        FilterValue: Text;
        i: Integer;
    begin
        if not QueryJson.Get('filters', FiltersToken) then
            exit;

        if not FiltersToken.IsArray() then
            exit;

        FiltersArray := FiltersToken.AsArray();
        for i := 0 to FiltersArray.Count - 1 do begin
            FiltersArray.Get(i, FilterToken);
            if FilterToken.IsObject() then begin
                FilterObj := FilterToken.AsObject();
                FieldName := GetJsonText(FilterObj, 'field');
                Operator := GetJsonText(FilterObj, 'operator');
                FilterValue := GetJsonText(FilterObj, 'value');

                case FieldName of
                    'City':
                        Vendor.SetFilter(City, '@*' + FilterValue + '*');
                    'Balance (LCY)':
                        Vendor.SetFilter("Balance (LCY)", Operator + FilterValue);
                    'Name':
                        Vendor.SetFilter(Name, '@*' + FilterValue + '*');
                end;
            end;
        end;
    end;

    local procedure ApplyFiltersFromJson(QueryJson: JsonObject; var Employee: Record Employee)
    var
        FiltersToken: JsonToken;
        FiltersArray: JsonArray;
        FilterToken: JsonToken;
        FilterObj: JsonObject;
        FieldName: Text;
        Operator: Text;
        FilterValue: Text;
        i: Integer;
    begin
        if not QueryJson.Get('filters', FiltersToken) then
            exit;

        if not FiltersToken.IsArray() then
            exit;

        FiltersArray := FiltersToken.AsArray();
        for i := 0 to FiltersArray.Count - 1 do begin
            FiltersArray.Get(i, FilterToken);
            if FilterToken.IsObject() then begin
                FilterObj := FilterToken.AsObject();
                FieldName := GetJsonText(FilterObj, 'field');
                Operator := GetJsonText(FilterObj, 'operator');
                FilterValue := GetJsonText(FilterObj, 'value');

                case FieldName of
                    'First Name', 'firstname':
                        Employee.SetFilter("First Name", '@*' + FilterValue + '*');
                    'Last Name', 'lastname':
                        Employee.SetFilter("Last Name", '@*' + FilterValue + '*');
                    'Job Title', 'jobtitle':
                        Employee.SetFilter("Job Title", '@*' + FilterValue + '*');
                end;
            end;
        end;
    end;

    local procedure ApplyFiltersFromJson(QueryJson: JsonObject; var SalesHeader: Record "Sales Header")
    var
        FiltersToken: JsonToken;
        FiltersArray: JsonArray;
        FilterToken: JsonToken;
        FilterObj: JsonObject;
        FieldName: Text;
        Operator: Text;
        FilterValue: Text;
        DateValue: Date;
        i: Integer;
    begin
        if not QueryJson.Get('filters', FiltersToken) then
            exit;

        if not FiltersToken.IsArray() then
            exit;

        FiltersArray := FiltersToken.AsArray();
        for i := 0 to FiltersArray.Count - 1 do begin
            FiltersArray.Get(i, FilterToken);
            if FilterToken.IsObject() then begin
                FilterObj := FilterToken.AsObject();
                FieldName := GetJsonText(FilterObj, 'field');
                Operator := GetJsonText(FilterObj, 'operator');
                FilterValue := GetJsonText(FilterObj, 'value');

                case FieldName of
                    'Status':
                        case LowerCase(FilterValue) of
                            'open':
                                SalesHeader.SetRange(Status, SalesHeader.Status::Open);
                            'released':
                                SalesHeader.SetRange(Status, SalesHeader.Status::Released);
                            'pending approval':
                                SalesHeader.SetRange(Status, SalesHeader.Status::"Pending Approval");
                        end;
                    'Order Date', 'OrderDate':
                        begin
                            DateValue := ParseDateValue(FilterValue);
                            if DateValue <> 0D then
                                SalesHeader.SetFilter("Order Date", Operator + Format(DateValue));
                        end;
                    'Sell-to Customer No.', 'CustomerNo':
                        SalesHeader.SetFilter("Sell-to Customer No.", '@*' + FilterValue + '*');
                    'Amount':
                        SalesHeader.SetFilter(Amount, Operator + FilterValue);
                end;
            end;
        end;
    end;

    local procedure ApplyFiltersFromJson(QueryJson: JsonObject; var Location: Record Location)
    var
        FiltersToken: JsonToken;
        FiltersArray: JsonArray;
        FilterToken: JsonToken;
        FilterObj: JsonObject;
        FieldName: Text;
        Operator: Text;
        FilterValue: Text;
        i: Integer;
    begin
        if not QueryJson.Get('filters', FiltersToken) then
            exit;

        if not FiltersToken.IsArray() then
            exit;

        FiltersArray := FiltersToken.AsArray();
        for i := 0 to FiltersArray.Count - 1 do begin
            FiltersArray.Get(i, FilterToken);
            if FilterToken.IsObject() then begin
                FilterObj := FilterToken.AsObject();
                FieldName := GetJsonText(FilterObj, 'field');
                Operator := GetJsonText(FilterObj, 'operator');
                FilterValue := GetJsonText(FilterObj, 'value');

                case FieldName of
                    'Code', 'code':
                        Location.SetFilter(Code, '@*' + FilterValue + '*');
                    'Name', 'name':
                        Location.SetFilter(Name, '@*' + FilterValue + '*');
                    'Use As In-Transit', 'UseAsInTransit':
                        if LowerCase(FilterValue) = 'true' then
                            Location.SetRange("Use As In-Transit", true)
                        else if LowerCase(FilterValue) = 'false' then
                            Location.SetRange("Use As In-Transit", false);
                end;
            end;
        end;
    end;

    local procedure ApplyFiltersFromJson(QueryJson: JsonObject; var PurchaseHeader: Record "Purchase Header")
    var
        FiltersToken: JsonToken;
        FiltersArray: JsonArray;
        FilterToken: JsonToken;
        FilterObj: JsonObject;
        FieldName: Text;
        Operator: Text;
        FilterValue: Text;
        DateValue: Date;
        i: Integer;
    begin
        if not QueryJson.Get('filters', FiltersToken) then
            exit;

        if not FiltersToken.IsArray() then
            exit;

        FiltersArray := FiltersToken.AsArray();
        for i := 0 to FiltersArray.Count - 1 do begin
            FiltersArray.Get(i, FilterToken);
            if FilterToken.IsObject() then begin
                FilterObj := FilterToken.AsObject();
                FieldName := GetJsonText(FilterObj, 'field');
                Operator := GetJsonText(FilterObj, 'operator');
                FilterValue := GetJsonText(FilterObj, 'value');

                case FieldName of
                    'Status':
                        case LowerCase(FilterValue) of
                            'open':
                                PurchaseHeader.SetRange(Status, PurchaseHeader.Status::Open);
                            'released':
                                PurchaseHeader.SetRange(Status, PurchaseHeader.Status::Released);
                            'pending approval':
                                PurchaseHeader.SetRange(Status, PurchaseHeader.Status::"Pending Approval");
                        end;
                    'Order Date', 'OrderDate':
                        begin
                            DateValue := ParseDateValue(FilterValue);
                            if DateValue <> 0D then
                                PurchaseHeader.SetFilter("Order Date", Operator + Format(DateValue));
                        end;
                    'Buy-from Vendor No.', 'VendorNo':
                        PurchaseHeader.SetFilter("Buy-from Vendor No.", '@*' + FilterValue + '*');
                    'Amount':
                        PurchaseHeader.SetFilter(Amount, Operator + FilterValue);
                end;
            end;
        end;
    end;

    // Result formatting helpers
    local procedure GetFirstCustomerName(ResultArray: JsonArray): Text
    var
        FirstToken: JsonToken;
        FirstObj: JsonObject;
    begin
        if ResultArray.Get(0, FirstToken) then begin
            if FirstToken.IsObject() then begin
                FirstObj := FirstToken.AsObject();
                exit(GetJsonText(FirstObj, 'name'));
            end;
        end;
        exit('');
    end;

    local procedure GetTopCustomerNames(ResultArray: JsonArray; MaxCount: Integer): Text
    var
        Token: JsonToken;
        Obj: JsonObject;
        Names: Text;
        i: Integer;
    begin
        for i := 0 to MinInt(MaxCount - 1, ResultArray.Count - 1) do begin
            if ResultArray.Get(i, Token) then begin
                if Token.IsObject() then begin
                    Obj := Token.AsObject();
                    if Names <> '' then
                        Names += ', ';
                    Names += GetJsonText(Obj, 'name');
                end;
            end;
        end;
        exit(Names);
    end;

    local procedure GetFirstItemDescription(ResultArray: JsonArray): Text
    var
        FirstToken: JsonToken;
        FirstObj: JsonObject;
    begin
        if ResultArray.Get(0, FirstToken) then begin
            if FirstToken.IsObject() then begin
                FirstObj := FirstToken.AsObject();
                exit(GetJsonText(FirstObj, 'description'));
            end;
        end;
        exit('');
    end;

    local procedure GetTopItemDescriptions(ResultArray: JsonArray; MaxCount: Integer): Text
    var
        Token: JsonToken;
        Obj: JsonObject;
        Descriptions: Text;
        i: Integer;
    begin
        for i := 0 to MinInt(MaxCount - 1, ResultArray.Count - 1) do begin
            if ResultArray.Get(i, Token) then begin
                if Token.IsObject() then begin
                    Obj := Token.AsObject();
                    if Descriptions <> '' then
                        Descriptions += ', ';
                    Descriptions += GetJsonText(Obj, 'description');
                end;
            end;
        end;
        exit(Descriptions);
    end;

    local procedure GetFirstVendorName(ResultArray: JsonArray): Text
    var
        FirstToken: JsonToken;
        FirstObj: JsonObject;
    begin
        if ResultArray.Get(0, FirstToken) then begin
            if FirstToken.IsObject() then begin
                FirstObj := FirstToken.AsObject();
                exit(GetJsonText(FirstObj, 'name'));
            end;
        end;
        exit('');
    end;

    local procedure GetTopVendorNames(ResultArray: JsonArray; MaxCount: Integer): Text
    var
        Token: JsonToken;
        Obj: JsonObject;
        Names: Text;
        i: Integer;
    begin
        for i := 0 to MinInt(MaxCount - 1, ResultArray.Count - 1) do begin
            if ResultArray.Get(i, Token) then begin
                if Token.IsObject() then begin
                    Obj := Token.AsObject();
                    if Names <> '' then
                        Names += ', ';
                    Names += GetJsonText(Obj, 'name');
                end;
            end;
        end;
        exit(Names);
    end;

    local procedure GetFirstEmployeeFirstName(ResultArray: JsonArray): Text
    var
        FirstToken: JsonToken;
        FirstObj: JsonObject;
    begin
        if ResultArray.Get(0, FirstToken) then begin
            if FirstToken.IsObject() then begin
                FirstObj := FirstToken.AsObject();
                exit(GetJsonText(FirstObj, 'firstName'));
            end;
        end;
        exit('');
    end;

    local procedure GetFirstEmployeeLastName(ResultArray: JsonArray): Text
    var
        FirstToken: JsonToken;
        FirstObj: JsonObject;
    begin
        if ResultArray.Get(0, FirstToken) then begin
            if FirstToken.IsObject() then begin
                FirstObj := FirstToken.AsObject();
                exit(GetJsonText(FirstObj, 'lastName'));
            end;
        end;
        exit('');
    end;

    local procedure GetFirstLocationName(ResultArray: JsonArray): Text
    var
        FirstToken: JsonToken;
        FirstObj: JsonObject;
    begin
        if ResultArray.Get(0, FirstToken) then begin
            if FirstToken.IsObject() then begin
                FirstObj := FirstToken.AsObject();
                exit(GetJsonText(FirstObj, 'name'));
            end;
        end;
        exit('');
    end;

    local procedure MinInt(A: Integer; B: Integer): Integer
    begin
        if A < B then
            exit(A);
        exit(B);
    end;
}
