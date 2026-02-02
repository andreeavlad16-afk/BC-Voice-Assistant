/// <summary>
/// Codeunit to automatically publish pages as web services.
/// Provides bulk publishing functionality for OData/API endpoints.
/// </summary>
codeunit 50630 "NXR Web Service Publisher"
{
    /// <summary>
    /// Publishes all available pages as OData web services.
    /// Creates web service records for pages that are not already published.
    /// </summary>
    procedure PublishAllPages()
    var
        AllObjWithCaption: Record AllObjWithCaption;
        TenantWebService: Record "Tenant Web Service";
        PagesList: List of [Integer];
        PageID: Integer;
        PublishedCount: Integer;
    begin
        PublishedCount := 0;

        // Get all pages that should be published
        GetPagesToPublish(PagesList);

        // Publish each page
        foreach PageID in PagesList do begin
            if not IsPageAlreadyPublished(PageID) then begin
                if PublishPage(PageID) then
                    PublishedCount += 1;
            end;
        end;

        if PublishedCount > 0 then
            Message('Published %1 new web services. Total pages now available via OData.', PublishedCount)
        else
            Message('All pages are already published as web services.');
    end;

    local procedure GetPagesToPublish(var PagesList: List of [Integer])
    begin
        // Publish 100+ most useful Business Central pages for queries

        // Master Data - Customers & Sales
        PagesList.Add(22); // Customer List
        PagesList.Add(21); // Customer Card
        PagesList.Add(25); // Customer Ledger Entries
        PagesList.Add(5050); // Contact List
        PagesList.Add(5052); // Contact Card
        PagesList.Add(297); // Salesperson/Purchaser List
        PagesList.Add(156); // Resource List
        PagesList.Add(335); // Shipping Agents

        // Master Data - Vendors & Purchasing
        PagesList.Add(27); // Vendor List
        PagesList.Add(26); // Vendor Card
        PagesList.Add(29); // Vendor Ledger Entries

        // Master Data - Items & Inventory
        PagesList.Add(31); // Item List
        PagesList.Add(30); // Item Card
        PagesList.Add(5701); // Item Availability by Location
        PagesList.Add(5702); // Item Availability by Period
        PagesList.Add(270); // Item Ledger Entries
        PagesList.Add(5802); // Value Entries
        PagesList.Add(5405); // Item Charges
        PagesList.Add(5800); // Item Charges Assignment
        PagesList.Add(5825); // Item Tracking Lines

        // Sales - Orders & Quotes
        PagesList.Add(9305); // Sales Order List
        PagesList.Add(42); // Sales Orders
        PagesList.Add(43); // Sales Order
        PagesList.Add(9301); // Sales Quote List
        PagesList.Add(41); // Sales Quotes
        PagesList.Add(9302); // Sales Invoice List
        PagesList.Add(9308); // Sales Invoices
        PagesList.Add(9303); // Sales Credit Memos
        PagesList.Add(9304); // Sales Return Order List
        PagesList.Add(9315); // Sales Order Archive List

        // Sales - Posted Documents
        PagesList.Add(143); // Posted Sales Invoices
        PagesList.Add(144); // Posted Sales Credit Memos
        PagesList.Add(142); // Posted Sales Shipments
        PagesList.Add(6660); // Posted Return Receipts

        // Sales - Lines & Details
        PagesList.Add(516); // Sales Lines
        PagesList.Add(113); // Posted Sales Invoice Lines

        // Purchase - Orders & Quotes
        PagesList.Add(9307); // Purchase Order List
        PagesList.Add(50); // Purchase Orders
        PagesList.Add(51); // Purchase Order
        PagesList.Add(9306); // Purchase Quote List
        PagesList.Add(49); // Purchase Quotes
        PagesList.Add(9308); // Purchase Invoice List
        PagesList.Add(9309); // Purchase Invoices
        PagesList.Add(9304); // Purchase Credit Memos
        PagesList.Add(9311); // Purchase Return Order List
        PagesList.Add(9346); // Purchase Order Archive List

        // Purchase - Posted Documents
        PagesList.Add(146); // Posted Purchase Invoices
        PagesList.Add(147); // Posted Purchase Credit Memos
        PagesList.Add(145); // Posted Purchase Receipts
        PagesList.Add(6661); // Posted Return Shipments

        // Purchase - Lines & Details
        PagesList.Add(518); // Purchase Lines
        PagesList.Add(123); // Posted Purchase Invoice Lines

        // Financial Management - G/L
        PagesList.Add(20); // G/L Account List
        PagesList.Add(18); // G/L Account Card
        PagesList.Add(17); // G/L Entries
        PagesList.Add(255); // Chart of Accounts
        PagesList.Add(16); // General Ledger Entries
        PagesList.Add(167); // Posted General Journal Lines

        // Financial Management - Bank
        PagesList.Add(375); // Bank Account List
        PagesList.Add(377); // Bank Account Card
        PagesList.Add(371); // Bank Account Ledger Entries
        PagesList.Add(379); // Bank Acc. Reconciliation List
        PagesList.Add(380); // Bank Acc. Reconciliation
        PagesList.Add(404); // Payment Journal

        // Financial Management - Currencies & Rates
        PagesList.Add(5); // Currency List
        PagesList.Add(483); // Currency Exchange Rates

        // Inventory & Warehouse
        PagesList.Add(457); // Locations
        PagesList.Add(7317); // Location List
        PagesList.Add(7354); // Transfer Orders
        PagesList.Add(5773); // Posted Transfer Shipments
        PagesList.Add(5774); // Posted Transfer Receipts
        PagesList.Add(271); // Bin Contents List
        PagesList.Add(7354); // Transfer Order List

        // Manufacturing
        PagesList.Add(99000784); // Production Order List
        PagesList.Add(99000831); // Released Production Orders
        PagesList.Add(99000773); // Production BOM List
        PagesList.Add(99000767); // Routing List
        PagesList.Add(5405); // Production Forecast

        // Service Management
        PagesList.Add(5900); // Service Order List
        PagesList.Add(5935); // Service Invoice List
        PagesList.Add(5970); // Service Contract List
        PagesList.Add(5971); // Service Contract Quote List
        PagesList.Add(5968); // Service Item List
        PagesList.Add(5915); // Posted Service Invoices
        PagesList.Add(5914); // Posted Service Shipments

        // Jobs & Projects
        PagesList.Add(89); // Job List
        PagesList.Add(88); // Job Card
        PagesList.Add(92); // Job Ledger Entries
        PagesList.Add(1001); // Job Task Lines
        PagesList.Add(1005); // Job Planning Lines
        PagesList.Add(1020); // Job Journal

        // Fixed Assets
        PagesList.Add(5601); // Fixed Asset List
        PagesList.Add(5604); // Fixed Asset Card
        PagesList.Add(5604); // FA Ledger Entries
        PagesList.Add(5611); // FA Depreciation Books

        // Setup & Configuration
        PagesList.Add(461); // Payment Terms
        PagesList.Add(11); // Payment Methods
        PagesList.Add(464); // Shipment Methods
        PagesList.Add(10); // Shipping Agents
        PagesList.Add(299); // Countries/Regions
        PagesList.Add(9); // Currencies
        PagesList.Add(204); // Units of Measure
        PagesList.Add(5196); // Responsibilities

        // Additional Commonly Used
        PagesList.Add(314); // Responsibility Centers
        PagesList.Add(5050); // Contact List
        PagesList.Add(5052); // Contact Card
        PagesList.Add(5200); // Employee List
        PagesList.Add(5201); // Employee Card
        PagesList.Add(254); // VAT Entries
        PagesList.Add(99000856); // Work Center List
        PagesList.Add(99000864); // Machine Center List
    end;

    local procedure IsPageAlreadyPublished(PageID: Integer): Boolean
    var
        TenantWebService: Record "Tenant Web Service";
    begin
        TenantWebService.SetRange("Object Type", TenantWebService."Object Type"::Page);
        TenantWebService.SetRange("Object ID", PageID);
        exit(not TenantWebService.IsEmpty);
    end;

    local procedure PublishPage(PageID: Integer): Boolean
    var
        TenantWebService: Record "Tenant Web Service";
        AllObjWithCaption: Record AllObjWithCaption;
        ServiceName: Text[240];
    begin
        // Get the page name
        AllObjWithCaption.SetRange("Object Type", AllObjWithCaption."Object Type"::Page);
        AllObjWithCaption.SetRange("Object ID", PageID);
        if not AllObjWithCaption.FindFirst() then
            exit(false);

        // Create service name from page name (remove spaces and special characters)
        ServiceName := DelChr(AllObjWithCaption."Object Caption", '=', ' /-()');
        ServiceName := 'BC_' + ServiceName;

        // Ensure unique service name
        if TenantWebService.Get(TenantWebService."Object Type"::Page, ServiceName) then
            ServiceName := ServiceName + '_' + Format(PageID);

        // Create the web service record
        Clear(TenantWebService);
        TenantWebService.Init();
        TenantWebService."Object Type" := TenantWebService."Object Type"::Page;
        TenantWebService."Object ID" := PageID;
        TenantWebService."Service Name" := CopyStr(ServiceName, 1, MaxStrLen(TenantWebService."Service Name"));
        TenantWebService.Published := true;

        if TenantWebService.Insert(true) then
            exit(true)
        else
            exit(false);
    end;
}
