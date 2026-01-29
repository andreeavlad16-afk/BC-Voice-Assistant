table 50601 "NXR Voice Query Intent"
{
    Caption = 'NXR Voice Query Intent';
    TableType = Temporary;

    fields
    {
        field(1; "Entry No."; Integer)
        {
            Caption = 'Entry No.';
            AutoIncrement = true;
        }

        field(10; "Query Text"; Text[250])
        {
            Caption = 'Query Text';
        }

        field(20; Entity; Enum "NXR Voice Entity Type")
        {
            Caption = 'Entity';
        }

        field(30; "Date Filter"; Date)
        {
            Caption = 'Date Filter';
        }

        field(40; "Date Range"; Enum "NXR Voice Date Range")
        {
            Caption = 'Date Range';
        }

        field(50; "Top N"; Integer)
        {
            Caption = 'Top N Records';
        }

        field(60; "Specific Filter"; Text[100])
        {
            Caption = 'Specific Filter';
        }

        field(70; "Structured Data"; Text[2048])
        {
            Caption = 'Structured Data (JSON)';
        }
    }

    keys
    {
        key(PK; "Entry No.")
        {
            Clustered = true;
        }
    }
}
