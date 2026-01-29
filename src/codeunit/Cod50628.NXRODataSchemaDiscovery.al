/// <summary>
/// Discovers all available OData entities (queries, tables, pages) from BC API.
/// Queries the $metadata endpoint to build comprehensive schema context.
/// </summary>
codeunit 50628 "NXR OData Schema Discovery"
{
    var
        Setup: Record "NXR Voice Assistant Setup";

    /// <summary>
    /// Discovers all OData entities and returns formatted schema.
    /// </summary>
    procedure DiscoverODataSchema(): Text
    var
        Client: HttpClient;
        Response: HttpResponseMessage;
        MetadataUrl: Text;
        MetadataXml: Text;
        Schema: Text;
    begin
        if not Setup.Get() then
            Error('Voice Assistant Setup not configured');

        // BC OData metadata endpoints
        MetadataUrl := GetODataMetadataUrl();
        
        Client.DefaultRequestHeaders.Add('Accept', 'application/xml');
        
        if not Client.Get(MetadataUrl, Response) then
            Error('Failed to connect to OData metadata endpoint');

        if not Response.IsSuccessStatusCode then
            Error('OData metadata request failed with status: %1', Response.HttpStatusCode);

        Response.Content.ReadAs(MetadataXml);
        
        Schema := ParseODataMetadata(MetadataXml);
        
        exit(Schema);
    end;

    local procedure GetODataMetadataUrl(): Text
    var
        BaseUrl: Text;
    begin
        // Get BC OData endpoint from environment
        // Standard BC OData v4: /api/v2.0/$metadata
        BaseUrl := GetUrl(ClientType::ODataV4);
        
        if BaseUrl = '' then
            Error('OData endpoint not available');

        // Remove any trailing slashes and add $metadata
        BaseUrl := DelChr(BaseUrl, '>', '/');
        exit(BaseUrl + '/$metadata');
    end;

    local procedure ParseODataMetadata(MetadataXml: Text): Text
    var
        Schema: Text;
        EntityTypes: List of [Text];
        EntityType: Text;
        EntityName: Text;
        Properties: Text;
    begin
        Schema := 'BUSINESS CENTRAL ODATA SCHEMA:\n\n';
        
        // Parse EntityType elements from EDMX metadata
        EntityTypes := ExtractEntityTypes(MetadataXml);
        
        foreach EntityType in EntityTypes do begin
            EntityName := ExtractEntityName(EntityType);
            Properties := ExtractEntityProperties(EntityType);
            
            if (EntityName <> '') and (Properties <> '') then
                Schema += EntityName + ': ' + Properties + '\n';
        end;

        if Schema = 'BUSINESS CENTRAL ODATA SCHEMA:\n\n' then
            Error('No OData entities found in metadata');

        exit(Schema);
    end;

    local procedure ExtractEntityTypes(MetadataXml: Text): List of [Text]
    var
        EntityTypes: List of [Text];
        EntityType: Text;
        StartPos: Integer;
        EndPos: Integer;
        SearchText: Text;
    begin
        // Find all <EntityType Name="..."> elements
        SearchText := '<EntityType Name="';
        StartPos := 1;
        
        repeat
            StartPos := MetadataXml.IndexOf(SearchText, StartPos);
            if StartPos > 0 then begin
                EndPos := MetadataXml.IndexOf('</EntityType>', StartPos);
                if EndPos > 0 then begin
                    EntityType := CopyStr(MetadataXml, StartPos, EndPos - StartPos + 13);
                    EntityTypes.Add(EntityType);
                    StartPos := EndPos + 1;
                end else
                    StartPos := 0;
            end;
        until StartPos = 0;

        exit(EntityTypes);
    end;

    local procedure ExtractEntityName(EntityType: Text): Text
    var
        NameStartPos: Integer;
        NameEndPos: Integer;
        EntityName: Text;
    begin
        // Extract: <EntityType Name="Customer"> -> "Customer"
        NameStartPos := EntityType.IndexOf('Name="');
        if NameStartPos = 0 then
            exit('');

        NameStartPos += 6; // Skip 'Name="'
        NameEndPos := EntityType.IndexOf('"', NameStartPos);
        
        if NameEndPos = 0 then
            exit('');

        EntityName := CopyStr(EntityType, NameStartPos, NameEndPos - NameStartPos);
        exit(EntityName);
    end;

    local procedure ExtractEntityProperties(EntityType: Text): Text
    var
        Properties: Text;
        PropertyName: Text;
        StartPos: Integer;
        EndPos: Integer;
        PropertyCount: Integer;
    begin
        // Extract all <Property Name="..."> elements
        StartPos := 1;
        PropertyCount := 0;
        
        repeat
            StartPos := EntityType.IndexOf('<Property Name="', StartPos);
            if StartPos > 0 then begin
                StartPos += 16; // Skip '<Property Name="'
                EndPos := EntityType.IndexOf('"', StartPos);
                
                if EndPos > 0 then begin
                    PropertyName := CopyStr(EntityType, StartPos, EndPos - StartPos);
                    
                    // Skip metadata properties
                    if not IsMetadataProperty(PropertyName) then begin
                        if PropertyCount > 0 then
                            Properties += ', ';
                        Properties += PropertyName;
                        PropertyCount += 1;
                    end;
                    
                    StartPos := EndPos + 1;
                end else
                    StartPos := 0;
            end;
        until (StartPos = 0) or (PropertyCount >= 50); // Limit to 50 properties per entity

        exit(Properties);
    end;

    local procedure IsMetadataProperty(PropertyName: Text): Boolean
    begin
        // Filter out OData metadata properties
        exit(
            (PropertyName = '@odata.etag') or
            (PropertyName = '@odata.context') or
            (PropertyName = '@odata.id') or
            (PropertyName = '@odata.type')
        );
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
        Message('OData schema refreshed successfully.\n\nDiscovered %1 characters of schema data.', StrLen(SchemaText));
    end;
}
