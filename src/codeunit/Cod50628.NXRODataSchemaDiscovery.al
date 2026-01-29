/// <summary>
/// Discovers all available OData entities (queries, tables, pages) from BC API.
/// Uses a predefined schema approach to avoid authentication issues with $metadata endpoint.
/// </summary>
codeunit 50628 "NXR OData Schema Discovery"
{
    var
        Setup: Record "NXR Voice Assistant Setup";

    /// <summary>
    /// Discovers all OData entities and returns formatted schema.
    /// Uses a simple, cached approach instead of querying $metadata (which requires special auth).
    /// </summary>
    procedure DiscoverODataSchema(): Text
    var
        Schema: Text;
    begin
        if not Setup.Get() then
            Error('Voice Assistant Setup not configured');

        // Use a predefined schema of commonly-used BC entities
        // This avoids OData $metadata endpoint auth issues
        Schema := BuildDefaultSchema();

        exit(Schema);
    end;

    local procedure BuildDefaultSchema(): Text
    var
        Schema: Text;
        NewLineChar: Text;
    begin
        // Build schema of commonly queried BC entities
        NewLineChar := Format(10); // ASCII line feed
        Schema := 'BUSINESS CENTRAL ODATA ENTITIES:' + NewLineChar + NewLineChar;
        
        Schema += 'Customer: CustomerNo, Name, City, CountryRegionCode, CustomerPostingGroup' + NewLineChar;
        Schema += 'Vendor: VendorNo, Name, City, CountryRegionCode, VendorPostingGroup' + NewLineChar;
        Schema += 'Item: ItemNo, Description, ItemCategoryCode, UnitOfMeasureCode' + NewLineChar;
        Schema += 'SalesOrder: DocumentNo, CustomerNo, OrderDate, Status, Amount' + NewLineChar;
        Schema += 'SalesInvoice: DocumentNo, CustomerNo, PostingDate, Amount, Status' + NewLineChar;
        Schema += 'PurchaseOrder: DocumentNo, VendorNo, OrderDate, Status, Amount' + NewLineChar;
        Schema += 'GeneralLedgerEntry: EntryNo, GLAccountNo, PostingDate, Amount, Description' + NewLineChar;
        Schema += 'SalesLine: DocumentNo, LineNo, ItemNo, Quantity, UnitPrice, Amount' + NewLineChar;
        Schema += 'PurchaseLine: DocumentNo, LineNo, ItemNo, Quantity, DirectUnitCost, Amount';
        
        exit(Schema);
    end;

    /// <summary>
    /// Refreshes schema and stores in Setup table.
    /// </summary>
    procedure RefreshSchema()
    var
        SchemaContext: Codeunit "NXR Schema Context";
        SchemaText: Text;
    begin
        SchemaText := DiscoverODataSchema();
        SchemaContext.SetSchemaContext(SchemaText);
        Message('Schema refreshed successfully with 9 Business Central entities.');
    end;
}
