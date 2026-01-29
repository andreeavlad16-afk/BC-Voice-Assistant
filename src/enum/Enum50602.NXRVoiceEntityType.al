enum 50602 "NXR Voice Entity Type"
{
    Extensible = true;

    // Master Data - Customers & Contacts
    value(0; Customer) { Caption = 'Customer'; }
    value(1; Contact) { Caption = 'Contact'; }
    value(2; Salesperson) { Caption = 'Salesperson'; }

    // Master Data - Vendors & Purchasing
    value(3; Vendor) { Caption = 'Vendor'; }
    value(4; Purchaser) { Caption = 'Purchaser'; }

    // Master Data - Items & Inventory
    value(5; Item) { Caption = 'Item'; }
    value(6; ItemCategory) { Caption = 'Item Category'; }
    value(7; Location) { Caption = 'Location'; }
    value(8; Resource) { Caption = 'Resource'; }

    // Master Data - Financial
    value(9; GLAccount) { Caption = 'G/L Account'; }
    value(10; BankAccount) { Caption = 'Bank Account'; }
    value(11; Currency) { Caption = 'Currency'; }
    value(12; PaymentTerms) { Caption = 'Payment Terms'; }
    value(13; PaymentMethod) { Caption = 'Payment Method'; }
    value(14; FixedAsset) { Caption = 'Fixed Asset'; }

    // Master Data - Setup
    value(15; ShipmentMethod) { Caption = 'Shipment Method'; }
    value(16; ShippingAgent) { Caption = 'Shipping Agent'; }
    value(17; CountryRegion) { Caption = 'Country/Region'; }
    value(18; Employee) { Caption = 'Employee'; }

    // Sales Documents
    value(20; SalesOrder) { Caption = 'Sales Order'; }
    value(21; SalesQuote) { Caption = 'Sales Quote'; }
    value(22; SalesInvoice) { Caption = 'Sales Invoice'; }
    value(23; SalesCreditMemo) { Caption = 'Sales Credit Memo'; }
    value(24; SalesShipment) { Caption = 'Sales Shipment'; }
    value(25; SalesReturnOrder) { Caption = 'Sales Return Order'; }

    // Purchase Documents
    value(30; PurchaseOrder) { Caption = 'Purchase Order'; }
    value(31; PurchaseQuote) { Caption = 'Purchase Quote'; }
    value(32; PurchaseInvoice) { Caption = 'Purchase Invoice'; }
    value(33; PurchaseCreditMemo) { Caption = 'Purchase Credit Memo'; }
    value(34; PurchaseReceipt) { Caption = 'Purchase Receipt'; }
    value(35; PurchaseReturnOrder) { Caption = 'Purchase Return Order'; }

    // Ledger Entries
    value(40; GLEntry) { Caption = 'G/L Entry'; }
    value(41; CustomerLedgerEntry) { Caption = 'Customer Ledger Entry'; }
    value(42; VendorLedgerEntry) { Caption = 'Vendor Ledger Entry'; }
    value(43; ItemLedgerEntry) { Caption = 'Item Ledger Entry'; }
    value(44; ValueEntry) { Caption = 'Value Entry'; }
    value(45; BankAccountLedgerEntry) { Caption = 'Bank Account Ledger Entry'; }

    // Jobs & Projects
    value(50; Job) { Caption = 'Job'; }
    value(51; JobTask) { Caption = 'Job Task'; }
    value(52; JobPlanningLine) { Caption = 'Job Planning Line'; }
    value(53; JobLedgerEntry) { Caption = 'Job Ledger Entry'; }

    // Additional Transactions
    value(60; TransferOrder) { Caption = 'Transfer Order'; }
    value(61; ProductionOrder) { Caption = 'Production Order'; }
    value(62; AssemblyOrder) { Caption = 'Assembly Order'; }
    value(63; ServiceOrder) { Caption = 'Service Order'; }
}

