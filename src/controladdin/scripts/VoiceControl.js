// Voice Control Add-in for Business Central
// Uses Web Speech API + On-Device AI for intelligent query parsing
// Falls back to MediaRecorder + Cloud transcription for mobile

let backendUrl = '';
let recognition = null;
let synthesis = window.speechSynthesis;
let isListening = false;
let aiSession = null;

// MediaRecorder fallback for mobile
let mediaRecorder = null;
let audioChunks = [];
let useMediaRecorder = false;

// ============================================================================
// BC SCHEMA - Entity Relationships for On-Device AI
// ============================================================================
const bcSchema = {
    entities: {
        Customer: {
            table: "Customer",
            description: "Customer master data - companies or people who buy from us",
            aliases: ["customer", "client", "buyer", "account"],
            fields: {
                "No.": { type: "Code", key: true, description: "Customer number" },
                "Name": { type: "Text", description: "Customer name" },
                "Balance (LCY)": { type: "Decimal", flowField: true, description: "Amount owed by customer" },
                "Sales (LCY)": { type: "Decimal", flowField: true, description: "Total sales to customer" },
                "City": { type: "Text", description: "City" },
                "Country/Region Code": { type: "Code", description: "Country" },
                "Credit Limit (LCY)": { type: "Decimal", description: "Maximum credit allowed" }
            },
            links: {
                Item: { via: "Sales Line", foreignKey: "Sell-to Customer No.", description: "Items this customer has ordered" },
                SalesOrder: { via: "Sales Header", foreignKey: "Sell-to Customer No.", description: "Orders for this customer" },
                SalesInvoice: { via: "Sales Invoice Header", foreignKey: "Sell-to Customer No.", description: "Invoices for this customer" }
            }
        },
        Item: {
            table: "Item",
            description: "Products and services we sell or buy",
            aliases: ["item", "product", "sku", "part", "goods", "stock"],
            fields: {
                "No.": { type: "Code", key: true, description: "Item number" },
                "Description": { type: "Text", description: "Item description/name" },
                "Unit Price": { type: "Decimal", description: "Selling price" },
                "Unit Cost": { type: "Decimal", description: "Cost price" },
                "Inventory": { type: "Decimal", flowField: true, description: "Quantity in stock" },
                "Item Category Code": { type: "Code", description: "Category/type of item" },
                "Reorder Point": { type: "Decimal", description: "Minimum stock level" }
            },
            links: {
                Customer: { via: "Sales Line", foreignKey: "No.", targetKey: "Sell-to Customer No.", description: "Customers who buy this item" },
                Vendor: { via: "Purchase Line", foreignKey: "No.", targetKey: "Buy-from Vendor No.", description: "Vendors who supply this item" }
            }
        },
        Vendor: {
            table: "Vendor",
            description: "Suppliers we buy from",
            aliases: ["vendor", "supplier", "provider"],
            fields: {
                "No.": { type: "Code", key: true, description: "Vendor number" },
                "Name": { type: "Text", description: "Vendor name" },
                "Balance (LCY)": { type: "Decimal", flowField: true, description: "Amount we owe vendor" },
                "City": { type: "Text", description: "City" },
                "Country/Region Code": { type: "Code", description: "Country" }
            },
            links: {
                Item: { via: "Purchase Line", foreignKey: "Buy-from Vendor No.", description: "Items from this vendor" }
            }
        },
        SalesOrder: {
            table: "Sales Header",
            description: "Sales orders - customer requests for goods",
            aliases: ["order", "sales order", "so"],
            filter: { "Document Type": "Order" },
            fields: {
                "No.": { type: "Code", key: true, description: "Order number" },
                "Order Date": { type: "Date", description: "Date order was placed" },
                "Sell-to Customer No.": { type: "Code", description: "Customer number" },
                "Sell-to Customer Name": { type: "Text", description: "Customer name" },
                "Amount": { type: "Decimal", flowField: true, description: "Order total" },
                "Status": { type: "Option", description: "Open, Released, Pending" }
            },
            links: {
                Customer: { via: "direct", foreignKey: "Sell-to Customer No." },
                Item: { via: "Sales Line", foreignKey: "Document No." }
            }
        },
        SalesInvoice: {
            table: "Sales Invoice Header",
            description: "Posted sales invoices",
            aliases: ["invoice", "sales invoice", "bill"],
            fields: {
                "No.": { type: "Code", key: true, description: "Invoice number" },
                "Posting Date": { type: "Date", description: "Invoice date" },
                "Sell-to Customer No.": { type: "Code", description: "Customer number" },
                "Sell-to Customer Name": { type: "Text", description: "Customer name" },
                "Amount Including VAT": { type: "Decimal", flowField: true, description: "Invoice total with tax" }
            },
            links: {
                Customer: { via: "direct", foreignKey: "Sell-to Customer No." },
                Item: { via: "Sales Invoice Line", foreignKey: "Document No." }
            }
        },
        PurchaseOrder: {
            table: "Purchase Header",
            description: "Purchase orders - our orders to vendors",
            aliases: ["purchase order", "po", "purchase"],
            filter: { "Document Type": "Order" },
            fields: {
                "No.": { type: "Code", key: true, description: "PO number" },
                "Order Date": { type: "Date", description: "Date order was placed" },
                "Buy-from Vendor No.": { type: "Code", description: "Vendor number" },
                "Buy-from Vendor Name": { type: "Text", description: "Vendor name" },
                "Amount": { type: "Decimal", flowField: true, description: "Order total" }
            },
            links: {
                Vendor: { via: "direct", foreignKey: "Buy-from Vendor No." },
                Item: { via: "Purchase Line", foreignKey: "Document No." }
            }
        }
    },
    transactionTables: {
        "Sales Line": {
            description: "Line items on sales documents",
            joins: { Customer: "Sell-to Customer No.", Item: "No." },
            fields: ["Document Type", "Document No.", "Line No.", "Sell-to Customer No.", "No.", "Description", "Quantity", "Amount"]
        },
        "Purchase Line": {
            description: "Line items on purchase documents",
            joins: { Vendor: "Buy-from Vendor No.", Item: "No." },
            fields: ["Document Type", "Document No.", "Line No.", "Buy-from Vendor No.", "No.", "Description", "Quantity", "Amount"]
        },
        "Sales Invoice Line": {
            description: "Line items on posted sales invoices",
            joins: { Customer: "Sell-to Customer No.", Item: "No." },
            fields: ["Document No.", "Line No.", "Sell-to Customer No.", "No.", "Description", "Quantity", "Amount"]
        },
        "Item Ledger Entry": {
            description: "Historical item transactions for aggregation",
            aggregates: ["Quantity", "Sales Amount (Actual)", "Cost Amount (Actual)"],
            fields: ["Item No.", "Posting Date", "Entry Type", "Source No.", "Quantity", "Sales Amount (Actual)"]
        },
        "Value Entry": {
            description: "Value/cost entries for profitability",
            aggregates: ["Sales Amount (Actual)", "Cost Amount (Actual)"],
            fields: ["Item No.", "Posting Date", "Item Ledger Entry Type", "Sales Amount (Actual)", "Cost Amount (Actual)"]
        }
    },
    dateKeywords: {
        "today": { type: "specific", calculate: "TODAY" },
        "yesterday": { type: "specific", calculate: "TODAY-1" },
        "this week": { type: "range", start: "CALCDATE('<-CW>', TODAY)", end: "TODAY" },
        "last week": { type: "range", start: "CALCDATE('<-CW-1W>', TODAY)", end: "CALCDATE('<CW-1W>', TODAY)" },
        "this month": { type: "range", start: "CALCDATE('<-CM>', TODAY)", end: "TODAY" },
        "last month": { type: "range", start: "CALCDATE('<-CM-1M>', TODAY)", end: "CALCDATE('<CM-1M>', TODAY)" },
        "this quarter": { type: "range", start: "CALCDATE('<-CQ>', TODAY)", end: "TODAY" },
        "this year": { type: "range", start: "CALCDATE('<-CY>', TODAY)", end: "TODAY" },
        "last year": { type: "range", start: "CALCDATE('<-CY-1Y>', TODAY)", end: "CALCDATE('<CY-1Y>', TODAY)" }
    },
    aggregations: {
        "top": { type: "limit", sortDirection: "DESC" },
        "bottom": { type: "limit", sortDirection: "ASC" },
        "total": { type: "sum" },
        "average": { type: "avg" },
        "count": { type: "count" }
    }
};

// ============================================================================
// AI PROMPT TEMPLATE
// ============================================================================
const systemPrompt = `You are a Business Central query parser. Parse natural language into structured JSON queries.

SCHEMA:
${JSON.stringify(bcSchema.entities, null, 2)}

RELATIONSHIPS:
- Customer <-> Item: via Sales Line table (Sell-to Customer No. joins to Item No.)
- Vendor <-> Item: via Purchase Line table (Buy-from Vendor No. joins to Item No.)
- Use these links when user asks about relationships (e.g., "customers who bought X", "vendors who supply Y")

OUTPUT FORMAT (always valid JSON):
{
  "intent": "list|aggregate|count|compare",
  "primaryEntity": "Customer|Item|Vendor|SalesOrder|SalesInvoice|PurchaseOrder",
  "fields": ["field1", "field2"],
  "filters": [
    {"field": "fieldName", "operator": "=|>|<|>=|<=|<>|contains", "value": "value"}
  ],
  "linkedEntity": {
    "entity": "EntityName",
    "relationship": "description of link",
    "filter": {"field": "value"}
  },
  "dateFilter": {
    "field": "Order Date|Posting Date",
    "type": "specific|range",
    "value": "date or range description"
  },
  "sort": {"field": "fieldName", "direction": "ASC|DESC"},
  "top": 5,
  "aggregation": {"function": "SUM|AVG|COUNT", "field": "fieldName", "groupBy": "fieldName"}
}

EXAMPLES:
"Top 5 customers by sales" -> {"intent":"list","primaryEntity":"Customer","fields":["No.","Name","Sales (LCY)"],"sort":{"field":"Sales (LCY)","direction":"DESC"},"top":5}

"Which customers have ordered the London Swivel Chair?" -> {"intent":"list","primaryEntity":"Customer","fields":["No.","Name"],"linkedEntity":{"entity":"Item","filter":{"Description":"London Swivel Chair"}}}

"Vendors who supply items with low stock" -> {"intent":"list","primaryEntity":"Vendor","fields":["No.","Name"],"linkedEntity":{"entity":"Item","filter":{"Inventory":"<10"}}}

"Total sales by item this month" -> {"intent":"aggregate","primaryEntity":"Item","aggregation":{"function":"SUM","field":"Sales Amount","groupBy":"No."},"dateFilter":{"type":"range","value":"this month"}}

"Orders from last week" -> {"intent":"list","primaryEntity":"SalesOrder","fields":["No.","Order Date","Sell-to Customer Name","Amount"],"dateFilter":{"field":"Order Date","type":"range","value":"last week"}}

Parse this query and return ONLY valid JSON:`;

// ============================================================================
// ON-DEVICE AI INTEGRATION (Google AI Edge / Gemini Nano)
// ============================================================================
async function initializeOnDeviceAI() {
    try {
        // Check for Chrome's built-in AI (Gemini Nano)
        if (window.ai && window.ai.languageModel) {
            const capabilities = await window.ai.languageModel.capabilities();
            if (capabilities.available === 'readily' || capabilities.available === 'after-download') {
                aiSession = await window.ai.languageModel.create({
                    systemPrompt: systemPrompt
                });
                console.log('On-device AI initialized successfully');
                return true;
            }
        }
        console.log('On-device AI not available, will use fallback');
        return false;
    } catch (e) {
        console.log('On-device AI initialization failed:', e);
        return false;
    }
}

async function parseQueryWithAI(userQuery) {
    // Try on-device AI first
    if (aiSession) {
        try {
            const result = await aiSession.prompt(userQuery);
            const parsed = extractJSON(result);
            if (parsed) {
                console.log('On-device AI parsed:', parsed);
                return parsed;
            }
        } catch (e) {
            console.log('On-device AI error:', e);
        }
    }
    
    // Fallback to pattern matching
    return parseQueryWithPatterns(userQuery);
}

function extractJSON(text) {
    try {
        // Try to parse directly
        return JSON.parse(text);
    } catch (e) {
        // Try to extract JSON from text
        const jsonMatch = text.match(/\{[\s\S]*\}/);
        if (jsonMatch) {
            try {
                return JSON.parse(jsonMatch[0]);
            } catch (e2) {
                return null;
            }
        }
        return null;
    }
}

// ============================================================================
// PATTERN-BASED FALLBACK PARSER
// ============================================================================
function parseQueryWithPatterns(query) {
    const q = query.toLowerCase();
    const result = {
        intent: 'list',
        primaryEntity: null,
        fields: [],
        filters: [],
        linkedEntity: null,
        dateFilter: null,
        sort: null,
        top: 0
    };
    
    // Detect primary entity
    for (const [entityName, entity] of Object.entries(bcSchema.entities)) {
        for (const alias of entity.aliases) {
            if (q.includes(alias)) {
                result.primaryEntity = entityName;
                break;
            }
        }
        if (result.primaryEntity) break;
    }
    
    if (!result.primaryEntity) {
        result.primaryEntity = 'Customer'; // Default
    }
    
    // Detect linked entity queries
    // "customers who bought/ordered [item]"
    if (result.primaryEntity === 'Customer' && (q.includes('bought') || q.includes('ordered') || q.includes('purchased'))) {
        result.linkedEntity = { entity: 'Item', filter: {} };
        // Try to extract item reference
        const itemMatch = q.match(/(?:bought|ordered|purchased)\s+(?:the\s+)?(.+?)(?:\s+this|\s+last|\s*$)/i);
        if (itemMatch) {
            result.linkedEntity.filter = { Description: itemMatch[1].trim() };
        }
    }
    
    // "items that [customer] has ordered"
    if (result.primaryEntity === 'Item' && q.includes('customer')) {
        const customerMatch = q.match(/(?:customer|client)\s+(\w+)/i);
        if (customerMatch) {
            result.linkedEntity = { entity: 'Customer', filter: { "No.": customerMatch[1] } };
        }
    }
    
    // "vendors who supply [item]"
    if (result.primaryEntity === 'Vendor' && (q.includes('supply') || q.includes('provide') || q.includes('sell'))) {
        result.linkedEntity = { entity: 'Item', filter: {} };
        const itemMatch = q.match(/(?:supply|provide|sell)\s+(?:the\s+)?(.+?)(?:\s+this|\s+last|\s*$)/i);
        if (itemMatch) {
            result.linkedEntity.filter = { Description: itemMatch[1].trim() };
        }
    }
    
    // "items from vendor X" or "what do we buy from [vendor]"
    if (result.primaryEntity === 'Item' && (q.includes('from vendor') || q.includes('from supplier') || q.includes('buy from'))) {
        const vendorMatch = q.match(/(?:from|vendor|supplier)\s+(\w+)/i);
        if (vendorMatch) {
            result.linkedEntity = { entity: 'Vendor', filter: { Name: vendorMatch[1] } };
        }
    }
    
    // Detect Top N
    const topMatch = q.match(/top\s+(\d+)/i);
    if (topMatch) {
        result.top = parseInt(topMatch[1]);
        result.sort = { direction: 'DESC' };
    }
    
    const bottomMatch = q.match(/bottom\s+(\d+)/i);
    if (bottomMatch) {
        result.top = parseInt(bottomMatch[1]);
        result.sort = { direction: 'ASC' };
    }
    
    // Detect date filters
    for (const [keyword, dateConfig] of Object.entries(bcSchema.dateKeywords)) {
        if (q.includes(keyword)) {
            result.dateFilter = { type: dateConfig.type, value: keyword };
            break;
        }
    }
    
    // Detect aggregation intent
    if (q.includes('total') || q.includes('sum')) {
        result.intent = 'aggregate';
        result.aggregation = { function: 'SUM' };
    } else if (q.includes('average') || q.includes('avg')) {
        result.intent = 'aggregate';
        result.aggregation = { function: 'AVG' };
    } else if (q.includes('how many') || q.includes('count')) {
        result.intent = 'count';
    }
    
    // Detect specific filters
    // "items with inventory below/under X"
    const belowMatch = q.match(/(?:below|under|less than)\s+(\d+)/i);
    if (belowMatch && result.primaryEntity === 'Item') {
        result.filters.push({ field: 'Inventory', operator: '<', value: parseInt(belowMatch[1]) });
    }
    
    // "customers with balance over/above X"
    const aboveMatch = q.match(/(?:over|above|more than|greater than)\s+(\d+)/i);
    if (aboveMatch) {
        if (result.primaryEntity === 'Customer') {
            result.filters.push({ field: 'Balance (LCY)', operator: '>', value: parseInt(aboveMatch[1]) });
        } else if (result.primaryEntity === 'Item') {
            result.filters.push({ field: 'Inventory', operator: '>', value: parseInt(aboveMatch[1]) });
        }
    }
    
    // "in [city/country]"
    const inMatch = q.match(/\bin\s+(\w+)/i);
    if (inMatch && (result.primaryEntity === 'Customer' || result.primaryEntity === 'Vendor')) {
        result.filters.push({ field: 'City', operator: '=', value: inMatch[1] });
    }
    
    // Set default fields based on entity
    const entity = bcSchema.entities[result.primaryEntity];
    if (entity) {
        result.fields = Object.keys(entity.fields).slice(0, 5);
    }
    
    console.log('Pattern parser result:', result);
    return result;
}

// ============================================================================
// SPEECH RECOGNITION (Web Speech API or MediaRecorder fallback)
// ============================================================================
function initializeSpeechRecognition() {
    const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
    
    // Check if we're in a WebView (BC Mobile App) - Web Speech API won't work
    const isWebView = navigator.userAgent.includes('Mobile') && 
                      (navigator.userAgent.includes('BC') || 
                       navigator.userAgent.includes('Dynamics') ||
                       !window.chrome?.runtime);
    
    if (SpeechRecognition && !isWebView) {
        // Web Speech API available (desktop Chrome/Edge)
        recognition = new SpeechRecognition();
        recognition.continuous = false;
        recognition.interimResults = false;
        recognition.lang = 'en-GB';
        
        recognition.onstart = function() {
            updateStatus('Listening...');
            isListening = true;
        };
        
        recognition.onresult = async function(event) {
            const transcript = event.results[0][0].transcript;
            await processTranscript(transcript);
        };
        
        recognition.onerror = function(event) {
            // If Web Speech fails with not-allowed, try MediaRecorder fallback
            if (event.error === 'not-allowed' || event.error === 'service-not-allowed') {
                console.log('Web Speech API blocked, switching to MediaRecorder');
                recognition = null;
                useMediaRecorder = true;
                updateInputModeUI();
                startMediaRecording();
                return;
            }
            updateStatus('Error: ' + event.error);
            Microsoft.Dynamics.NAV.InvokeExtensibilityMethod('OnSpeechError', [event.error]);
            isListening = false;
        };
        
        recognition.onend = function() {
            updateStatus('Ready');
            isListening = false;
        };
        
        useMediaRecorder = false;
        return true;
    }
    
    // Fallback: MediaRecorder for mobile WebViews
    if (navigator.mediaDevices && navigator.mediaDevices.getUserMedia) {
        useMediaRecorder = true;
        console.log('Using MediaRecorder fallback for speech input');
        return true;
    }
    
    Microsoft.Dynamics.NAV.InvokeExtensibilityMethod('OnSpeechError', ['Speech input not supported on this device']);
    return false;
}

async function initializeMediaRecorder() {
    try {
        const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
        
        // Use m4a for iOS (native format), webm for others
        // Whisper supports: flac, m4a, mp3, mp4, mpeg, mpga, oga, ogg, wav, webm
        let mimeType = 'audio/webm;codecs=opus';
        
        // iOS/Safari - use audio/mp4 which MediaRecorder supports, but we'll report as m4a to transcription
        if (/iPad|iPhone|iPod/.test(navigator.userAgent) || (navigator.userAgent.includes('Safari') && !navigator.userAgent.includes('Chrome'))) {
            mimeType = 'audio/mp4'; // MediaRecorder format
        }
        
        // Verify support, fallback intelligently
        if (!MediaRecorder.isTypeSupported(mimeType)) {
            const supportedTypes = ['audio/webm', 'audio/mp4', 'audio/ogg', 'audio/wav'];
            mimeType = supportedTypes.find(type => MediaRecorder.isTypeSupported(type)) || '';
        }
        
        const options = mimeType ? { mimeType } : {};
        mediaRecorder = new MediaRecorder(stream, options);
        
        mediaRecorder.ondataavailable = (event) => {
            if (event.data.size > 0) {
                audioChunks.push(event.data);
            }
        };
        
        mediaRecorder.onstop = async () => {
            updateStatus('Transcribing...');
            const actualMimeType = mediaRecorder.mimeType || mimeType || 'audio/mp4';
            const audioBlob = new Blob(audioChunks, { type: actualMimeType });
            audioChunks = [];
            
            // Send to BC for transcription via cloud service
            await sendAudioForTranscription(audioBlob);
        };
        
        return true;
    } catch (e) {
        Microsoft.Dynamics.NAV.InvokeExtensibilityMethod('OnSpeechError', ['Microphone access denied: ' + e.message]);
        return false;
    }
}

async function sendAudioForTranscription(audioBlob) {
    try {
        // Convert blob to base64
        const reader = new FileReader();
        reader.readAsDataURL(audioBlob);
        
        reader.onloadend = async () => {
            const base64Audio = reader.result.split(',')[1]; // Remove data:audio/...;base64, prefix
            let mimeType = audioBlob.type || 'audio/webm';
            
            // Convert audio/mp4 to audio/m4a for OpenAI Whisper compatibility
            // iOS MediaRecorder uses audio/mp4 but Whisper expects m4a
            if (mimeType === 'audio/mp4' || mimeType.startsWith('audio/mp4;')) {
                mimeType = 'audio/m4a';
            }
            
            // Send to BC via control event
            const payload = {
                audioData: base64Audio,
                mimeType: mimeType,
                requestType: 'transcribe'
            };
            
            Microsoft.Dynamics.NAV.InvokeExtensibilityMethod('OnAudioInput', [JSON.stringify(payload)]);
        };
    } catch (e) {
        updateStatus('Error: ' + e.message);
        Microsoft.Dynamics.NAV.InvokeExtensibilityMethod('OnSpeechError', ['Failed to process audio: ' + e.message]);
    }
}

async function processTranscript(transcript) {
    updateStatus('Processing: ' + transcript);
    
    // Parse with AI or patterns
    const structuredQuery = await parseQueryWithAI(transcript);
    
    // Send both raw text and structured query to BC
    const payload = {
        rawQuery: transcript,
        structured: structuredQuery
    };
    
    Microsoft.Dynamics.NAV.InvokeExtensibilityMethod('OnVoiceInput', [JSON.stringify(payload)]);
}

// Called from BC after cloud transcription completes
function OnTranscriptionResult(transcript) {
    if (transcript && transcript.trim()) {
        processTranscript(transcript);
    } else {
        updateStatus('Could not understand audio');
        Microsoft.Dynamics.NAV.InvokeExtensibilityMethod('OnSpeechError', ['Transcription returned empty result']);
    }
}

function StartListening() {
    if (useMediaRecorder) {
        startMediaRecording();
    } else {
        startSpeechRecognition();
    }
}

async function startMediaRecording() {
    if (!mediaRecorder) {
        if (!await initializeMediaRecorder()) {
            return;
        }
    }
    
    if (isListening) {
        updateStatus('Already recording...');
        return;
    }
    
    try {
        audioChunks = [];
        mediaRecorder.start();
        isListening = true;
        updateStatus('Recording... (tap Stop when done)');
    } catch (e) {
        Microsoft.Dynamics.NAV.InvokeExtensibilityMethod('OnSpeechError', ['Could not start recording: ' + e.message]);
    }
}

function startSpeechRecognition() {
    if (!recognition) {
        if (!initializeSpeechRecognition()) {
            return;
        }
    }
    
    if (isListening) {
        updateStatus('Already listening...');
        return;
    }
    
    try {
        recognition.start();
    } catch (e) {
        Microsoft.Dynamics.NAV.InvokeExtensibilityMethod('OnSpeechError', ['Could not start listening: ' + e.message]);
    }
}

function StopListening() {
    if (useMediaRecorder && mediaRecorder && isListening) {
        mediaRecorder.stop();
        isListening = false;
        updateStatus('Processing...');
    } else if (recognition && isListening) {
        recognition.stop();
        isListening = false;
        updateStatus('Stopped');
    }
}

// ============================================================================
// TEXT TO SPEECH
// ============================================================================
function SpeakResponse(responseText) {
    if (!synthesis) {
        Microsoft.Dynamics.NAV.InvokeExtensibilityMethod('OnSpeechError', ['Text-to-speech not supported']);
        return;
    }
    
    synthesis.cancel();
    
    // Strip out debug information before speaking (but keep it in the UI)
    // Remove lines that start with [DEBUG]
    const spokenText = responseText
        .split('\n')
        .filter(line => !line.trim().startsWith('[DEBUG]'))
        .join('\n')
        .trim();
    
    const utterance = new SpeechSynthesisUtterance(spokenText);
    utterance.lang = 'en-GB';
    utterance.rate = 1.0;
    utterance.pitch = 1.0;
    utterance.volume = 1.0;
    
    utterance.onstart = function() {
        updateStatus('Speaking...');
    };
    
    utterance.onend = function() {
        updateStatus('Ready');
    };
    
    utterance.onerror = function(event) {
        Microsoft.Dynamics.NAV.InvokeExtensibilityMethod('OnSpeechError', ['Speech synthesis error: ' + event.error]);
    };
    
    synthesis.speak(utterance);
}

// Display response text without speaking (for Text Only Mode)
function DisplayResponse(responseText) {
    // Just update the status to show response received
    // The text will already be visible in the conversation area
    updateStatus('Response received (Text Only Mode)');
}

function SetBackendUrl(url) {
    backendUrl = url;
}

// ============================================================================
// UI FUNCTIONS
// ============================================================================
function updateStatus(statusText) {
    const statusElement = document.getElementById('status');
    if (statusElement) {
        statusElement.textContent = statusText;
        statusElement.className = 'status ' + getStatusClass(statusText);
    }
}

function getStatusClass(statusText) {
    if (statusText.includes('Listening')) return 'listening';
    if (statusText.includes('Recording')) return 'listening';
    if (statusText.includes('Speaking')) return 'speaking';
    if (statusText.includes('Processing')) return 'processing';
    if (statusText.includes('Transcribing')) return 'processing';
    if (statusText.includes('Error')) return 'error';
    return 'ready';
}

function updateInputModeUI() {
    const inputModeEl = document.getElementById('input-mode');
    if (inputModeEl) {
        if (useMediaRecorder) {
            inputModeEl.textContent = '🎤 Cloud transcription mode (mobile)';
            inputModeEl.className = 'input-mode cloud';
        } else if (recognition) {
            inputModeEl.textContent = '🎙️ Web Speech API (instant)';
            inputModeEl.className = 'input-mode native';
        } else {
            inputModeEl.textContent = '⚠️ Voice input not available';
            inputModeEl.className = 'input-mode unavailable';
        }
    }
}

// Initialize on load
document.addEventListener('DOMContentLoaded', async function() {
    const container = document.getElementById('controlAddIn');
    
    container.innerHTML = `
        <div class="voice-control-container">
            <div class="status-section">
                <div id="status" class="status ready">Initializing...</div>
                <div class="microphone-icon" id="mic-button" onclick="toggleListening()" style="cursor: pointer;">
                    <svg width="64" height="64" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
                        <path d="M12 1C10.34 1 9 2.34 9 4V12C9 13.66 10.34 15 12 15C13.66 15 15 13.66 15 12V4C15 2.34 13.66 1 12 1Z" stroke="currentColor" stroke-width="2"/>
                        <path d="M19 10V12C19 15.87 15.87 19 12 19C8.13 19 5 15.87 5 12V10" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>
                        <path d="M12 19V23M8 23H16" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>
                    </svg>
                    <div class="mic-hint">Tap to speak</div>
                </div>
                <div id="ai-status" class="ai-status"></div>
                <div id="input-mode" class="input-mode"></div>
            </div>
            <div class="text-input-section">
                <div class="text-input-container">
                    <input type="text" id="text-query" placeholder="Or type your question here..." 
                           onkeypress="handleTextInputKeypress(event)" />
                    <button id="send-btn" onclick="submitTextQuery()">
                        <svg width="24" height="24" viewBox="0 0 24 24" fill="none">
                            <path d="M2 21L23 12L2 3V10L17 12L2 14V21Z" fill="currentColor"/>
                        </svg>
                    </button>
                </div>
            </div>
            <div class="info-section">
                <p class="info-text">Tap the microphone or type your question</p>
                <p class="examples">Try asking:</p>
                <ul class="examples-list">
                    <li>"Who are my top 5 customers?"</li>
                    <li>"Which customers have ordered bicycles?"</li>
                    <li>"What vendors supply items with low stock?"</li>
                    <li>"Show me orders from this week"</li>
                    <li>"Items with inventory below 10"</li>
                    <li>"Total sales by customer this month"</li>
                </ul>
            </div>
        </div>
    `;
    
    // Check speech recognition availability
    initializeSpeechRecognition();
    
    // Update input mode indicator
    updateInputModeUI();
    
    // Initialize on-device AI
    const aiAvailable = await initializeOnDeviceAI();
    const aiStatusEl = document.getElementById('ai-status');
    if (aiStatusEl) {
        aiStatusEl.textContent = aiAvailable ? '🧠 On-device AI active' : '📝 Pattern matching mode';
        aiStatusEl.className = 'ai-status ' + (aiAvailable ? 'ai-active' : 'ai-fallback');
    }
    
    updateStatus('Ready');
});

// Toggle listening function for tap-to-speak
function toggleListening() {
    if (isListening) {
        StopListening();
    } else {
        StartListening();
    }
}

// Text input handlers
function handleTextInputKeypress(event) {
    if (event.key === 'Enter') {
        submitTextQuery();
    }
}

async function submitTextQuery() {
    const input = document.getElementById('text-query');
    const query = input.value.trim();
    
    if (!query) return;
    
    input.value = '';
    updateStatus('Processing...');
    
    // Process the text query same as voice
    await processTranscript(query);
}

// Notify BC that control is ready
Microsoft.Dynamics.NAV.InvokeExtensibilityMethod('OnReady', []);
