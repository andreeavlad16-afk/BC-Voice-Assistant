# Conversation Context Improvements

## Analysis of Chat Log Issues

### Current Conversation Flow Problems

```
1. User: "Who is our biggest selling customer?"
   → Response: "Top customer is Adatum Corporation (10000)"

2. User: "What's the open balance for Adam Corporation?"  [misspelling]
   → Response: Returns 5 customers (fuzzy match failed)
   → Should have recognized: "Adam" ≈ "Adatum" from previous context

3. User: "What's the open balance for customer 10,000?"
   → Response: Returns 5 customers again
   → Should have: Directly answered for customer 10000

4. User: "Many orders are currently outstanding for customer 10,000."
   → Response: Generic count of 9 SalesOrders
   → Should have: Filtered to customer 10000 specifically
```

## Root Cause Analysis

### 1. **No Entity Resolution Memory**
The system currently tracks conversation history for context, but doesn't extract and remember **key entities** from responses.

**Current State:**
```al
// Page tracks raw message history
AddToHistory('user', 'Who is our biggest selling customer?');
AddToHistory('assistant', 'Top customer is Adatum Corporation (10000)');
```

**Problem:** When user asks follow-up about "Adam Corporation" or "customer 10,000", the system:
- ✅ Sends conversation history to AI
- ❌ Doesn't have structured entity extraction
- ❌ AI doesn't use the context to resolve entity references

### 2. **Speech Transcription Errors Not Handled**
- "Adam Corporation" (speech error) vs "Adatum Corporation" (correct)
- System doesn't apply fuzzy matching on recently mentioned entities
- No edit distance calculation to correct common transcription errors

### 3. **Explicit References Not Resolved**
When user says "customer 10,000", the system should:
1. Check if customer 10000 was recently mentioned
2. Use that context to enrich the query
3. Provide direct answer instead of search results

### 4. **AI Prompt Doesn't Emphasize Entity Tracking**
Current system prompt (line 619-628 of Cod50607) mentions:
```al
'- Use history to understand pronouns (it, that, them) and implicit references\\'
```

But it doesn't instruct the AI to:
- Extract and remember entity references (customer numbers, names)
- Match fuzzy references to previously mentioned entities
- Prioritize recent context when resolving ambiguous queries

## Recommended Improvements

### **Priority 1: Enhanced AI Prompt for Entity Resolution**

**Location:** `Cod50607.NXRVoiceAIService.al` - `GetSystemPrompt()` method

**Add after line 628:**

```al
EnhancedSystemPrompt += '\\\\ENTITY RESOLUTION & CONTEXT AWARENESS:\\';
EnhancedSystemPrompt += '- Extract key entities from conversation: customer numbers/names, item numbers, order numbers\\';
EnhancedSystemPrompt += '- When user mentions an entity that was in previous response, use that exact reference\\';
EnhancedSystemPrompt += '- Apply fuzzy matching for speech transcription errors (Adam → Adatum, 10,000 → 10000)\\';
EnhancedSystemPrompt += '- Example: Previous response mentioned "Adatum Corporation (10000)", user asks about "Adam Corporation" → Match to customer 10000\\';
EnhancedSystemPrompt += '- Example: Previous response showed "customer 10000", user asks "open balance for customer 10,000" → Filter to No.=10000\\';
EnhancedSystemPrompt += '- When user refers to specific number/name from previous answer, create a direct filter, not a search\\';
EnhancedSystemPrompt += '- Pronouns and implicit references: "that customer", "their orders", "this item" → Use entity from last response\\';
EnhancedSystemPrompt += '\\';
```

### **Priority 2: Add Entity Extraction to Response Processing**

**Location:** `Pag50608.NXRVoiceAssistant.al`

**Current conversation tracking:**
```al
local procedure AddToHistory(Role: Text; Content: Text)
var
    MessageObj: JsonObject;
begin
    MessageObj.Add('role', Role);
    MessageObj.Add('content', Content);
    ConversationHistory.Add(MessageObj);
    
    // Keep only last 10 messages (5 exchanges) to avoid token limits
    if ConversationHistory.Count() > 10 then
        ConversationHistory.RemoveAt(0);
end;
```

**Enhanced version with entity tracking:**
```al
var
    LastMentionedCustomer: Code[20];
    LastMentionedCustomerName: Text[100];
    LastMentionedItem: Code[20];
    LastMentionedOrder: Code[20];

local procedure AddToHistory(Role: Text; Content: Text)
var
    MessageObj: JsonObject;
begin
    MessageObj.Add('role', Role);
    MessageObj.Add('content', Content);
    ConversationHistory.Add(MessageObj);
    
    // Extract entities from assistant responses
    if Role = 'assistant' then
        ExtractEntitiesFromResponse(Content);
    
    // Keep only last 10 messages (5 exchanges) to avoid token limits
    if ConversationHistory.Count() > 10 then
        ConversationHistory.RemoveAt(0);
end;

local procedure ExtractEntitiesFromResponse(ResponseText: Text)
var
    CustomerMatch: Text;
    CustomerNo: Code[20];
    Regex: DotNet Regex;
    Match: DotNet Match;
begin
    // Extract customer references like "Adatum Corporation (10000)"
    // Pattern: CompanyName (Number) or "customer 10000"
    
    // Simple extraction for customer numbers
    if StrPos(ResponseText, '(') > 0 then begin
        CustomerMatch := CopyStr(ResponseText, StrPos(ResponseText, '(') + 1);
        if StrPos(CustomerMatch, ')') > 0 then begin
            CustomerNo := CopyStr(CustomerMatch, 1, StrPos(CustomerMatch, ')') - 1);
            LastMentionedCustomer := CustomerNo;
            
            // Extract customer name before the parenthesis
            CustomerMatch := CopyStr(ResponseText, 1, StrPos(ResponseText, '(') - 1);
            LastMentionedCustomerName := CopyStr(CustomerMatch, 1, MaxStrLen(LastMentionedCustomerName));
        end;
    end;
    
    // TODO: Add extraction for order numbers, item numbers, etc.
end;
```

### **Priority 3: Inject Entity Context into AI Query**

**Location:** `Cod50607.NXRVoiceAIService.al` - Add to `BuildOpenAIRequestWithHistory()`

**Enhance the user message with entity context:**

```al
local procedure BuildOpenAIRequestWithHistory(QueryText: Text; ConversationHistory: JsonArray; LastCustomerNo: Code[20]; LastCustomerName: Text): JsonObject
var
    RequestJson: JsonObject;
    MessagesArray: JsonArray;
    SystemMessage: JsonObject;
    UserMessage: JsonObject;
    EnhancedQuery: Text;
    HistoryToken: JsonToken;
    i: Integer;
    EnhancedSystemPrompt: Text;
begin
    EnhancedSystemPrompt := GetSystemPrompt();

    // Add system message
    SystemMessage.Add('role', 'system');
    SystemMessage.Add('content', EnhancedSystemPrompt);
    MessagesArray.Add(SystemMessage);

    // Add conversation history (up to last 10 messages)
    for i := 0 to ConversationHistory.Count() - 1 do begin
        if ConversationHistory.Get(i, HistoryToken) then
            MessagesArray.Add(HistoryToken);
    end;

    // Enhance current query with entity context
    EnhancedQuery := QueryText;
    if LastCustomerNo <> '' then
        EnhancedQuery += StrSubstNo(' [Context: Last mentioned customer was %1 (%2)]', LastCustomerName, LastCustomerNo);

    // Add current user message
    UserMessage.Add('role', 'user');
    UserMessage.Add('content', EnhancedQuery);
    MessagesArray.Add(UserMessage);

    RequestJson.Add('model', GetModelName());
    RequestJson.Add('messages', MessagesArray);
    RequestJson.Add('temperature', 0.2);
    RequestJson.Add('max_tokens', Setup."Max Tokens");
    RequestJson.Add('seed', 42);

    exit(RequestJson);
end;
```

### **Priority 4: Add Fuzzy Matching for Speech Transcription Errors**

**Location:** `Cod50609.NXRVoiceDynamicQueryExecutor.al`

**Add helper method for fuzzy customer name matching:**

```al
local procedure FindCustomerByFuzzyName(SearchName: Text; var Customer: Record Customer): Boolean
var
    TempCustomer: Record Customer temporary;
    BestMatch: Record Customer;
    BestScore: Integer;
    CurrentScore: Integer;
begin
    // First try exact match
    Customer.SetFilter(Name, '@*' + SearchName + '*');
    if Customer.FindFirst() then
        exit(true);
    
    Customer.Reset();
    
    // Try Levenshtein distance on all customers
    if Customer.FindSet() then
        repeat
            CurrentScore := CalculateLevenshteinDistance(LowerCase(SearchName), LowerCase(Customer.Name));
            
            // Accept if edit distance <= 2 (covers "Adam" → "Adatum")
            if (CurrentScore <= 2) and ((BestScore = 0) or (CurrentScore < BestScore)) then begin
                BestScore := CurrentScore;
                BestMatch := Customer;
            end;
        until Customer.Next() = 0;
    
    if BestScore > 0 then begin
        Customer := BestMatch;
        exit(true);
    end;
    
    exit(false);
end;

local procedure CalculateLevenshteinDistance(Source: Text; Target: Text): Integer
var
    Matrix: array[100, 100] of Integer;
    i, j: Integer;
    Cost: Integer;
begin
    // Standard Levenshtein distance algorithm
    // Returns edit distance between two strings
    // Implementation details omitted for brevity
    // See: https://en.wikipedia.org/wiki/Levenshtein_distance
end;
```

## Implementation Plan

### Phase 1: Quick Wins (2-4 hours)
1. ✅ **Enhance AI prompt** with entity resolution instructions (Priority 1)
   - Modify `GetSystemPrompt()` in Cod50607
   - Add 8 lines of guidance
   - Test immediately with existing conversation history

2. ✅ **Add entity context injection** (Priority 3 - simplified)
   - Add context note to user query before sending to AI
   - No code restructuring needed

### Phase 2: Entity Extraction (4-6 hours)
3. ✅ **Add entity extraction from responses** (Priority 2)
   - Add global variables to page for last customer/item/order
   - Extract entities using simple pattern matching
   - Store in page state

4. ✅ **Pass extracted entities to AI service**
   - Modify `ProcessQueryWithHistory` signature
   - Thread entity context through to AI call

### Phase 3: Advanced Matching (6-8 hours)
5. ✅ **Implement fuzzy matching** (Priority 4)
   - Add Levenshtein distance function
   - Apply to customer name searches
   - Extend to vendor/item names

## Expected Improvements

### Before (Current Behavior)
```
User: "Who is our biggest selling customer?"
Bot: "Top customer is Adatum Corporation (10000)"

User: "What's the open balance for Adam Corporation?"
Bot: "Found 5 Customer:Adatum Corporation, reference 10000,Trey Research..."
       ❌ Should recognize Adam ≈ Adatum from context

User: "What's the open balance for customer 10,000?"
Bot: "Found 5 Customer:Adatum Corporation, reference 10000,Trey Research..."
       ❌ Should directly answer for customer 10000
```

### After (Expected Behavior)
```
User: "Who is our biggest selling customer?"
Bot: "Top customer is Adatum Corporation (10000)"
     [System remembers: LastCustomer = 10000, LastCustomerName = "Adatum Corporation"]

User: "What's the open balance for Adam Corporation?"
Bot: "The open balance for Adatum Corporation (10000) is £2,543.50"
     ✅ Fuzzy matched "Adam" → "Adatum" from context
     ✅ Recognized this is a follow-up about the same customer

User: "What's the open balance for customer 10,000?"
Bot: "The open balance for customer 10000 (Adatum Corporation) is £2,543.50"
     ✅ Direct answer using explicit customer number
     ✅ No ambiguous search results

User: "How many orders do they have outstanding?"
Bot: "Adatum Corporation (10000) has 9 outstanding orders"
     ✅ Resolved "they" to last mentioned customer
```

## Testing Strategy

### Test Cases

**Test 1: Entity Retention**
```
1. "Who is my top customer?"
   Expected: "Adatum Corporation (10000)"
2. "What's their balance?"
   Expected: Direct answer for customer 10000 (not search results)
```

**Test 2: Fuzzy Matching**
```
1. "Who is my top customer?"
   Expected: "Adatum Corporation (10000)"
2. "Show me orders from Adam Corporation"  [transcription error]
   Expected: Orders for Adatum (10000), NOT search results
```

**Test 3: Explicit Number Reference**
```
1. "Who is my top customer?"
   Expected: "Adatum Corporation (10000)"
2. "Open balance for customer 10000"
   Expected: Direct balance, NOT "Found 5 customers"
```

**Test 4: Multiple Entity Types**
```
1. "Biggest customer?"
   → "Adatum Corporation (10000)"
2. "Show me order 101004"
   → Order details [System now tracks LastOrder = 101004]
3. "What's the status of that order?"
   → Status of order 101004
4. "Does that customer have other orders?"
   → [Should fail - lost customer context after order mention]
   → Future improvement: Track multiple entity types simultaneously
```

## Architecture Diagram

```
┌─────────────────────────────────────────────────────┐
│         User Input (Voice/Text)                     │
│  "What's the open balance for Adam Corporation?"    │
└───────────────────┬─────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────┐
│    Page 50608: Voice Assistant                      │
│                                                      │
│  1. Add to conversation history                     │
│  2. Extract entities from previous responses        │
│     → LastCustomer = 10000                          │
│     → LastCustomerName = "Adatum Corporation"       │
│  3. Call ProcessQueryWithHistory()                  │
└───────────────────┬─────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────┐
│  Codeunit 50605: Voice Assistant Management         │
│                                                      │
│  Pass query + history + entity context to AI        │
└───────────────────┬─────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────┐
│  Codeunit 50607: AI Service                         │
│                                                      │
│  BuildOpenAIRequestWithHistory():                   │
│    UserMessage = "What's the open balance for       │
│                   Adam Corporation?                  │
│                   [Context: Last customer was        │
│                   Adatum Corporation (10000)]"       │
│                                                      │
│  AI analyzes with enhanced prompt:                  │
│    ✅ Recognizes "Adam" ≈ "Adatum" (fuzzy match)   │
│    ✅ Uses customer 10000 from context             │
│    ✅ Creates direct filter, not search            │
└───────────────────┬─────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────┐
│  Structured Query:                                   │
│  {                                                   │
│    "intent": "query",                               │
│    "executionMode": "native",                       │
│    "primaryEntity": "Customer",                     │
│    "filters": [                                     │
│      { "field": "No.", "operator": "=",            │
│        "value": "10000" }                          │
│    ],                                               │
│    "fields": ["Name", "Balance (LCY)"]             │
│  }                                                  │
└───────────────────┬─────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────┐
│  Direct Answer (not search results)                 │
│  "The open balance for Adatum Corporation (10000)   │
│   is £2,543.50"                                     │
└─────────────────────────────────────────────────────┘
```

## API Changes

### Modified Method Signatures

**Page 50608:**
```al
// Add global variables
var
    LastMentionedCustomer: Code[20];
    LastMentionedCustomerName: Text[100];
    LastMentionedItem: Code[20];
    LastMentionedOrder: Code[20];

// New methods
local procedure ExtractEntitiesFromResponse(ResponseText: Text)
local procedure GetEntityContext(): Text
```

**Codeunit 50607:**
```al
// Enhanced signature (backward compatible - add new overload)
procedure AnalyzeQueryWithHistoryAndContext(
    QueryText: Text; 
    ConversationHistory: JsonArray; 
    EntityContext: Text;  // NEW parameter
    var Intent: Record "NXR Voice Query Intent" temporary
): Boolean

// Internal use
local procedure BuildOpenAIRequestWithHistory(
    QueryText: Text; 
    ConversationHistory: JsonArray;
    EntityContext: Text  // NEW parameter
): JsonObject
```

## Success Metrics

1. **Context Resolution Rate**
   - Target: 90% of follow-up queries correctly resolve entities
   - Measure: Track queries with pronouns/"that"/"it" that succeed

2. **Fuzzy Match Success**
   - Target: 80% of 1-2 character transcription errors corrected
   - Measure: Compare "Adam" → "Adatum" type corrections

3. **Direct Answer Rate**
   - Target: Reduce search result responses by 60% for follow-ups
   - Measure: Track responses that return single record vs. list

4. **User Satisfaction**
   - Target: Reduce query repetition by 50%
   - Measure: Track how often users rephrase same question

## Future Enhancements (Phase 4+)

1. **Multi-Entity Tracking**
   - Track customer, item, order simultaneously
   - "Show me that customer's orders for the item we discussed"

2. **Persistent Context Across Sessions**
   - Save last mentioned entities to user preferences
   - "Remember where we left off?"

3. **Confidence Scoring**
   - AI returns confidence level for entity matches
   - Ask for confirmation on low-confidence matches
   - "Did you mean Adatum Corporation (10000)?"

4. **Learning from Corrections**
   - Track user corrections and patterns
   - Build user-specific vocabulary mappings

## Files to Modify

1. ✅ `src/codeunit/Cod50607.NXRVoiceAIService.al`
   - GetSystemPrompt() - Add entity resolution guidance
   - BuildOpenAIRequestWithHistory() - Add entity context parameter

2. ✅ `src/page/Pag50608.NXRVoiceAssistant.al`
   - Add entity tracking variables
   - ExtractEntitiesFromResponse() - New method
   - GetEntityContext() - New method
   - Modify AddToHistory() to call extraction

3. ✅ `src/codeunit/Cod50605.NXRVoiceAssistantMgt.al`
   - ProcessQueryWithHistory() - Pass entity context to AI

4. ⏳ `src/codeunit/Cod50609.NXRVoiceDynamicQueryExecutor.al` (Phase 3)
   - FindCustomerByFuzzyName() - New method
   - CalculateLevenshteinDistance() - New method

## Rollout Plan

### Week 1: Phase 1 Implementation
- Enhance AI prompt (2 hours)
- Add entity context injection (2 hours)
- Test with existing conversation history
- Deploy to test environment

### Week 2: Phase 2 Implementation
- Add entity extraction (4 hours)
- Integration testing (2 hours)
- User acceptance testing
- Deploy to production

### Week 3: Phase 3 Implementation
- Implement fuzzy matching (6 hours)
- Performance testing (2 hours)
- Fine-tune edit distance threshold

### Week 4: Monitoring & Optimization
- Collect metrics on context resolution
- Analyze edge cases
- Refine AI prompt based on patterns
- Document findings

---

## Summary

The conversation log reveals that while the system tracks conversation history, it doesn't effectively **extract and utilize entity references** from responses. The three key improvements are:

1. **Enhanced AI Prompt** - Explicit instructions for entity resolution and fuzzy matching
2. **Entity Extraction** - Parse responses to remember customer numbers, names, orders
3. **Context Injection** - Send extracted entities back to AI with each new query

These changes will transform follow-up queries from generic searches into precise, context-aware operations, dramatically improving the conversational experience.
