# Hackathon Learning: AI-Assisted Debugging Success Story

**Date:** January 30, 2026  
**Context:** EMEA Hackathon 2025 - BC Voice Assistant Project

## The Mystery Bug

**Symptom:** Text queries failing with "No records found" while voice queries worked perfectly.

**Initial Confusion:**
- Voice query: "ho many customrs in th databas" → ✅ Success (9 customers found)
- Text query: "How many customers are there in the database?" → ❌ Failure (no records)

This was bizarre - the SAME processing code, but different results!

## The Debugging Process

### Step 1: Enable Debug Mode
Added debug logging to see what was actually being received:

```al
if Setup.Get() and Setup."Debug Mode" then
    AddToConversation('[DEBUG] Input received: "' + InputText + '"');
```

### Step 2: The Smoking Gun
Debug output revealed the problem:

```json
{
  "rawQuery": "Many vendors are there in the database.",
  "structured": {
    "intent": "list",
    "primaryEntity": "Vendor",
    "fields": ["No.", "Name", "Balance (LCY)", "City", "Country/Region Code"],
    "filters": [
      {"field": "City", "operator": "=", "value": "the"}  // 🐛 BUG!
    ],
    "sort": null,
    "top": 0
  }
}
```

**The Bug:** Client-side pre-processing was treating "the" from "in **the** database" as a City filter! 
`WHERE City = 'the'` → No records match → Query fails

### Step 3: Root Cause Analysis
- **Voice queries:** Sent directly to Azure OpenAI → correct JSON generated
- **Text queries:** Pre-processed by broken client-side logic → bad filters injected → failure

### Step 4: The Fix (v2.1.8.5)
Bypassed the broken client-side processing entirely:

```al
// ALWAYS use AI processing - ignore client-side structured query
// Client-side parsing creates bad filters (e.g., "the" becomes City filter)
Response := VoiceAssistantMgt.ProcessQuery(RawQuery, BackendServiceUrl, BCWebServiceUrl);
```

## Key Takeaways

### ✅ What Worked Well
1. **Systematic debugging** - Added logging at the entry point to see raw input
2. **Debug mode architecture** - Having a debug flag that shows AI JSON was crucial
3. **Comparing working vs broken** - Voice vs text revealed the difference
4. **AI collaboration** - GitHub Copilot helped identify the issue quickly

### 🚨 Security Lesson Learned
**CREDENTIAL LEAK INCIDENT:** During troubleshooting, credentials were accidentally exposed in logs/screenshots. 

**Best Practices Going Forward:**
- Never share raw Azure logs/screenshots without sanitizing
- Mask API keys, connection strings, tokens before sharing
- Use Azure Key Vault references in app settings (not plain text)
- Rotate credentials immediately after any potential exposure
- Set up Azure cost alerts to detect abuse

### 💡 Hackathon Tips
1. **Debug mode is essential** - Build it in from day 1
2. **Log at entry points** - See what's actually arriving before processing
3. **Compare working vs broken** - When one path works and another fails, they're taking different routes
4. **Client-side "smart" processing can be dumb** - Sometimes simpler is better
5. **AI debugging partner** - Having GitHub Copilot suggest fixes saved hours

## Technical Details

### Architecture Decision
**Before:** Client-side attempted "smart" query parsing → Often wrong  
**After:** All queries sent to Azure OpenAI → Always correct

**Lesson:** Let the AI model do what it's trained for. Don't try to be clever on the client side.

### Performance Impact
**Concern:** Won't this make every query slower by calling OpenAI?  
**Reality:** Voice queries were already doing this. Text queries now have same (acceptable) latency for much better accuracy.

### Code Changes
- **Modified:** `Pag50608.NXRVoiceAssistant.al` - Removed client-side structured query handling
- **Version:** 2.1.8.5
- **Impact:** All queries now use AI processing (consistent behavior)

## Screenshot Reference
![AI Debugging in Action](./docs/ai-debugging-example.png)
*The actual debugging session showing the bad filter discovery*

---

## Follow-Up Features (v2.1.9.0)

After fixing the query bugs, we added conversational AI features:

### 1. Conversation History
**Problem:** AI had no memory of previous questions  
**Solution:** Track last 10 messages (5 exchanges) and send to AI with each query

**Implementation:**
```al
// Page tracks conversation
ConversationHistory: JsonArray;

procedure AddToHistory(Role: Text; Content: Text)
var
    MessageObj: JsonObject;
begin
    MessageObj.Add('role', Role);
    MessageObj.Add('content', Content);
    ConversationHistory.Add(MessageObj);
    
    // Keep only last 10 messages
    if ConversationHistory.Count() > 10 then
        ConversationHistory.RemoveAt(0);
end;
```

**Benefit:** AI understands context from previous queries

### 2. AI-Generated Follow-Up Suggestions
**Problem:** Static suggestions like "To see names, ask..." weren't contextual  
**Solution:** After each query, AI generates 2-3 relevant follow-up questions

**Example:**
```
User: "Give me the names of all vendors"
Assistant: Found 7 Vendor records:
- Vendor A
- Vendor B
...

You might also ask:
- Show me orders from my top vendor
- Which vendor has the most purchase orders?
```

**Implementation:**
- Separate AI call with conversation history
- Generates contextual suggestions based on:
  - User's query
  - System response
  - Query type (count, list, filter, etc.)
  - Previous conversation

**Lesson Learned:** Focus on ONE feature at a time
- v2.1.8.8: Response formatting only
- v2.1.8.10: Record limit only
- v2.1.9.0: Conversation history + follow-ups together (related features)

Each version was tested independently before moving to next feature.

---

**Moral of the story:** When something mysteriously works one way but not another, they're not taking the same path. Add logging, find the fork, compare the routes. The bug will reveal itself.

Then build features incrementally, one at a time, testing thoroughly between each addition.
