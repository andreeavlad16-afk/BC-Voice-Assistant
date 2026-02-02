# NXR Voice Assistant - Demo Script

## Introduction (30 seconds)

"NXR Voice Assistant is an AI-powered voice interface for Business Central that lets you query your ERP data using natural language, just like talking to a colleague. It uses Azure OpenAI to understand your intent, executes queries against Business Central, and speaks the results back to you - working on any device with a microphone."

---

## Demo Flow (5-7 minutes)

### 1. **Simple Queries** (1 minute)
*Start with basic data retrieval to show it works*

**Say:** "How many customers do we have?"
- **Shows:** Basic counting

**Say:** "Show me the top 5 customers"
- **Shows:** Sorting and limiting results

**Say:** "How many items are in stock?"
- **Shows:** Calculated fields

---

### 2. **Context Awareness** (1 minute)
*Demonstrate conversation memory*

**Say:** "Who is customer 10000?"
- **Result:** "Adatum Corporation, located in Atlanta"

**Say:** "What's their balance?"
- **Shows:** System remembers we're talking about customer 10000
- **Result:** "Adatum Corporation owes $X"

**Say:** "Show me their city"
- **Shows:** Still in context
- **Result:** "Atlanta"

---

### 3. **Regional Number Formats** (30 seconds)
*Show voice-friendly number handling*

**Say:** "Show me customer 10,000" *(with comma)*
- **Works:** System strips comma, finds "10000"

**Say:** "What about customer 20,000?"
- **Works:** Context + number format handling

---

### 4. **Fuzzy Search** (1 minute)
*Demonstrate intelligent matching*

**Say:** "Find items with bicycle in the name"
- **Shows:** Partial text matching
- **Result:** Shows all cycling-related products

**Say:** "Which customers are in London?"
- **Shows:** City filtering

**Say:** "Show me vendors"
- **Shows:** Vendor list

---

### 5. **Complex Queries** (1 minute)
*Show aggregation and sorting*

**Say:** "What are my top items by sales?"
- **Shows:** Sorting by calculated field

**Say:** "Which items are low on stock?"
- **Shows:** Business logic (below reorder point)

**Say:** "Show me recent sales invoices"
- **Shows:** Date filtering and recent records

---

### 6. **Multi-Step Guidance** (2 minutes)
*This is the killer feature - show intelligent orchestration*

**Say:** "Find the vendor that sells the most critical items"

**System Response:**
```
🔍 "I found your most critical item: 1970-S Touring Bicycle 
    (only 15 units in stock, reorder point is 20)"

💡 "To find the vendor, ask: Which vendor supplies item 1970-S?"

📍 "This requires checking both items and vendors, so I've broken 
    it into steps to help you get the answer."
```

**Then say:** "Which vendor supplies item 1970-S?"
- **Shows:** System executes second step
- **Result:** "Vendor V0001 - Alpine Ski House supplies item 1970-S"

**Alternative multi-step example:**

**Say:** "Show me customers in cities where we have locations"

**System Response:**
```
🔍 "We have locations in: London, Brighton, Manchester"

💡 "To find customers, ask: Show me customers in London, Brighton, or Manchester"

📍 "This requires cross-referencing locations and customers"
```

---

### 7. **Error Handling & Guidance** (30 seconds)
*Show how it handles unclear queries*

**Say:** "Find me stuff"
- **Shows:** System asks for clarification
- **Result:** "I can help you find customers, items, vendors, or other records. What would you like to search for?"

---

### 8. **Configuration** (1 minute)
*Show the setup page*

**Open:** NXR Voice Assistant Setup page

**Highlight:**
- Multiple AI backends (Azure OpenAI, Anthropic, Local LLM)
- Conversation History Size (0-50 messages)
- Debug Mode (show AI reasoning)
- Text Only Mode (disable voice output)

**Say:** "All of this works without any Business Central code changes - just OData API access"

---

## Key Differentiators to Mention

### Why Not Just Use MCP?
"Unlike Microsoft's Model Context Protocol which only works with BC version 27+, our architecture works with **any BC version that has OData** - that means v14 and up, cloud or on-premise."

### Intelligence Layer
"We built an orchestration layer *between* the AI and Business Central that handles:
- Regional number formats (US commas, European periods, Swiss apostrophes)
- Entity resolution ('customer 10,000' → '10000')
- Multi-step query breakdown
- Fuzzy matching
- Context preservation"

### Multi-Model Support
"You're not locked into one AI provider - swap between OpenAI, Anthropic's Claude, or even run it with local LLMs like Ollama for sensitive data."

### Future-Proof Architecture
"The same orchestration layer can connect to Dynamics F&O, CRM, SQL databases, or any API - it's not just a BC tool, it's an enterprise voice platform."

---

## Closing Statement (30 seconds)

"This is more than a voice interface - it's an intelligent agent that understands your business context, guides you through complex queries, and adapts to how *you* naturally speak. It works on iOS, Android, web, or the BC mobile app, and it's ready to deploy to your customers today."

---

## Quick Stats for Impact
- **Supported BC versions:** v14+ (any with OData)
- **Query types:** 50+ patterns (counting, filtering, sorting, aggregation, cross-entity)
- **Languages supported:** Any (Whisper transcription supports 50+ languages)
- **AI providers:** Azure OpenAI, OpenAI Direct, Anthropic, Local LLMs
- **Setup time:** < 15 minutes with Azure
- **Code changes to BC:** Zero

---

## Demo Tips

### Before You Start
1. ✅ Ensure microphone permissions are granted
2. ✅ Have a quiet environment (Whisper works well but background noise affects accuracy)
3. ✅ Open the Voice Assistant page in BC
4. ✅ Have debug mode OFF for cleaner responses (enable if something goes wrong)

### During Demo
- **Speak clearly** but naturally (no robot voice needed)
- **Pause** after system responds to let it finish speaking
- **Show the UI** - let people see the conversation history building up
- **Handle errors gracefully** - if Whisper misunderstands, just say "clear conversation" and try again

### Common Issues
- **"I got gibberish"** → Microphone picked up background noise, try again
- **"It's not responding"** → Check Azure OpenAI connection, enable debug mode
- **"Numbers are wrong"** → Demonstrate the number format cleaning by showing setup

---

## Test Queries (Backup List)

If you need more examples during Q&A:

**Simple:**
- "How many locations?"
- "List all employees"
- "What's the current company?"

**Filtering:**
- "Customers in Atlanta"
- "Items under $50"
- "Vendors with balance"

**Context-aware:**
- "Who is vendor V0001?" → "What's their balance?" → "Show their city"

**Business logic:**
- "Items below reorder point"
- "Customers with overdue invoices"
- "Top selling items this year"

**Multi-step (advanced):**
- "Find items we bought but never sold" → Guides to: "Items with zero sales quantity"
- "Customers who bought bicycles" → Complex filtering with guidance

---

*Last Updated: February 2, 2026*  
*Version: 2.2.0.39*
