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
                if RecordCount >= TopN then
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
                if RecordCount >= TopN then
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
                if RecordCount >= TopN then
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
                if RecordCount >= TopN then
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
    var
        TableNo: Integer;
        GroupByToken: JsonToken;
    begin
        // Check if this is a GROUP BY query
        if QueryJson.Get('groupBy', GroupByToken) then begin
            // Route to grouped aggregation executor
            TableNo := GetTableNumber(PrimaryEntity);
            if TableNo = 0 then begin
                ResponseText := StrSubstNo('Unknown entity type: %1', PrimaryEntity);
                exit(false);
            end;
            exit(ExecuteGroupedQuery(TableNo, PrimaryEntity, QueryJson, ResultData, RecordCount, ResponseText));
        end;

        // Map entity name to table number
        TableNo := GetTableNumber(PrimaryEntity);
        if TableNo = 0 then begin
            ResponseText := StrSubstNo('Unknown entity type: %1', PrimaryEntity);
            exit(false);
        end;

        // Use generic query executor for all entities
        exit(ExecuteGenericQuery(TableNo, PrimaryEntity, QueryJson, ResultData, RecordCount, ResponseText));
    end;

    local procedure GetTableNumber(EntityName: Text): Integer
    begin
        case EntityName of
            'Customer':
                exit(DATABASE::Customer);
            'Vendor':
                exit(DATABASE::Vendor);
            'Item':
                exit(DATABASE::Item);
            'Employee':
                exit(DATABASE::Employee);
            'Location':
                exit(DATABASE::Location);
            'SalesOrder', 'Sales Order', 'SalesHeader', 'Sales Header':
                exit(DATABASE::"Sales Header");
            'SalesLine', 'Sales Line':
                exit(DATABASE::"Sales Line");
            'SalesInvoice', 'Sales Invoice', 'SalesInvoiceHeader':
                exit(DATABASE::"Sales Invoice Header");
            'PurchaseOrder', 'Purchase Order', 'PurchaseHeader', 'Purchase Header':
                exit(DATABASE::"Purchase Header");
            'PurchaseLine', 'Purchase Line':
                exit(DATABASE::"Purchase Line");
            'BankAccount', 'Bank Account':
                exit(DATABASE::"Bank Account");
            'Dimension':
                exit(DATABASE::Dimension);
            'DimensionValue', 'Dimension Value':
                exit(DATABASE::"Dimension Value");
            'G/L Entry', 'GLEntry':
                exit(DATABASE::"G/L Entry");
            else
                exit(0);
        end;
    end;

    local procedure ExecuteGenericQuery(TableNo: Integer; EntityName: Text; QueryJson: JsonObject; var ResultData: JsonObject; var RecordCount: Integer; var ResponseText: Text): Boolean
    var
        RecRef: RecordRef;
        ResultArray: JsonArray;
        RecordJson: JsonObject;
        TopN: Integer;
        QueryType: Text;
        Setup: Record "NXR Voice Assistant Setup";
        DebugJson: Text;
    begin
        RecRef.Open(TableNo);

        // Check for count-only query
        QueryType := GetJsonText(QueryJson, 'queryType');
        if QueryType = 'count' then begin
            RecordCount := RecRef.Count();
            RecRef.Close();
            ResultData.Add('count', RecordCount);
            ResponseText := StrSubstNo('There are %1 %2 records in the database.', RecordCount, EntityName);
            exit(true);
        end;

        // Apply filters from JSON
        ApplyGenericFilters(QueryJson, RecRef);

        // Apply sorting
        ApplyGenericSorting(QueryJson, RecRef, EntityName);

        // Get top N limit
        TopN := GetJsonInteger(QueryJson, 'top');
        if TopN = 0 then
            TopN := 10; // Default limit

        // Execute query
        if not RecRef.FindSet() then begin
            RecRef.Close();
            ResponseText := StrSubstNo('No %1 records found matching your criteria.', EntityName);
            RecordCount := 0;
            exit(true);
        end;

        // Build result array
        RecordCount := 0;
        repeat
            RecordCount += 1;
            Clear(RecordJson);

            // Add key fields dynamically based on entity
            BuildRecordJson(RecRef, EntityName, RecordJson);
            ResultArray.Add(RecordJson);

            if RecordCount >= TopN then
                break;
        until RecRef.Next() = 0;

        RecRef.Close();

        // Post-query sort if sorting by FlowField
        SortResultArrayIfNeeded(ResultArray, QueryJson, RecRef.Number());

        ResultData.Add(LowerCase(EntityName) + 's', ResultArray);
        ResultData.Add('count', RecordCount);

        // Generate intelligent response text based on query type
        ResponseText := GenerateResponseText(EntityName, RecordCount, TopN, ResultArray, QueryJson);

        exit(true);
    end;

    local procedure ExecuteGroupedQuery(TableNo: Integer; EntityName: Text; QueryJson: JsonObject; var ResultData: JsonObject; var RecordCount: Integer; var ResponseText: Text): Boolean
    var
        RecRef: RecordRef;
        GroupKeys: Dictionary of [Text, JsonObject];
        GroupKey: Text;
        GroupFieldNames: List of [Text];
        GroupFieldName: Text;
        AggFieldName: Text;
        AggFunction: Text;
        AggAlias: Text;
        AggToken: JsonToken;
        GroupData: JsonObject;
        ResultArray: JsonArray;
        EmptyArray: JsonArray;
        SortedGroups: List of [Text];
        SortField: Text;
        SortDir: Text;
        TopN: Integer;
        i: Integer;
    begin
        // Parse groupBy fields
        if not ParseGroupByFields(QueryJson, GroupFieldNames) then begin
            ResponseText := 'GROUP BY query must specify at least one groupBy field.';
            exit(false);
        end;

        // Open table and apply filters
        RecRef.Open(TableNo);
        ApplyGenericFilters(QueryJson, RecRef);

        // Iterate all matching records and build groups
        if RecRef.FindSet() then begin
            repeat
                // Build group key from groupBy field values
                GroupKey := BuildGroupKey(RecRef, GroupFieldNames);

                // Get or create group data
                if not GroupKeys.Get(GroupKey, GroupData) then begin
                    Clear(GroupData);
                    GroupData.Add('groupKey', GroupKey);
                    GroupData.Add('count', 0);
                    GroupData.Add('sum', 0.0);
                    GroupData.Add('min', 999999999.0);
                    GroupData.Add('max', -999999999.0);
                    Clear(EmptyArray);
                    GroupData.Add('values', EmptyArray);

                    // Add group field values
                    AddGroupFieldValues(RecRef, GroupFieldNames, GroupData);

                    GroupKeys.Add(GroupKey, GroupData);
                end;

                // Update aggregations
                UpdateGroupAggregations(RecRef, QueryJson, GroupData);

            until RecRef.Next() = 0;
        end;

        RecRef.Close();

        // Calculate final aggregations (AVG)
        FinalizeGroupAggregations(QueryJson, GroupKeys);

        // Sort groups by aggregated value
        SortField := GetSortField(QueryJson);
        SortDir := GetSortDirection(QueryJson);
        SortedGroups := SortGroupsByAggregation(GroupKeys, SortField, SortDir);

        // Get top N limit
        TopN := GetJsonInteger(QueryJson, 'top');
        if TopN = 0 then
            TopN := 10;

        // Build result array
        RecordCount := 0;
        foreach GroupKey in SortedGroups do begin
            if RecordCount >= TopN then
                break;

            GroupKeys.Get(GroupKey, GroupData);
            ResultArray.Add(GroupData);
            RecordCount += 1;
        end;

        ResultData.Add('groups', ResultArray);
        ResultData.Add('count', RecordCount);

        // Generate response text
        ResponseText := GenerateGroupedResponseText(EntityName, QueryJson, ResultArray, RecordCount);

        exit(true);
    end;

    local procedure ParseGroupByFields(QueryJson: JsonObject; var GroupFieldNames: List of [Text]): Boolean
    var
        GroupByToken: JsonToken;
        GroupByArray: JsonArray;
        FieldToken: JsonToken;
        i: Integer;
    begin
        if not QueryJson.Get('groupBy', GroupByToken) then
            exit(false);

        if not GroupByToken.IsArray() then
            exit(false);

        GroupByArray := GroupByToken.AsArray();
        if GroupByArray.Count() = 0 then
            exit(false);

        for i := 0 to GroupByArray.Count() - 1 do begin
            GroupByArray.Get(i, FieldToken);
            GroupFieldNames.Add(FieldToken.AsValue().AsText());
        end;

        exit(true);
    end;

    local procedure BuildGroupKey(RecRef: RecordRef; GroupFieldNames: List of [Text]): Text
    var
        FieldName: Text;
        FieldNo: Integer;
        FieldRef: FieldRef;
        GroupKey: Text;
    begin
        GroupKey := '';
        foreach FieldName in GroupFieldNames do begin
            FieldNo := GetFieldNumber(RecRef, FieldName);
            if FieldNo <> 0 then begin
                FieldRef := RecRef.Field(FieldNo);
                if GroupKey <> '' then
                    GroupKey += '|';
                GroupKey += Format(FieldRef.Value);
            end;
        end;
        exit(GroupKey);
    end;

    local procedure AddGroupFieldValues(RecRef: RecordRef; GroupFieldNames: List of [Text]; var GroupData: JsonObject)
    var
        FieldName: Text;
        FieldNo: Integer;
        FieldRef: FieldRef;
        FieldKey: Text;
    begin
        foreach FieldName in GroupFieldNames do begin
            FieldNo := GetFieldNumber(RecRef, FieldName);
            if FieldNo <> 0 then begin
                FieldRef := RecRef.Field(FieldNo);
                FieldKey := LowerCase(FieldName.Replace(' ', '').Replace('(', '').Replace(')', '').Replace('/', ''));
                GroupData.Add(FieldKey, Format(FieldRef.Value));
            end;
        end;
    end;

    local procedure UpdateGroupAggregations(RecRef: RecordRef; QueryJson: JsonObject; var GroupData: JsonObject)
    var
        AggToken: JsonToken;
        AggArray: JsonArray;
        AggObj: JsonObject;
        AggFunction: Text;
        AggField: Text;
        FieldNo: Integer;
        FieldRef: FieldRef;
        FieldValue: Decimal;
        CurrentCount: Integer;
        CurrentSum: Decimal;
        CurrentMin: Decimal;
        CurrentMax: Decimal;
        ValuesArray: JsonArray;
        i: Integer;
    begin
        // Get current aggregation values
        CurrentCount := GetJsonInteger(GroupData, 'count');
        CurrentSum := GetJsonDecimal(GroupData, 'sum');
        CurrentMin := GetJsonDecimal(GroupData, 'min');
        CurrentMax := GetJsonDecimal(GroupData, 'max');
        GroupData.Get('values', AggToken);
        ValuesArray := AggToken.AsArray();

        // Increment count
        CurrentCount += 1;
        GroupData.Replace('count', CurrentCount);

        // Process each aggregation function
        if QueryJson.Get('aggregations', AggToken) then begin
            if AggToken.IsArray() then begin
                AggArray := AggToken.AsArray();
                for i := 0 to AggArray.Count() - 1 do begin
                    AggArray.Get(i, AggToken);
                    if AggToken.IsObject() then begin
                        AggObj := AggToken.AsObject();
                        AggFunction := GetJsonText(AggObj, 'function');
                        AggField := GetJsonText(AggObj, 'field');

                        // For COUNT, we already incremented above
                        if AggFunction <> 'COUNT' then begin
                            // Get field value
                            if AggField <> '*' then begin
                                FieldNo := GetFieldNumber(RecRef, AggField);
                                if FieldNo <> 0 then begin
                                    FieldRef := RecRef.Field(FieldNo);
                                    if Evaluate(FieldValue, Format(FieldRef.Value)) then begin
                                        // Update SUM
                                        CurrentSum += FieldValue;
                                        GroupData.Replace('sum', CurrentSum);

                                        // Update MIN/MAX
                                        if FieldValue < CurrentMin then begin
                                            CurrentMin := FieldValue;
                                            GroupData.Replace('min', CurrentMin);
                                        end;
                                        if FieldValue > CurrentMax then begin
                                            CurrentMax := FieldValue;
                                            GroupData.Replace('max', CurrentMax);
                                        end;

                                        // Store value for AVG calculation
                                        ValuesArray.Add(FieldValue);
                                    end;
                                end;
                            end;
                        end;
                    end;
                end;
                GroupData.Replace('values', ValuesArray);
            end;
        end;
    end;

    local procedure FinalizeGroupAggregations(QueryJson: JsonObject; var GroupKeys: Dictionary of [Text, JsonObject])
    var
        GroupKey: Text;
        GroupData: JsonObject;
        AggToken: JsonToken;
        AggArray: JsonArray;
        AggObj: JsonObject;
        AggFunction: Text;
        AggAlias: Text;
        CurrentCount: Integer;
        CurrentSum: Decimal;
        CurrentMin: Decimal;
        CurrentMax: Decimal;
        AverageValue: Decimal;
        i: Integer;
    begin
        // Calculate final values for each group
        foreach GroupKey in GroupKeys.Keys() do begin
            GroupKeys.Get(GroupKey, GroupData);

            CurrentCount := GetJsonInteger(GroupData, 'count');
            CurrentSum := GetJsonDecimal(GroupData, 'sum');
            CurrentMin := GetJsonDecimal(GroupData, 'min');
            CurrentMax := GetJsonDecimal(GroupData, 'max');

            // Calculate average
            if CurrentCount > 0 then
                AverageValue := CurrentSum / CurrentCount
            else
                AverageValue := 0;

            GroupData.Add('avg', AverageValue);

            // Add aliased aggregation values
            if QueryJson.Get('aggregations', AggToken) then begin
                if AggToken.IsArray() then begin
                    AggArray := AggToken.AsArray();
                    for i := 0 to AggArray.Count() - 1 do begin
                        AggArray.Get(i, AggToken);
                        if AggToken.IsObject() then begin
                            AggObj := AggToken.AsObject();
                            AggFunction := GetJsonText(AggObj, 'function');
                            AggAlias := GetJsonText(AggObj, 'alias');

                            case AggFunction of
                                'COUNT':
                                    GroupData.Add(AggAlias, CurrentCount);
                                'SUM':
                                    GroupData.Add(AggAlias, CurrentSum);
                                'AVG':
                                    GroupData.Add(AggAlias, AverageValue);
                                'MIN':
                                    GroupData.Add(AggAlias, CurrentMin);
                                'MAX':
                                    GroupData.Add(AggAlias, CurrentMax);
                            end;
                        end;
                    end;
                end;
            end;

            GroupKeys.Set(GroupKey, GroupData);
        end;
    end;

    local procedure SortGroupsByAggregation(GroupKeys: Dictionary of [Text, JsonObject]; SortField: Text; SortDir: Text): List of [Text]
    var
        SortedKeys: List of [Text];
        GroupKey: Text;
        GroupData: JsonObject;
        SortValues: Dictionary of [Decimal, List of [Text]];
        SortValue: Decimal;
        KeyList: List of [Text];
        SortedValueList: List of [Decimal];
        Value: Decimal;
        GroupKeyFromList: Text;
    begin
        // Extract sort values for each group
        foreach GroupKey in GroupKeys.Keys() do begin
            GroupKeys.Get(GroupKey, GroupData);

            // Get the aggregated value to sort by
            if SortField <> '' then
                SortValue := GetJsonDecimal(GroupData, SortField)
            else
                SortValue := GetJsonInteger(GroupData, 'count'); // Default to count

            // Group keys by sort value (handle ties)
            if not SortValues.Get(SortValue, KeyList) then begin
                Clear(KeyList);
                SortValues.Add(SortValue, KeyList);
            end;
            KeyList.Add(GroupKey);
            SortValues.Set(SortValue, KeyList);
        end;

        // Sort values
        Clear(SortedValueList);
        foreach Value in SortValues.Keys() do
            SortedValueList.Add(Value);

        // Simple bubble sort (good enough for small result sets)
        BubbleSortDecimalList(SortedValueList, SortDir = 'DESC');

        // Build final sorted key list
        foreach Value in SortedValueList do begin
            SortValues.Get(Value, KeyList);
            foreach GroupKeyFromList in KeyList do
                SortedKeys.Add(GroupKeyFromList);
        end;

        exit(SortedKeys);
    end;

    local procedure BubbleSortDecimalList(var ValueList: List of [Decimal]; Descending: Boolean)
    var
        i: Integer;
        j: Integer;
        Temp: Decimal;
        Value1: Decimal;
        Value2: Decimal;
        Swapped: Boolean;
    begin
        if ValueList.Count() <= 1 then
            exit;

        for i := 0 to ValueList.Count() - 2 do begin
            Swapped := false;
            for j := 0 to ValueList.Count() - i - 2 do begin
                ValueList.Get(j, Value1);
                ValueList.Get(j + 1, Value2);

                if Descending then begin
                    if Value1 < Value2 then begin
                        ValueList.Set(j, Value2);
                        ValueList.Set(j + 1, Value1);
                        Swapped := true;
                    end;
                end else begin
                    if Value1 > Value2 then begin
                        ValueList.Set(j, Value2);
                        ValueList.Set(j + 1, Value1);
                        Swapped := true;
                    end;
                end;
            end;
            if not Swapped then
                exit;
        end;
    end;

    local procedure GenerateGroupedResponseText(EntityName: Text; QueryJson: JsonObject; ResultArray: JsonArray; RecordCount: Integer): Text
    var
        ResponseText: Text;
        GroupToken: JsonToken;
        GroupObj: JsonObject;
        AggToken: JsonToken;
        AggArray: JsonArray;
        AggObj: JsonObject;
        AggAlias: Text;
        AggValue: Text;
        GroupKeyValue: Text;
        TopN: Integer;
        i: Integer;
    begin
        TopN := GetJsonInteger(QueryJson, 'top');

        if RecordCount = 0 then
            exit(StrSubstNo('No %1 records found.', EntityName));

        // For single result (e.g., "which X has most Y"), show the winner
        if (RecordCount = 1) and (TopN = 1) then begin
            ResultArray.Get(0, GroupToken);
            if GroupToken.IsObject() then begin
                GroupObj := GroupToken.AsObject();

                // Get group key value (first groupBy field)
                GroupKeyValue := GetFirstGroupFieldValue(GroupObj, QueryJson);

                // Get aggregation value
                if QueryJson.Get('aggregations', AggToken) then begin
                    if AggToken.IsArray() then begin
                        AggArray := AggToken.AsArray();
                        if AggArray.Count() > 0 then begin
                            AggArray.Get(0, AggToken);
                            if AggToken.IsObject() then begin
                                AggObj := AggToken.AsObject();
                                AggAlias := GetJsonText(AggObj, 'alias');
                                AggValue := Format(GetJsonDecimal(GroupObj, AggAlias));

                                ResponseText := StrSubstNo('%1 has %2.', GroupKeyValue, AggValue);
                                exit(ResponseText);
                            end;
                        end;
                    end;
                end;
            end;
        end;

        // For multiple results, list them
        ResponseText := StrSubstNo('Found %1 groups:', RecordCount);
        for i := 0 to RecordCount - 1 do begin
            ResultArray.Get(i, GroupToken);
            if GroupToken.IsObject() then begin
                GroupObj := GroupToken.AsObject();
                GroupKeyValue := GetFirstGroupFieldValue(GroupObj, QueryJson);

                // Get aggregation value
                if QueryJson.Get('aggregations', AggToken) then begin
                    if AggToken.IsArray() then begin
                        AggArray := AggToken.AsArray();
                        if AggArray.Count() > 0 then begin
                            AggArray.Get(0, AggToken);
                            if AggToken.IsObject() then begin
                                AggObj := AggToken.AsObject();
                                AggAlias := GetJsonText(AggObj, 'alias');
                                AggValue := Format(GetJsonDecimal(GroupObj, AggAlias));

                                ResponseText += StrSubstNo(' %1 (%2)', GroupKeyValue, AggValue);
                                if i < RecordCount - 1 then
                                    ResponseText += ',';
                            end;
                        end;
                    end;
                end;
            end;
        end;

        exit(ResponseText);
    end;

    local procedure GetFirstGroupFieldValue(GroupObj: JsonObject; QueryJson: JsonObject): Text
    var
        GroupByToken: JsonToken;
        GroupByArray: JsonArray;
        FieldToken: JsonToken;
        FieldName: Text;
        FieldKey: Text;
    begin
        if QueryJson.Get('groupBy', GroupByToken) then begin
            if GroupByToken.IsArray() then begin
                GroupByArray := GroupByToken.AsArray();
                if GroupByArray.Count() > 0 then begin
                    GroupByArray.Get(0, FieldToken);
                    FieldName := FieldToken.AsValue().AsText();
                    FieldKey := LowerCase(FieldName.Replace(' ', '').Replace('(', '').Replace(')', '').Replace('/', ''));
                    exit(GetJsonText(GroupObj, FieldKey));
                end;
            end;
        end;
        exit('Unknown');
    end;

    local procedure GetJsonDecimal(JObject: JsonObject; PropertyName: Text): Decimal
    var
        JToken: JsonToken;
        DecValue: Decimal;
    begin
        if JObject.Get(PropertyName, JToken) then
            if JToken.IsValue() then
                if Evaluate(DecValue, JToken.AsValue().AsText()) then
                    exit(DecValue);
        exit(0);
    end;

    local procedure GenerateResponseText(EntityName: Text; RecordCount: Integer; TopN: Integer; ResultArray: JsonArray; QueryJson: JsonObject): Text
    var
        ResponseText: Text;
        SortField: Text;
        SortDir: Text;
        FirstRecord: JsonToken;
        FirstObj: JsonObject;
        KeyValue: Text;
        NameValue: Text;
        AmountValue: Text;
        DateValue: Text;
    begin
        if RecordCount = 0 then
            exit(StrSubstNo('No %1 records found.', EntityName));

        SortField := GetSortField(QueryJson);
        SortDir := GetSortDirection(QueryJson);

        // For single record queries (top:1), provide detailed info
        if (RecordCount = 1) and (TopN = 1) then begin
            ResultArray.Get(0, FirstRecord);
            if FirstRecord.IsObject() then begin
                FirstObj := FirstRecord.AsObject();

                // Extract key fields
                KeyValue := GetJsonValueFromRecord(FirstObj, 'no');
                NameValue := GetJsonValueFromRecord(FirstObj, 'name');
                if NameValue = '' then
                    NameValue := GetJsonValueFromRecord(FirstObj, 'description');
                AmountValue := GetJsonValueFromRecord(FirstObj, 'amount');
                if AmountValue = '' then
                    AmountValue := GetJsonValueFromRecord(FirstObj, 'saleslcy');
                DateValue := GetJsonValueFromRecord(FirstObj, 'orderdate');
                if DateValue = '' then
                    DateValue := GetJsonValueFromRecord(FirstObj, 'postingdate');

                // Format response based on entity type and sort
                case EntityName of
                    'SalesOrder', 'Sales Order', 'SalesHeader', 'Sales Header':
                        begin
                            if (SortField = 'Amount') and (SortDir = 'DESC') then
                                ResponseText := StrSubstNo('Largest sales order is %1 for %2.', KeyValue, AmountValue)
                            else if (SortField = 'Order Date') and (SortDir = 'DESC') then
                                ResponseText := StrSubstNo('Latest sales order is %1 on %2 for %3.', KeyValue, DateValue, AmountValue)
                            else
                                ResponseText := StrSubstNo('Sales order: %1', KeyValue);
                        end;
                    'Customer':
                        begin
                            if (SortField = 'Sales (LCY)') and (SortDir = 'DESC') then
                                ResponseText := StrSubstNo('Top customer is %1 (%2).', NameValue, KeyValue)
                            else if (SortField = 'Balance (LCY)') and (SortDir = 'DESC') then
                                ResponseText := StrSubstNo('Customer with highest balance is %1 (%2).', NameValue, KeyValue)
                            else
                                ResponseText := StrSubstNo('Customer: %1 (%2)', NameValue, KeyValue);
                        end;
                    'Item':
                        begin
                            if (SortField = 'Sales (LCY)') and (SortDir = 'DESC') then
                                ResponseText := StrSubstNo('Top selling item is %1 - %2.', KeyValue, NameValue)
                            else if (SortField = 'Inventory') and (SortDir = 'DESC') then
                                ResponseText := StrSubstNo('Item with most inventory is %1 - %2.', KeyValue, NameValue)
                            else
                                ResponseText := StrSubstNo('Item: %1 - %2', KeyValue, NameValue);
                        end;
                    'G/L Entry', 'GLEntry':
                        ResponseText := StrSubstNo('G/L Entry %1: %2', KeyValue, NameValue);
                    else
                        ResponseText := StrSubstNo('%1: %2', EntityName, KeyValue);
                end;
            end else
                ResponseText := StrSubstNo('Found 1 %1 record.', EntityName);
        end
        // For multiple records, provide list or summary
        else begin
            // For small result sets (≤10), list them
            if RecordCount <= 10 then
                ResponseText := BuildRecordList(EntityName, RecordCount, ResultArray)
            else if (TopN <= 10) and (SortDir = 'DESC') then
                ResponseText := StrSubstNo('Top %1 %2 records by %3.', RecordCount, EntityName, SortField)
            else
                ResponseText := StrSubstNo('Found %1 %2 record(s).', RecordCount, EntityName);
        end;

        exit(ResponseText);
    end;

    local procedure BuildRecordList(EntityName: Text; RecordCount: Integer; ResultArray: JsonArray): Text
    var
        ResponseText: Text;
        RecordToken: JsonToken;
        RecordObj: JsonObject;
        KeyValue: Text;
        NameValue: Text;
        i: Integer;
    begin
        ResponseText := StrSubstNo('Found %1 %2:', RecordCount, EntityName);
        
        for i := 0 to RecordCount - 1 do begin
            if ResultArray.Get(i, RecordToken) then begin
                if RecordToken.IsObject() then begin
                    RecordObj := RecordToken.AsObject();
                    KeyValue := GetJsonValueFromRecord(RecordObj, 'no');
                    NameValue := GetJsonValueFromRecord(RecordObj, 'name');
                    if NameValue = '' then
                        NameValue := GetJsonValueFromRecord(RecordObj, 'description');
                    
                    if NameValue <> '' then
                        ResponseText += StrSubstNo('\n- %1 (%2)', NameValue, KeyValue)
                    else
                        ResponseText += StrSubstNo('\n- %1', KeyValue);
                end;
            end;
        end;
        
        exit(ResponseText);
    end;

    local procedure GetJsonValueFromRecord(RecordObj: JsonObject; FieldName: Text): Text
    var
        FieldToken: JsonToken;
    begin
        if RecordObj.Get(FieldName, FieldToken) then
            exit(FieldToken.AsValue().AsText());
        exit('');
    end;

    local procedure ApplyGenericFilters(QueryJson: JsonObject; var RecRef: RecordRef)
    var
        FiltersToken: JsonToken;
        FiltersArray: JsonArray;
        FilterToken: JsonToken;
        FilterObj: JsonObject;
        FieldName: Text;
        FieldValue: Text;
        FieldRef: FieldRef;
        FieldNo: Integer;
        i: Integer;
    begin
        if not QueryJson.Get('filters', FiltersToken) then
            exit;

        if not FiltersToken.IsArray() then
            exit;

        FiltersArray := FiltersToken.AsArray();
        for i := 0 to FiltersArray.Count() - 1 do begin
            FiltersArray.Get(i, FilterToken);
            if FilterToken.IsObject() then begin
                FilterObj := FilterToken.AsObject();
                FieldName := GetJsonText(FilterObj, 'field');
                FieldValue := GetJsonText(FilterObj, 'value');

                if FieldName <> '' then begin
                    FieldNo := GetFieldNumber(RecRef, FieldName);
                    if FieldNo <> 0 then begin
                        FieldRef := RecRef.Field(FieldNo);
                        FieldRef.SetFilter(FieldValue);
                    end;
                end;
            end;
        end;
    end;

    local procedure ApplyGenericSorting(QueryJson: JsonObject; var RecRef: RecordRef; EntityName: Text)
    var
        SortField: Text;
        SortDir: Text;
        FieldNo: Integer;
        FieldRef: FieldRef;
    begin
        SortField := GetSortField(QueryJson);
        SortDir := GetSortDirection(QueryJson);

        // Apply entity-specific default sorting if none specified
        if SortField = '' then
            SortField := GetDefaultSortField(EntityName);

        if SortField <> '' then begin
            FieldNo := GetFieldNumber(RecRef, SortField);
            if FieldNo <> 0 then begin
                FieldRef := RecRef.Field(FieldNo);
                
                // Only apply SetView for Normal fields, not FlowFields
                // FlowFields can't be used in SETCURRENTKEY/ORDER
                if FieldRef.Class() = FieldClass::Normal then
                    RecRef.SetView(StrSubstNo('SORTING(%1) ORDER(%2)', FieldRef.Name, UpperCase(SortDir)));
                // For FlowFields, sorting will happen after data retrieval
            end;
        end;
    end;

    local procedure GetDefaultSortField(EntityName: Text): Text
    begin
        case EntityName of
            'Customer':
                exit('Sales (LCY)');
            'Vendor':
                exit('Balance (LCY)');
            'Item':
                exit('Inventory');
            'SalesOrder', 'Sales Order':
                exit('Order Date');
            'SalesInvoice', 'Sales Invoice':
                exit('Posting Date');
            'PurchaseOrder', 'Purchase Order':
                exit('Order Date');
            else
                exit('');
        end;
    end;

    local procedure GetFieldNumber(RecRef: RecordRef; FieldName: Text): Integer
    var
        FieldRef: FieldRef;
        i: Integer;
    begin
        // Try exact match first
        for i := 1 to RecRef.FieldCount() do begin
            FieldRef := RecRef.FieldIndex(i);
            if FieldRef.Name = FieldName then
                exit(FieldRef.Number);
        end;

        // Try case-insensitive match
        for i := 1 to RecRef.FieldCount() do begin
            FieldRef := RecRef.FieldIndex(i);
            if LowerCase(FieldRef.Name) = LowerCase(FieldName) then
                exit(FieldRef.Number);
        end;

        exit(0);
    end;

    local procedure BuildRecordJson(RecRef: RecordRef; EntityName: Text; var RecordJson: JsonObject)
    var
        FieldRef: FieldRef;
        i: Integer;
        FieldClass: FieldClass;
    begin
        // Add all normal and flow fields (skip FlowFilters and BLOB fields)
        for i := 1 to RecRef.FieldCount() do begin
            FieldRef := RecRef.FieldIndex(i);
            FieldClass := FieldRef.Class();
            
            // Include Normal and FlowField, skip FlowFilter and BLOB
            if FieldClass in [FieldClass::Normal, FieldClass::FlowField] then begin
                if FieldRef.Type() <> FieldType::BLOB then begin
                    // Calculate FlowFields before reading
                    if FieldClass = FieldClass::FlowField then
                        FieldRef.CalcField();
                    AddFieldToJson(FieldRef, RecordJson);
                end;
            end;
        end;
    end;

    local procedure AddFieldToJson(FieldRef: FieldRef; var RecordJson: JsonObject)
    var
        FieldName: Text;
        FieldValue: Text;
    begin
        FieldName := LowerCase(FieldRef.Name.Replace(' ', '').Replace('(', '').Replace(')', '').Replace('/', '').Replace('.', ''));
        FieldValue := Format(FieldRef.Value);
        RecordJson.Add(FieldName, FieldValue);
    end;

    local procedure AddCustomerFields(RecRef: RecordRef; var RecordJson: JsonObject)
    begin
        AddFieldIfExists(RecRef, 'Name', RecordJson);
        AddFieldIfExists(RecRef, 'City', RecordJson);
        AddFieldIfExists(RecRef, 'Balance (LCY)', RecordJson);
        AddFieldIfExists(RecRef, 'Sales (LCY)', RecordJson);
    end;

    local procedure AddVendorFields(RecRef: RecordRef; var RecordJson: JsonObject)
    begin
        AddFieldIfExists(RecRef, 'Name', RecordJson);
        AddFieldIfExists(RecRef, 'City', RecordJson);
        AddFieldIfExists(RecRef, 'Balance (LCY)', RecordJson);
    end;

    local procedure AddItemFields(RecRef: RecordRef; var RecordJson: JsonObject)
    begin
        AddFieldIfExists(RecRef, 'Description', RecordJson);
        AddFieldIfExists(RecRef, 'Type', RecordJson);
        AddFieldIfExists(RecRef, 'Inventory', RecordJson);
        AddFieldIfExists(RecRef, 'Unit Price', RecordJson);
        AddFieldIfExists(RecRef, 'Unit Cost', RecordJson);
        AddFieldIfExists(RecRef, 'Sales (LCY)', RecordJson);
    end;

    local procedure AddEmployeeFields(RecRef: RecordRef; var RecordJson: JsonObject)
    begin
        AddFieldIfExists(RecRef, 'First Name', RecordJson);
        AddFieldIfExists(RecRef, 'Last Name', RecordJson);
        AddFieldIfExists(RecRef, 'Job Title', RecordJson);
        AddFieldIfExists(RecRef, 'Company E-Mail', RecordJson);
    end;

    local procedure AddSalesOrderFields(RecRef: RecordRef; var RecordJson: JsonObject)
    begin
        AddFieldIfExists(RecRef, 'Order Date', RecordJson);
        AddFieldIfExists(RecRef, 'Sell-to Customer Name', RecordJson);
        AddFieldIfExists(RecRef, 'Amount', RecordJson);
    end;

    local procedure AddSalesInvoiceFields(RecRef: RecordRef; var RecordJson: JsonObject)
    begin
        AddFieldIfExists(RecRef, 'Posting Date', RecordJson);
        AddFieldIfExists(RecRef, 'Sell-to Customer Name', RecordJson);
        AddFieldIfExists(RecRef, 'Amount Including VAT', RecordJson);
    end;

    local procedure AddLocationFields(RecRef: RecordRef; var RecordJson: JsonObject)
    begin
        AddFieldIfExists(RecRef, 'Name', RecordJson);
        AddFieldIfExists(RecRef, 'City', RecordJson);
        AddFieldIfExists(RecRef, 'Contact', RecordJson);
    end;

    local procedure AddPurchaseOrderFields(RecRef: RecordRef; var RecordJson: JsonObject)
    begin
        AddFieldIfExists(RecRef, 'Order Date', RecordJson);
        AddFieldIfExists(RecRef, 'Buy-from Vendor Name', RecordJson);
        AddFieldIfExists(RecRef, 'Amount', RecordJson);
    end;

    local procedure AddPurchaseLineFields(RecRef: RecordRef; var RecordJson: JsonObject)
    begin
        AddFieldIfExists(RecRef, 'Document Type', RecordJson);
        AddFieldIfExists(RecRef, 'Document No.', RecordJson);
        AddFieldIfExists(RecRef, 'Line No.', RecordJson);
        AddFieldIfExists(RecRef, 'Type', RecordJson);
        AddFieldIfExists(RecRef, 'No.', RecordJson);
        AddFieldIfExists(RecRef, 'Description', RecordJson);
        AddFieldIfExists(RecRef, 'Quantity', RecordJson);
        AddFieldIfExists(RecRef, 'Direct Unit Cost', RecordJson);
        AddFieldIfExists(RecRef, 'Amount', RecordJson);
    end;

    local procedure AddSalesLineFields(RecRef: RecordRef; var RecordJson: JsonObject)
    begin
        AddFieldIfExists(RecRef, 'Document Type', RecordJson);
        AddFieldIfExists(RecRef, 'Document No.', RecordJson);
        AddFieldIfExists(RecRef, 'Line No.', RecordJson);
        AddFieldIfExists(RecRef, 'Type', RecordJson);
        AddFieldIfExists(RecRef, 'No.', RecordJson);
        AddFieldIfExists(RecRef, 'Description', RecordJson);
        AddFieldIfExists(RecRef, 'Quantity', RecordJson);
        AddFieldIfExists(RecRef, 'Unit Price', RecordJson);
        AddFieldIfExists(RecRef, 'Amount', RecordJson);
    end;

    local procedure AddGLEntryFields(RecRef: RecordRef; var RecordJson: JsonObject)
    begin
        AddFieldIfExists(RecRef, 'G/L Account No.', RecordJson);
        AddFieldIfExists(RecRef, 'Posting Date', RecordJson);
        AddFieldIfExists(RecRef, 'Document No.', RecordJson);
        AddFieldIfExists(RecRef, 'Description', RecordJson);
        AddFieldIfExists(RecRef, 'Amount', RecordJson);
        AddFieldIfExists(RecRef, 'Debit Amount', RecordJson);
        AddFieldIfExists(RecRef, 'Credit Amount', RecordJson);
        AddFieldIfExists(RecRef, 'Journal Batch Name', RecordJson);
    end;

    local procedure AddFieldIfExists(RecRef: RecordRef; FieldName: Text; var RecordJson: JsonObject)
    var
        FieldNo: Integer;
    begin
        FieldNo := GetFieldNumber(RecRef, FieldName);
        if FieldNo <> 0 then
            AddFieldToJson(RecRef.Field(FieldNo), RecordJson);
    end;

    // LEGACY: Keep old functions for now in case needed for reference, but they're no longer called

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
        QueryType: Text;
        Setup: Record "NXR Voice Assistant Setup";
    begin
        // DEBUG: Capture what JSON we received (if debug mode enabled)
        if Setup.Get() and Setup."Debug Mode" then begin
            QueryJson.WriteTo(DebugJson);
            DebugInfo := '\\\\[DEBUG] QueryCustomers received JSON: ' + DebugJson;
        end;

        ApplyFiltersFromJson(QueryJson, Customer);

        // Check if this is a count-only query
        QueryType := GetJsonText(QueryJson, 'queryType');
        if QueryType = 'count' then begin
            RecordCount := Customer.Count();
            ResultData.Add('count', RecordCount);
            if Setup.Get() and Setup."Debug Mode" then
                ResponseText := DebugInfo + '\\\\Count query detected\\';
            ResponseText += StrSubstNo('\\There are %1 customers in the database.', RecordCount);
            exit(true);
        end;

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

            // Stop if we've reached the limit
            if RecordCount >= TopN then
                break;
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
            if RecordCount >= TopN then
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

            Clear(VendorJson);
            VendorJson.Add('no', Vendor."No.");
            VendorJson.Add('name', Vendor.Name);
            VendorJson.Add('city', Vendor.City);
            Vendor.CalcFields("Balance (LCY)");
            VendorJson.Add('balance', Vendor."Balance (LCY)");
            TotalOwed += Vendor."Balance (LCY)";
            ResultArray.Add(VendorJson);

            if RecordCount >= TopN then
                break;
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
        SortField: Text;
        SortDir: Text;
        FirstOrderNo: Code[20];
        FirstOrderDate: Date;
        FirstOrderAmount: Decimal;
    begin
        SalesHeader.SetRange("Document Type", SalesHeader."Document Type"::Order);

        // Apply date filter
        DateFilterValue := GetDateFilterValue(QueryJson);
        if DateFilterValue <> '' then begin
            GetDateRangeFromText(DateFilterValue, StartDate, EndDate);
            if StartDate <> 0D then
                SalesHeader.SetRange("Order Date", StartDate, EndDate);
        end;

        // Handle sorting (e.g., last sales order)
        SortField := GetSortField(QueryJson);
        SortDir := GetSortDirection(QueryJson);
        // Normalize field name to handle variations (Order_Date, Order Date, orderdate, orderDate)
        if (SortField = 'Order_Date') or (SortField = 'Order Date') or (SortField = 'orderdate') or (SortField = 'orderDate') then begin
            SalesHeader.SetCurrentKey("Order Date");
            SalesHeader.Ascending(SortDir <> 'DESC');
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

            Clear(OrderJson);
            OrderJson.Add('no', SalesHeader."No.");
            OrderJson.Add('orderDate', Format(SalesHeader."Order Date"));
            OrderJson.Add('customerName', SalesHeader."Sell-to Customer Name");
            SalesHeader.CalcFields(Amount);
            OrderJson.Add('amount', SalesHeader.Amount);
            TotalAmount += SalesHeader.Amount;
            if RecordCount = 1 then begin
                FirstOrderNo := SalesHeader."No.";
                FirstOrderDate := SalesHeader."Order Date";
                FirstOrderAmount := SalesHeader.Amount;
            end;
            ResultArray.Add(OrderJson);

            // Stop if we've reached the limit
            if RecordCount >= TopN then
                break;
        until SalesHeader.Next() = 0;

        ResultData.Add('orders', ResultArray);
        ResultData.Add('totalAmount', TotalAmount);

        // Check for "last order" query pattern - handle all field name variations
        if (RecordCount = 1) and (TopN = 1) and (DateFilterValue = '') and
           ((SortField = 'Order_Date') or (SortField = 'Order Date') or (SortField = 'orderdate') or (SortField = 'orderDate')) and (SortDir = 'DESC') then
            ResponseText := StrSubstNo('Latest sales order is %1 on %2 for %3.', FirstOrderNo, Format(FirstOrderDate), Format(FirstOrderAmount, 0, '<Precision,2:2><Standard Format,0>'))
        else if DateFilterValue <> '' then
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

            Clear(InvoiceJson);
            InvoiceJson.Add('no', SalesInvoiceHeader."No.");
            InvoiceJson.Add('postingDate', Format(SalesInvoiceHeader."Posting Date"));
            InvoiceJson.Add('customerName', SalesInvoiceHeader."Sell-to Customer Name");
            SalesInvoiceHeader.CalcFields("Amount Including VAT");
            InvoiceJson.Add('amount', SalesInvoiceHeader."Amount Including VAT");
            TotalAmount += SalesInvoiceHeader."Amount Including VAT";
            ResultArray.Add(InvoiceJson);

            if RecordCount >= TopN then
                break;
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
            if RecordCount >= TopN then
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
            if RecordCount >= TopN then
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

            Clear(OrderJson);
            OrderJson.Add('no', PurchaseHeader."No.");
            OrderJson.Add('orderDate', Format(PurchaseHeader."Order Date"));
            OrderJson.Add('vendorName', PurchaseHeader."Buy-from Vendor Name");
            PurchaseHeader.CalcFields(Amount);
            OrderJson.Add('amount', PurchaseHeader.Amount);
            TotalAmount += PurchaseHeader.Amount;
            ResultArray.Add(OrderJson);

            if RecordCount >= TopN then
                break;
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

    local procedure SortResultArrayIfNeeded(var ResultArray: JsonArray; QueryJson: JsonObject; TableNo: Integer)
    var
        SortField: Text;
        SortDir: Text;
        IsFlowField: Boolean;
    begin
        SortField := GetSortField(QueryJson);
        if SortField = '' then
            exit; // No sorting needed

        // Try to check if sort field is a FlowField
        if not TryCheckIfFlowField(TableNo, SortField, IsFlowField) then
            exit; // Can't determine field type, skip post-sort
        
        if not IsFlowField then
            exit; // Normal field, already sorted by SetView

        // FlowField detected - need to sort the JSON array
        SortDir := GetSortDirection(QueryJson);
        SortJsonArrayByField(ResultArray, SortField, SortDir);
    end;

    [TryFunction]
    local procedure TryCheckIfFlowField(TableNo: Integer; FieldName: Text; var IsFlowField: Boolean)
    var
        TempRecRef: RecordRef;
        FieldRef: FieldRef;
        FieldNo: Integer;
    begin
        IsFlowField := false;
        TempRecRef.Open(TableNo);
        FieldNo := GetFieldNumber(TempRecRef, FieldName);
        if FieldNo = 0 then begin
            TempRecRef.Close();
            Error('');  // Trigger try function to return false
        end;

        FieldRef := TempRecRef.Field(FieldNo);
        IsFlowField := (FieldRef.Class() = FieldClass::FlowField);
        TempRecRef.Close();
    end;

    local procedure SortJsonArrayByField(var ResultArray: JsonArray; SortField: Text; Direction: Text)
    var
        SortedArray: JsonArray;
        ValueList: List of [Decimal];
        RecordList: List of [JsonObject];
        Token: JsonToken;
        RecordObj: JsonObject;
        FieldValue: Decimal;
        i: Integer;
        j: Integer;
        MinIdx: Integer;
        MinValue: Decimal;
        TempValue: Decimal;
        TempRecord: JsonObject;
        FieldName: Text;
    begin
        if ResultArray.Count() = 0 then
            exit;

        // Convert field name to lowercase without spaces/special chars
        FieldName := LowerCase(SortField.Replace(' ', '').Replace('(', '').Replace(')', '').Replace('/', '').Replace('.', ''));

        // Extract values and records into lists
        foreach Token in ResultArray do begin
            if Token.IsObject() then begin
                RecordObj := Token.AsObject();
                RecordList.Add(RecordObj);
                
                // Try to get numeric value for sorting
                if not Evaluate(FieldValue, GetJsonText(RecordObj, FieldName)) then
                    FieldValue := 0;
                ValueList.Add(FieldValue);
            end;
        end;

        // Simple selection sort
        for i := 1 to ValueList.Count() - 1 do begin
            MinIdx := i;
            MinValue := ValueList.Get(i);
            
            for j := i + 1 to ValueList.Count() do begin
                TempValue := ValueList.Get(j);
                if ((Direction = 'DESC') and (TempValue > MinValue)) or
                   ((Direction <> 'DESC') and (TempValue < MinValue)) then begin
                    MinIdx := j;
                    MinValue := TempValue;
                end;
            end;
            
            if MinIdx <> i then begin
                // Swap in value list
                TempValue := ValueList.Get(i);
                ValueList.Set(i, ValueList.Get(MinIdx));
                ValueList.Set(MinIdx, TempValue);
                
                // Swap in record list
                TempRecord := RecordList.Get(i);
                RecordList.Set(i, RecordList.Get(MinIdx));
                RecordList.Set(MinIdx, TempRecord);
            end;
        end;

        // Rebuild array in sorted order
        Clear(SortedArray);
        foreach RecordObj in RecordList do
            SortedArray.Add(RecordObj);
        
        ResultArray := SortedArray;
    end;
}
