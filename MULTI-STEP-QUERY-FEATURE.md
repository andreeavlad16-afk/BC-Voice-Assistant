# Multi-Step Query Guidance Feature

## Overview
The multi-step query feature enables the voice assistant to handle complex queries that cannot be executed in a single step. Instead of just saying "this query is not supported", the system now:

1. **Executes the first step** of what the user wants
2. **Returns partial results** from that first step
3. **Suggests the next query** with actual data filled in from step 1

This provides a graceful degradation path and teaches users how to work with the system's capabilities.

## Example Scenario

**User asks:** "Find me the vendor that sells the most critical items"

**System behavior:**
1. Recognizes this requires joining items and vendors (not supported in one query)
2. Executes step 1: "Find top items by sales volume"
3. Returns: "Your top selling item is 1970-S Touring Bicycle (50 units sold)"
4. Suggests: "💡 Next step: Which vendor supplies item 1970-S?"

## Implementation Details

### 1. AI Prompt Enhancement
**File:** `Cod50607.NXRVoiceAIService.al` (lines 689-698)

Added a new section to the system prompt explaining the multistep execution mode:

```
MULTI-STEP QUERY GUIDANCE:
When a query requires multiple steps (e.g., finding vendors for top items), use "multistep" mode:
- executionMode: "multistep"
- step1Query: The first query to execute (e.g., find top items)
- guidanceTemplate: Text suggesting next query with placeholders like {itemNo}, {customerName}
- reason: Brief explanation of why this requires multiple steps

Example: "Find vendor selling most critical items"
→ step1Query executes "top items by sales"
→ guidanceTemplate: "Which vendor supplies item {itemNo}?"
→ System executes step1, replaces {itemNo} with actual result, suggests next query
```

### 2. Query Routing Logic
**File:** `Cod50605.NXRVoiceAssistantMgt.al` (lines 82-86)

Added routing to handle the new execution mode:

```al
if ExecutionModeToken.AsValue().AsText() = 'multistep' then begin
    ResponseText := HandleMultiStepQuery(StructuredQueryJson);
    exit(ApplyDebug(ResponseText, DebugInfo));
end;
```

### 3. Multi-Step Handler Function
**File:** `Cod50605.NXRVoiceAssistantMgt.al` (lines 390-444)

The `HandleMultiStepQuery` function:
1. Extracts `step1Query` from the JSON
2. Executes it using `DynamicQueryExecutor.ExecuteStructuredQuery()`
3. Gets `guidanceTemplate` and `reason` from JSON
4. Calls `FormatGuidanceWithData()` to replace placeholders with actual results
5. Builds final response with emojis:
   - 📍 for reason explanation
   - 💡 for suggested next step

### 4. Template Formatting System
**File:** `Cod50605.NXRVoiceAssistantMgt.al` (lines 447-494)

The `FormatGuidanceWithData` function supports placeholder replacement:

**Supported placeholders:**
- `{itemNo}` - Item number from first item result
- `{itemDescription}` - Item description from first item result
- `{customerNo}` - Customer number from first customer result
- `{customerName}` - Customer name from first customer result
- `{locationCities}` - Comma-separated list of location cities

**Helper functions:**
- `ReplaceJsonPlaceholder()` - Replaces single field placeholders
- `ReplaceWithListPlaceholder()` - Replaces list placeholders with comma-separated values

## JSON Structure

When the AI returns a multistep query, it looks like:

```json
{
  "executionMode": "multistep",
  "step1Query": {
    "entity": "items",
    "operation": "top",
    "sortField": "quantityOnPurchaseOrder",
    "limit": 1
  },
  "guidanceTemplate": "Which vendor supplies item {itemNo}?",
  "reason": "This requires checking both items and vendors. I'll first find your most critical item."
}
```

## Example Use Cases

### 1. Vendor for Top Items
**Query:** "Find vendor that sells most critical items"
- **Step 1:** Execute "top items by purchase order quantity"
- **Result:** "1970-S Touring Bicycle (100 units on order)"
- **Guidance:** "Which vendor supplies item 1970-S?"

### 2. Customers in Location Cities
**Query:** "Show customers in cities where we have locations"
- **Step 1:** Execute "list all locations"
- **Result:** "London, Birmingham, Manchester"
- **Guidance:** "Show customers in London, Birmingham, Manchester"

### 3. Items Bought But Never Sold
**Query:** "Find items we bought but never sold"
- **Step 1:** Execute "items with zero sales quantity"
- **Result:** "Item 1896-S (0 sales)"
- **Guidance:** "Did we purchase item 1896-S? Check purchase orders for 1896-S"

## AI Training Considerations

The AI has been trained to:
1. **Recognize complexity** - Identify queries that need joins, multiple tables, or complex logic
2. **Break down logically** - Choose the most useful first step
3. **Provide context** - Explain WHY the query needs multiple steps
4. **Use actual data** - Fill in specific values (item numbers, names) in the suggested next query

## Benefits

1. **User Education** - Teaches users what the system can do
2. **Progressive Disclosure** - Shows results step-by-step instead of failing
3. **Natural Workflow** - Guides users through complex tasks conversationally
4. **Better UX** - Turns "no" into "yes, here's how"

## Testing Recommendations

Test with queries that require:
- ✅ Multiple table lookups (items + vendors)
- ✅ Filtering across relationships (customers in location cities)
- ✅ Aggregation + detail lookup (top items, then vendor details)
- ✅ Complex business logic (purchased but not sold)

## Future Enhancements

Potential improvements:
1. **Auto-execute second step** - If user confirms, automatically run the suggested query
2. **More placeholders** - Support vendor names, location codes, dates, etc.
3. **Multi-level steps** - Support 3+ step queries
4. **Context preservation** - Remember first step results for follow-up questions
5. **Smart caching** - Cache step 1 results for the follow-up query

## Related Files

- `Cod50607.NXRVoiceAIService.al` - AI prompt configuration
- `Cod50605.NXRVoiceAssistantMgt.al` - Multi-step routing and handler
- `Cod50609.NXRVoiceDynamicQueryExecutor.al` - Query execution
- `CONVERSATION-CONTEXT-IMPROVEMENTS.md` - Entity resolution strategy
- `ALPHANUMERIC-CODE-FIX-SUMMARY.md` - Number format handling

## Status

✅ **FULLY IMPLEMENTED** - Feature is complete and ready for testing
- AI prompt updated with multistep guidance
- Routing logic added to ProcessQueryWithHistoryInternal()
- HandleMultiStepQuery() function implemented
- Template formatting system with placeholder support
- Helper functions for JSON field replacement
