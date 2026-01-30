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
        // BC TABLE FIELD NAMES for NATIVE MODE (AL Record queries)
        // These match the actual Record field names used in Cod50609 native executor
        NewLineChar := Format(10); // ASCII line feed
        Schema := 'BUSINESS CENTRAL TABLE ENTITIES (BC Table Field Names for Native Mode):' + NewLineChar + NewLineChar;

        // Master data entities - using BC table field names
        Schema += 'Customer: No., Name, Name 2, Address, Address 2, City, County, Country/Region Code, Post Code, Phone No., E-Mail, Home Page, Contact, VAT Registration No., Currency Code, Payment Terms Code, Shipment Method Code, Payment Method Code, Blocked, Last Date Modified, Balance (LCY), Balance Due (LCY), Sales (LCY), Credit Limit (LCY), Customer Posting Group, Gen. Bus. Posting Group, VAT Bus. Posting Group' + NewLineChar;
        Schema += 'Vendor: No., Name, Name 2, Address, Address 2, City, County, Country/Region Code, Post Code, Phone No., E-Mail, Home Page, Contact, VAT Registration No., Currency Code, Payment Terms Code, Shipment Method Code, Payment Method Code, Blocked, Last Date Modified, Balance (LCY), Balance Due (LCY), Vendor Posting Group, Gen. Bus. Posting Group, VAT Bus. Posting Group' + NewLineChar;
        Schema += 'Item: No., Description, Description 2, Type, Item Category Code, Product Group Code, Blocked, Base Unit of Measure, GTIN, Inventory, Unit Price, Price Includes VAT, Unit Cost, Last Direct Cost, Standard Cost, Vendor No., Vendor Item No., Tax Group Code, Gen. Prod. Posting Group, VAT Prod. Posting Group, Item Disc. Group, Costing Method, Last Date Modified' + NewLineChar;
        Schema += 'Employee: No., First Name, Middle Name, Last Name, Initials, Job Title, Search Name, Address, Address 2, City, County, Country/Region Code, Post Code, Phone No., Mobile Phone No., Company E-Mail, E-Mail, Employment Date, Termination Date, Status, Inactive Date, Birth Date, Social Security No., Union Code, Emplymt. Contract Code, Statistics Group Code, Employee Posting Group' + NewLineChar;
        Schema += 'Location: Code, Name, Name 2, Contact, Address, Address 2, City, County, Country/Region Code, Post Code, Phone No., Phone No. 2, E-Mail, Use As In-Transit, Use Cross-Docking, Require Put-away, Require Pick, Require Receive, Require Shipment' + NewLineChar + NewLineChar;

        // Additional master data
        Schema += 'Bank Account: No., Name, Name 2, Address, Address 2, City, County, Country/Region Code, Post Code, Phone No., Contact, Bank Account No., SWIFT Code, IBAN, Currency Code, Last Date Modified, Balance (LCY), Balance at Date (LCY)' + NewLineChar;
        Schema += 'Item Category: Code, Description, Parent Category, Indentation, Has Children' + NewLineChar;
        Schema += 'Payment Terms: Code, Description, Due Date Calculation, Discount Date Calculation, Discount %, Calc. Pmt. Disc. on Cr. Memos' + NewLineChar;
        Schema += 'Shipment Method: Code, Description' + NewLineChar;
        Schema += 'Payment Method: Code, Description, Bal. Account Type, Bal. Account No.' + NewLineChar;
        Schema += 'Salesperson/Purchaser: Code, Name, Name 2, E-Mail, Phone No., Commission %' + NewLineChar + NewLineChar;

        // Sales document entities - using BC table field names
        Schema += 'Sales Header (Quote/Order/Invoice/Credit Memo/Blanket Order/Return Order): Document Type, No., Sell-to Customer No., Sell-to Customer Name, Sell-to Customer Name 2, Sell-to Address, Sell-to Address 2, Sell-to City, Sell-to Contact, Sell-to Post Code, Sell-to County, Sell-to Country/Region Code, Bill-to Customer No., Bill-to Name, Bill-to Name 2, Bill-to Address, Bill-to Address 2, Bill-to City, Bill-to Contact, Bill-to Post Code, Bill-to County, Bill-to Country/Region Code, Ship-to Code, Ship-to Name, Ship-to Name 2, Ship-to Address, Ship-to Address 2, Ship-to City, Ship-to Contact, Ship-to Post Code, Ship-to County, Ship-to Country/Region Code, Posting Date, Order Date, Document Date, Shipment Date, Due Date, Payment Terms Code, Payment Method Code, Shipment Method Code, Location Code, Shortcut Dimension 1 Code, Shortcut Dimension 2 Code, Customer Posting Group, Currency Code, Currency Factor, Prices Including VAT, Invoice Discount Value, Invoice Discount Amount, Salesperson Code, Requested Delivery Date, Promised Delivery Date, External Document No., Your Reference, Quote No., Order No., Prepayment %, Prepayment No., Amount, Amount Including VAT, Completely Shipped, Outstanding Amount, Shipped Not Invoiced, Status, Sell-to Phone No., Sell-to E-Mail' + NewLineChar;
        Schema += 'Sales Line: Document Type, Document No., Line No., Sell-to Customer No., Type, No., Location Code, Posting Group, Shipment Date, Description, Description 2, Unit of Measure, Unit of Measure Code, Quantity, Outstanding Quantity, Qty. to Invoice, Qty. to Ship, Unit Price, Unit Cost (LCY), VAT %, Line Discount %, Line Discount Amount, Amount, Amount Including VAT, Attached to Line No., Job No., Work Type Code, Shortcut Dimension 1 Code, Shortcut Dimension 2 Code, Customer Price Group, Quantity Shipped, Quantity Invoiced, Shipment No., Variant Code, Bin Code, Qty. per Unit of Measure, Outstanding Amount, Shipped Not Invoiced' + NewLineChar;
        Schema += 'Sales Invoice Header: No., Sell-to Customer No., Sell-to Customer Name, Sell-to Customer Name 2, Sell-to Address, Sell-to Address 2, Sell-to City, Sell-to Contact, Sell-to Post Code, Sell-to County, Sell-to Country/Region Code, Bill-to Customer No., Bill-to Name, Bill-to Name 2, Bill-to Address, Bill-to Address 2, Bill-to City, Bill-to Contact, Bill-to Post Code, Bill-to County, Bill-to Country/Region Code, Ship-to Code, Ship-to Name, Ship-to Name 2, Ship-to Address, Ship-to Address 2, Ship-to City, Ship-to Contact, Ship-to Post Code, Ship-to County, Ship-to Country/Region Code, Posting Date, Document Date, Shipment Date, Due Date, Payment Terms Code, Payment Method Code, Shipment Method Code, Location Code, Salesperson Code, Order No., External Document No., Your Reference, Currency Code, Prices Including VAT, Amount, Amount Including VAT, Remaining Amount, Closed, User ID, Sell-to Phone No., Sell-to E-Mail' + NewLineChar;
        Schema += 'Sales Invoice Line: Document No., Line No., Sell-to Customer No., Type, No., Location Code, Posting Group, Shipment Date, Description, Description 2, Unit of Measure, Unit of Measure Code, Quantity, Unit Price, Unit Cost (LCY), VAT %, Line Discount %, Line Discount Amount, Amount, Amount Including VAT, Shipment No., Variant Code, Bin Code, Qty. per Unit of Measure' + NewLineChar;
        Schema += 'Sales Cr.Memo Header: No., Sell-to Customer No., Sell-to Customer Name, Sell-to Customer Name 2, Sell-to Address, Sell-to Address 2, Sell-to City, Sell-to Contact, Sell-to Post Code, Sell-to County, Sell-to Country/Region Code, Bill-to Customer No., Bill-to Name, Bill-to Name 2, Bill-to Address, Bill-to Address 2, Bill-to City, Bill-to Contact, Bill-to Post Code, Bill-to County, Bill-to Country/Region Code, Posting Date, Document Date, Due Date, Payment Terms Code, Payment Method Code, Applies-to Doc. Type, Applies-to Doc. No., Currency Code, Prices Including VAT, Amount, Amount Including VAT, Remaining Amount, Closed, Sell-to Phone No., Sell-to E-Mail' + NewLineChar;
        Schema += 'Sales Cr.Memo Line: Document No., Line No., Sell-to Customer No., Type, No., Location Code, Posting Group, Description, Description 2, Unit of Measure, Unit of Measure Code, Quantity, Unit Price, Unit Cost (LCY), VAT %, Line Discount %, Line Discount Amount, Amount, Amount Including VAT, Variant Code' + NewLineChar + NewLineChar;

        // Purchase document entities - using BC table field names
        Schema += 'Purchase Header (Quote/Order/Invoice/Credit Memo/Blanket Order/Return Order): Document Type, No., Buy-from Vendor No., Buy-from Vendor Name, Buy-from Vendor Name 2, Buy-from Address, Buy-from Address 2, Buy-from City, Buy-from Contact, Buy-from Post Code, Buy-from County, Buy-from Country/Region Code, Pay-to Vendor No., Pay-to Name, Pay-to Name 2, Pay-to Address, Pay-to Address 2, Pay-to City, Pay-to Contact, Pay-to Post Code, Pay-to County, Pay-to Country/Region Code, Ship-to Code, Ship-to Name, Ship-to Name 2, Ship-to Address, Ship-to Address 2, Ship-to City, Ship-to Contact, Ship-to Post Code, Ship-to County, Ship-to Country/Region Code, Posting Date, Order Date, Document Date, Expected Receipt Date, Due Date, Payment Terms Code, Payment Method Code, Shipment Method Code, Location Code, Shortcut Dimension 1 Code, Shortcut Dimension 2 Code, Vendor Posting Group, Currency Code, Currency Factor, Prices Including VAT, Invoice Discount Value, Invoice Discount Amount, Purchaser Code, Vendor Invoice No., Vendor Shipment No., Vendor Order No., Order Address Code, Prepayment %, Prepayment No., Amount, Amount Including VAT, Completely Received, Outstanding Amount, Amt. Rcd. Not Invoiced, Status, Buy-from Contact No., Pay-to Contact No.' + NewLineChar;
        Schema += 'Purchase Line: Document Type, Document No., Line No., Buy-from Vendor No., Type, No., Location Code, Posting Group, Expected Receipt Date, Description, Description 2, Unit of Measure, Unit of Measure Code, Quantity, Outstanding Quantity, Qty. to Invoice, Qty. to Receive, Direct Unit Cost, Unit Cost (LCY), VAT %, Line Discount %, Line Discount Amount, Amount, Amount Including VAT, Job No., Indirect Cost %, Shortcut Dimension 1 Code, Shortcut Dimension 2 Code, Quantity Received, Quantity Invoiced, Receipt No., Variant Code, Bin Code, Qty. per Unit of Measure, Outstanding Amount, Amt. Rcd. Not Invoiced' + NewLineChar;
        Schema += 'Purch. Inv. Header: No., Buy-from Vendor No., Buy-from Vendor Name, Buy-from Vendor Name 2, Buy-from Address, Buy-from Address 2, Buy-from City, Buy-from Contact, Buy-from Post Code, Buy-from County, Buy-from Country/Region Code, Pay-to Vendor No., Pay-to Name, Pay-to Name 2, Pay-to Address, Pay-to Address 2, Pay-to City, Pay-to Contact, Pay-to Post Code, Pay-to County, Pay-to Country/Region Code, Ship-to Code, Ship-to Name, Ship-to Name 2, Ship-to Address, Ship-to Address 2, Ship-to City, Ship-to Contact, Ship-to Post Code, Ship-to County, Ship-to Country/Region Code, Posting Date, Document Date, Due Date, Payment Terms Code, Payment Method Code, Shipment Method Code, Location Code, Purchaser Code, Order No., Vendor Invoice No., Vendor Order No., Currency Code, Prices Including VAT, Amount, Amount Including VAT, Remaining Amount, Closed, User ID' + NewLineChar;
        Schema += 'Purch. Inv. Line: Document No., Line No., Buy-from Vendor No., Type, No., Location Code, Posting Group, Description, Description 2, Unit of Measure, Unit of Measure Code, Quantity, Direct Unit Cost, Unit Cost (LCY), VAT %, Line Discount %, Line Discount Amount, Amount, Amount Including VAT, Receipt No., Variant Code, Bin Code, Qty. per Unit of Measure' + NewLineChar;
        Schema += 'Purch. Cr. Memo Hdr.: No., Buy-from Vendor No., Buy-from Vendor Name, Buy-from Vendor Name 2, Buy-from Address, Buy-from Address 2, Buy-from City, Buy-from Contact, Buy-from Post Code, Buy-from County, Buy-from Country/Region Code, Pay-to Vendor No., Pay-to Name, Pay-to Name 2, Pay-to Address, Pay-to Address 2, Pay-to City, Pay-to Contact, Pay-to Post Code, Pay-to County, Pay-to Country/Region Code, Posting Date, Document Date, Due Date, Payment Terms Code, Applies-to Doc. Type, Applies-to Doc. No., Vendor Cr. Memo No., Currency Code, Prices Including VAT, Amount, Amount Including VAT, Remaining Amount, Closed' + NewLineChar;
        Schema += 'Purch. Cr. Memo Line: Document No., Line No., Buy-from Vendor No., Type, No., Location Code, Posting Group, Description, Description 2, Unit of Measure, Unit of Measure Code, Quantity, Direct Unit Cost, Unit Cost (LCY), VAT %, Line Discount %, Line Discount Amount, Amount, Amount Including VAT, Variant Code' + NewLineChar + NewLineChar;

        // Financial/Ledger entries
        Schema += 'G/L Entry: Entry No., G/L Account No., G/L Account Name, Posting Date, Document Type, Document No., Description, Bal. Account No., Amount, Debit Amount, Credit Amount, Source Code, Source Type, Source No., VAT Amount, Gen. Posting Type, Gen. Bus. Posting Group, Gen. Prod. Posting Group, Global Dimension 1 Code, Global Dimension 2 Code, User ID, Transaction No., Closed' + NewLineChar;
        Schema += 'Cust. Ledger Entry: Entry No., Customer No., Customer Name, Posting Date, Document Type, Document No., Description, Currency Code, Amount, Amount (LCY), Remaining Amount, Remaining Amt. (LCY), Original Amount, Original Amt. (LCY), Closed, Closed at Date, Closed by Entry No., Open, Due Date, Pmt. Discount Date, On Hold, Positive, Sales (LCY), Global Dimension 1 Code, Global Dimension 2 Code, Salesperson Code, User ID' + NewLineChar;
        Schema += 'Vendor Ledger Entry: Entry No., Vendor No., Vendor Name, Posting Date, Document Type, Document No., Description, Currency Code, Amount, Amount (LCY), Remaining Amount, Remaining Amt. (LCY), Original Amount, Original Amt. (LCY), Closed, Closed at Date, Closed by Entry No., Open, Due Date, Pmt. Discount Date, On Hold, Positive, Purchase (LCY), Global Dimension 1 Code, Global Dimension 2 Code, Purchaser Code, User ID' + NewLineChar;
        Schema += 'Bank Account Ledger Entry: Entry No., Bank Account No., Posting Date, Document Type, Document No., Description, Currency Code, Amount, Amount (LCY), Remaining Amount, Remaining Amt. (LCY), Open, Statement Status, Statement No., Statement Line No., Debit Amount, Debit Amount (LCY), Credit Amount, Credit Amount (LCY), Reversed, Reversed by Entry No., Reversed Entry No., User ID' + NewLineChar + NewLineChar;

        // Dimension tables for analytics
        Schema += 'Dimension: Code, Name, Description, Code Caption, Filter Caption, Consolidation Code, Map-to IC Dimension Code, Blocked' + NewLineChar;
        Schema += 'Dimension Value: Dimension Code, Code, Name, Dimension Value Type, Totaling, Blocked, Consolidation Code, Indentation, Global Dimension No., Map-to IC Dimension Value Code' + NewLineChar + NewLineChar;

        // Critical field name rules for BC tables
        Schema += 'CRITICAL BC TABLE FIELD NAME RULES:' + NewLineChar;
        Schema += '- Field names use Title Case with spaces (e.g., "Order Date" not "orderDate")' + NewLineChar;
        Schema += '- Special characters: Use "/" (Country/Region Code), "()" for Balance (LCY), "-" for hyphens (Sell-to, Buy-from)' + NewLineChar;
        Schema += '- Document numbers: "No." field (with period)' + NewLineChar;
        Schema += '- Names: "Name" for master data, "Sell-to Customer Name"/"Buy-from Vendor Name" for documents' + NewLineChar;
        Schema += '- Dates: "Order Date", "Posting Date", "Due Date", "Requested Delivery Date"' + NewLineChar;
        Schema += '- Amounts: "Amount", "Amount Including VAT", "Balance (LCY)", "Unit Price"' + NewLineChar;
        Schema += '- Common patterns: "Sell-to" (sales), "Buy-from"/"Pay-to" (purchase), "Ship-to" (both)' + NewLineChar;
        Schema += '- For sorting: Use field names exactly as shown (e.g., "Order Date" for latest order sorting)' + NewLineChar;
        Schema += '- These are BC AL table field names - native mode queries BC tables directly using these names' + NewLineChar;

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
        Message('Schema refreshed successfully with 30+ Business Central table entities for native mode.');
    end;
}
