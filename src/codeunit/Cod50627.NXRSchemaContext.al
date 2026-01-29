/// <summary>
/// Manages database schema context for AI queries.
/// Stores schema once in Setup table, used by all queries.
/// </summary>
codeunit 50627 "NXR Schema Context"
{
    var
        Setup: Record "NXR Voice Assistant Setup";

    /// <summary>
    /// Gets schema context from Setup table or builds default.
    /// Priority: 1) Cached blob, 2) Published web services, 3) Default hardcoded schema
    /// </summary>
    procedure GetSchemaContext(): Text
    var
        SchemaText: Text;
    begin
        if not Setup.Get() then
            exit(BuildCombinedSchema());

        SchemaText := ReadSchemaFromBlob();

        if SchemaText = '' then
            SchemaText := BuildCombinedSchema();

        exit(SchemaText);
    end;

    /// <summary>
    /// Builds schema from OData $metadata discovery + default fallback
    /// </summary>
    local procedure BuildCombinedSchema(): Text
    var
        ODataSchemaDiscovery: Codeunit "NXR OData Schema Discovery";
        SchemaText: Text;
    begin
        // Use OData $metadata discovery for field-level schema
        SchemaText := ODataSchemaDiscovery.DiscoverODataSchema();

        // Add separator
        SchemaText += '\n---\n\n';

        // Append default schema for standard tables
        SchemaText += GetDefaultSchema();

        exit(SchemaText);
    end;

    /// <summary>
    /// Stores schema context in Setup table.
    /// </summary>
    procedure SetSchemaContext(SchemaText: Text)
    begin
        if not Setup.Get() then begin
            Setup.Init();
            Setup.Insert();
        end;

        WriteSchemaToBlob(SchemaText);
        Setup."Schema Last Updated" := CurrentDateTime;
        Setup.Modify();
    end;

    local procedure ReadSchemaFromBlob(): Text
    var
        InStream: InStream;
        SchemaText: Text;
        Line: Text;
    begin
        Setup.CalcFields("OData Schema Context");

        if not Setup."OData Schema Context".HasValue then
            exit('');

        Setup."OData Schema Context".CreateInStream(InStream, TextEncoding::UTF8);

        while not InStream.EOS do begin
            InStream.ReadText(Line);
            SchemaText += Line;
        end;

        exit(SchemaText);
    end;

    local procedure WriteSchemaToBlob(SchemaText: Text)
    var
        OutStream: OutStream;
    begin
        Clear(Setup."OData Schema Context");
        Setup."OData Schema Context".CreateOutStream(OutStream, TextEncoding::UTF8);
        OutStream.WriteText(SchemaText);
    end;

    local procedure GetDefaultSchema(): Text
    var
        Schema: Text;
    begin
        // Comprehensive BC schema covering standard tables
        Schema := 'BUSINESS CENTRAL DATABASE SCHEMA:\n\n';

        // Core master data
        Schema += 'Customer: No, Name, Address, City, Country_Region_Code, Phone_No, E_Mail, Balance_LCY, Sales_LCY, Contact\n';
        Schema += 'Vendor: No, Name, Address, City, Country_Region_Code, Phone_No, Balance_LCY, Purchases_LCY\n';
        Schema += 'Item: No, Description, Base_Unit_of_Measure, Unit_Price, Unit_Cost, Inventory, Item_Category_Code, Vendor_No\n';
        Schema += 'Employee: No, First_Name, Last_Name, Job_Title, E_Mail, Phone_No, Employment_Date\n';
        Schema += 'Location: Code, Name, Address, City, Country_Region_Code\n';
        Schema += 'G_L_Account: No, Name, Account_Type, Balance, Debit_Amount, Credit_Amount\n';

        // Sales documents
        Schema += 'Sales_Header: Document_Type, No, Sell_to_Customer_No, Order_Date, Posting_Date, Due_Date, Amount, Amount_Including_VAT, Status\n';
        Schema += 'Sales_Line: Document_Type, Document_No, Line_No, Type, No, Description, Quantity, Unit_Price, Amount, Location_Code\n';
        Schema += 'Sales_Invoice_Header: No, Sell_to_Customer_No, Posting_Date, Due_Date, Amount, Amount_Including_VAT\n';
        Schema += 'Sales_Invoice_Line: Document_No, Line_No, Type, No, Description, Quantity, Unit_Price, Amount\n';

        // Purchase documents  
        Schema += 'Purchase_Header: Document_Type, No, Buy_from_Vendor_No, Order_Date, Posting_Date, Due_Date, Amount, Amount_Including_VAT, Status\n';
        Schema += 'Purchase_Line: Document_Type, Document_No, Line_No, Type, No, Description, Quantity, Direct_Unit_Cost, Amount, Location_Code\n';
        Schema += 'Purch_Inv_Header: No, Buy_from_Vendor_No, Posting_Date, Due_Date, Amount, Amount_Including_VAT\n';
        Schema += 'Purch_Inv_Line: Document_No, Line_No, Type, No, Description, Quantity, Direct_Unit_Cost, Amount\n';

        // Ledger entries
        Schema += 'Cust_Ledger_Entry: Entry_No, Customer_No, Posting_Date, Document_Type, Document_No, Amount, Remaining_Amount, Open\n';
        Schema += 'Vendor_Ledger_Entry: Entry_No, Vendor_No, Posting_Date, Document_Type, Document_No, Amount, Remaining_Amount, Open\n';
        Schema += 'Item_Ledger_Entry: Entry_No, Item_No, Posting_Date, Entry_Type, Location_Code, Quantity, Remaining_Quantity\n';
        Schema += 'G_L_Entry: Entry_No, G_L_Account_No, Posting_Date, Document_Type, Document_No, Amount, Debit_Amount, Credit_Amount\n';

        // Additional entities
        Schema += 'Item_Category: Code, Description, Parent_Category\n';
        Schema += 'Customer_Price_Group: Code, Description, Price_Includes_VAT\n';
        Schema += 'Sales_Price: Item_No, Sales_Type, Sales_Code, Unit_Price, Starting_Date, Ending_Date\n';
        Schema += 'Resource: No, Name, Type, Unit_Price, Unit_Cost, Base_Unit_of_Measure\n';
        Schema += 'Job: No, Description, Bill_to_Customer_No, Starting_Date, Ending_Date, Status\n';
        Schema += 'Bank_Account: No, Name, Bank_Account_No, Currency_Code, Balance_LCY\n';
        Schema += 'Payment_Terms: Code, Due_Date_Calculation, Discount_Date_Calculation, Discount_Percent\n';
        Schema += 'Shipment_Method: Code, Description\n';
        Schema += 'Country_Region: Code, Name, EU_Country_Region_Code\n';
        Schema += 'Currency: Code, Description, Currency_Factor, Amount_Rounding_Precision\n';

        exit(Schema);
    end;
}
