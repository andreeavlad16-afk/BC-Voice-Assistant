codeunit 50629 "NXR Web Service Schema Bldr"
{
    /// <summary>
    /// Builds AI-friendly schema context from published BC Web Services
    /// Uses standard Web Service table (2000000076) for compatibility
    /// </summary>
    procedure BuildSchemaFromWebServices(): Text
    var
        WebService: Record "Web Service";
        SchemaText: Text;
    begin
        SchemaText := 'PUBLISHED WEB SERVICES (OData V4):\n\n';
        WebService.SetRange("Object Type", WebService."Object Type"::Page);
        WebService.SetRange(Published, true);

        if WebService.FindSet() then
            repeat
                SchemaText += BuildServiceSchema(WebService);
            until WebService.Next() = 0;

        exit(SchemaText);
    end;

    local procedure BuildServiceSchema(WebService: Record "Web Service"): Text
    var
        ServiceSchema: Text;
    begin
        // Service name and path
        ServiceSchema := StrSubstNo('Service: %1\n', WebService."Service Name");
    
    
    
    
    
    
    