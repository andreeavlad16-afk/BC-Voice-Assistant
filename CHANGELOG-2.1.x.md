# BC Voice Assistant - Changelog (v2.1.x)

## Version 2.1.9.0 (January 30, 2026)

### 🎯 Major Features
- **Conversation History Tracking**: System now maintains last 10 messages (5 exchanges) and passes them to AI for contextual query understanding
- **AI-Generated Follow-Up Suggestions**: After each query, AI generates 2-3 relevant follow-up questions based on context
- **Enhanced AI Context**: AI receives full conversation history when analyzing new queries

### 📝 Changes
- `Pag50608`: Added `ConversationHistory` JsonArray and `AddToHistory()` method
- `Cod50605`: New `ProcessQueryWithHistory()` method wrapping existing logic
- `Cod50607`: New methods for history-aware AI processing:
  - `AnalyzeQueryWithHistory()`
  - `GenerateFollowUpSuggestions()`
  - `BuildOpenAIRequestWithHistory()`
  - `BuildFollowUpRequest()`

### 🔧 Technical Details
- Conversation history limited to 10 messages to avoid token limits
- Follow-up generation uses higher temperature (0.7) for creative suggestions
- Backward compatible: Old `ProcessQuery()` method delegates to new history-aware version

---

## Version 2.1.8.10 (January 30, 2026)

### 🐛 Bug Fixes
- Increased record display limit from 5 to 10 records for better list visibility

### 📝 Changes
- `Cod50609`: Updated `BuildRecordList()` threshold from 5 to 10

---

## Version 2.1.8.9 (January 30, 2026)

### ✨ Improvements
- Added single-table query preference guidance to AI prompt
- AI now strongly encouraged to prefer single-table queries over joins

### 📝 Changes
- `Cod50607`: Updated system prompt with "PREFER SINGLE-TABLE QUERIES" guidance

---

## Version 2.1.8.8 (January 30, 2026)

### ✨ Improvements
- Enhanced response formatting to show actual record names for small result sets (≤5 records)
- Added `BuildRecordList()` function to format detailed record lists

### 📝 Changes
- `Cod50609`: New `BuildRecordList()` method for formatting multi-record responses
- Response now shows names instead of just counts for small datasets

---

## Version 2.1.8.7 (January 30, 2026)

### 🐛 Bug Fixes
- Fixed RecordRef "not open" errors when checking FlowField status
- Wrapped FlowField detection in TryFunction for graceful error handling

### 📝 Changes
- `Cod50609`: Added `TryCheckIfFlowField()` for safe field class detection
- Updated `SortResultArrayIfNeeded()` to use TryFunction

---

## Version 2.1.8.6 (January 30, 2026)

### 🐛 Bug Fixes
- Attempted fix for RecordRef errors by reordering FieldClass check
- Issue: Still had errors, required v2.1.8.7 TryFunction approach

---

## Version 2.1.8.5 (January 30, 2026)

### 🐛 Major Bug Fix
- **Client-side preprocessing bypass**: Fixed text queries failing due to broken client-side logic
- Text queries creating invalid filters (e.g., "the" → City filter)
- All queries now use Azure OpenAI for consistent behavior

### 📝 Changes
- `Pag50608`: Removed client-side structured query handling
- Now bypasses JSON preprocessing and always sends raw text to AI
- Debug logging added at entry point

### 🔍 Debugging Story
- Discovered via debug mode that client parsed "in the database" incorrectly
- Created bad filter: `{"field":"City","operator":"=","value":"the"}`
- Voice queries worked because they skipped client preprocessing
- Documented in `HACKATHON-AI-DEBUGGING-EXAMPLE.md`

---

## Version 2.1.8.4 (January 30, 2026)

### 🐛 Bug Fixes
- Added debug logging to ProcessVoiceInput for troubleshooting
- Enhanced error tracking for query flow

---

## Version 2.1.8.3 (January 30, 2026)

### ✨ Improvements
- Updated AI system prompt to explicitly state native mode handles GROUP BY/aggregations
- Deprecated OData mode in favor of native execution

### 📝 Changes
- `Cod50607`: Updated SystemPromptLbl with native mode capabilities

---

## Version 2.1.8.2 (January 30, 2026)

### 🐛 Bug Fixes
- Fixed FlowField sorting causing "Invalid expression" errors
- Implemented post-query sorting for FlowFields instead of SETCURRENTKEY

### 📝 Changes
- `Cod50609`: Added `ApplyGenericSorting()` to detect FlowFields
- Added `SortResultArrayIfNeeded()` for post-query sorting
- Added `SortJsonArrayByField()` with selection sort implementation

---

## Version 2.1.8.1 (January 30, 2026)

### ✨ Improvements
- Added FlowField calculation support (Amount, Sales LCY, etc.)
- FlowFields now included in BuildRecordJson with automatic CalcField()

### 📝 Changes
- `Cod50609`: Enhanced BuildRecordJson to detect and calculate FlowFields

---

## Version 2.1.8.0 (January 30, 2026)

### 🎯 Major Refactoring
- **Metadata-Driven Architecture**: Completely removed hardcoded field selection
- Now returns ALL normal fields from any table dynamically

### 📝 Changes
- `Cod50609`: Refactored BuildRecordJson to iterate FieldCount
- Removed all entity-specific field lists
- Added dynamic field discovery using RecordRef/FieldRef

---

## Version 2.1.7.7 (January 29, 2026)

### 🐛 Bug Fixes
- Fixed field name formatting - "No." period causing JSON lookup mismatch
- Strip periods from field names in AddFieldToJson

---

## Version 2.1.7.3-2.1.7.6 (January 29, 2026)

### 🐛 Bug Fixes
- Fixed entity name mapping issues
- AI generated "SalesHeader" but code expected "SalesOrder"
- Added camelCase variants to GetTableNumber()
- Multiple iterations to cover all entity name variations

---

## Development Best Practices Learned

1. **Focus on One Feature at a Time**
   - Each version should have ONE clear purpose
   - Test thoroughly before moving to next feature
   - Makes debugging 10x easier

2. **Version Numbering**
   - Small fix: Increment patch (2.1.8.8 → 2.1.8.9)
   - Single feature: Increment minor (2.1.8.x → 2.1.9.0)
   - Major refactor: Increment major (2.x.x → 3.0.0)

3. **Debug Mode is Essential**
   - Build in logging from day 1
   - Log at entry points before processing
   - Compare working vs broken paths

4. **AI-Assisted Development**
   - Entire codebase built through GitHub Copilot
   - AI debugging partner saved countless hours
   - Document learnings for future reference

---

**Current Status:** ✅ Fully Operational  
**Latest Version:** 2.1.9.0  
**Last Updated:** January 30, 2026
