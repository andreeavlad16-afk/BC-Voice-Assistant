/**
 * BC Voice Assistant PWA v2
 * 
 * Thin client: records audio or accepts text, sends to Azure Function voiceRelay,
 * which handles transcription + BC API call. All intelligence stays in BC.
 */

// ============================================================================
// CONFIG
// ============================================================================
const CONFIG = {
    get relayUrl() { return localStorage.getItem('pwa2_relayUrl') || 'https://func-bcvoice-v2.azurewebsites.net/api/voicerelay'; },
    set relayUrl(v) { localStorage.setItem('pwa2_relayUrl', v); },
};

// ============================================================================
// STATE
// ============================================================================
let mediaRecorder = null;
let audioChunks = [];
let isRecording = false;
let isProcessing = false;

// ============================================================================
// DOM
// ============================================================================
const $ = (sel) => document.querySelector(sel);
const micBtn = $('#micBtn');
const sendBtn = $('#sendBtn');
const textInput = $('#textInput');
const conversation = $('#conversation');
const settingsBtn = $('#settingsBtn');
const settingsPanel = $('#settingsPanel');
const saveSettingsBtn = $('#saveSettingsBtn');
const cancelSettingsBtn = $('#cancelSettingsBtn');
const settingsStatus = $('#settingsStatus');
const recordingOverlay = $('#recordingOverlay');
const stopBtn = $('#stopBtn');

// ============================================================================
// SETTINGS
// ============================================================================
function loadSettings() {
    $('#relayUrl').value = CONFIG.relayUrl;
}

function saveSettings() {
    CONFIG.relayUrl = $('#relayUrl').value.trim().replace(/\/$/, '');
    settingsStatus.textContent = 'Saved!';
    settingsStatus.className = 'settings-status ok';
    setTimeout(() => {
        settingsPanel.classList.add('hidden');
        settingsStatus.textContent = '';
    }, 800);
    // Re-check connectivity after saving
    checkConnectivity().catch(() => {});
}

function toggleSettings() {
    const isHidden = settingsPanel.classList.contains('hidden');
    if (isHidden) {
        loadSettings();
        settingsPanel.classList.remove('hidden');
    } else {
        settingsPanel.classList.add('hidden');
    }
}

function toggleDebugPanel() {
    const panel = document.getElementById('debugPanel');
    const wasHidden = panel.classList.contains('hidden');
    panel.classList.toggle('hidden');
    if (wasHidden) {
        DEBUG.showVoices();
        DEBUG.log('=== Debug Panel Opened ===');
    }
}

// ============================================================================
// MESSAGES
// ============================================================================
// Update status indicator
function setStatus(text, color) {
    const statusText = document.querySelector('.status-text');
    const statusDot = document.querySelector('.status-dot');
    if (statusText) statusText.textContent = text;
    if (statusDot && color) statusDot.style.background = color;
}

// Derive base Function App URL (remove /api/voicerelay if present)
function getFunctionBaseUrl() {
    const url = CONFIG.relayUrl || '';
    return url.replace(/\/?api\/voicerelay$/i, '');
}

// Lightweight connectivity check using /api/test endpoint
async function checkConnectivity() {
    try {
        const base = getFunctionBaseUrl();
        if (!base) { setStatus('Not configured', '#d13438'); return; }
        const testUrl = base + '/api/test';
        setStatus('Checking connection…', '#f3f2f1');
        const res = await fetch(testUrl, { method: 'GET' });
        if (res.ok) {
            setStatus('Connected', '#107c10');
        } else {
            setStatus('Server error ' + res.status, '#ffaa44');
        }
    } catch (e) {
        setStatus('Network/CORS issue', '#d13438');
    }
}

function addMessage(type, text) {
    const div = document.createElement('div');
    div.className = `msg ${type}`;
    div.innerHTML = `<p>${escapeHtml(text)}</p>`;
    conversation.appendChild(div);
    conversation.scrollTop = conversation.scrollHeight;
    if (type === 'error') setStatus('Error', 'var(--error-color)');
    if (type === 'assistant') setStatus('Ready', 'var(--primary-color)');
    if (type === 'user') setStatus('Thinking...', 'var(--primary-dark)');
    return div;
}

function addProcessingMessage() {
    const div = document.createElement('div');
    div.className = 'msg assistant processing';
    div.id = 'processingMsg';
    div.innerHTML = '<p>Thinking...</p>';
    conversation.appendChild(div);
    conversation.scrollTop = conversation.scrollHeight;
    return div;
}

function removeProcessingMessage() {
    const el = $('#processingMsg');
    if (el) el.remove();
}

// ============================================================================
// DEBUG LOGGING FOR TTS (iOS troubleshooting)
// ============================================================================
const DEBUG = {
    logs: [],
    maxLogs: 50,
    
    log(message) {
        const timestamp = new Date().toLocaleTimeString();
        const entry = `[${timestamp}] ${message}`;
        this.logs.push(entry);
        if (this.logs.length > this.maxLogs) {
            this.logs.shift();
        }
        this.updateUI();
    },
    
    updateUI() {
        const logPanel = document.getElementById('ttsLog');
        if (logPanel) {
            logPanel.innerHTML = this.logs
                .map(log => `<div>${log}</div>`)
                .join('');
            logPanel.scrollTop = logPanel.scrollHeight;
        }
    },
    
    showVoices() {
        const voices = speechSynthesis.getVoices();
        const voiceInfo = document.getElementById('voiceInfo');
        if (voiceInfo) {
            if (voices.length === 0) {
                voiceInfo.innerHTML = '<div style="color:#f00;">❌ No voices available!</div>';
            } else {
                const voiceList = voices
                    .map((v, i) => `${i+1}. ${v.name} (${v.lang}${v.default ? ' [DEFAULT]' : ''})`) 
                    .join('<br>');
                voiceInfo.innerHTML = `<div>✓ Found ${voices.length} voices:<br>${voiceList}</div>`;
            }
        }
        this.log(`Voices loaded: ${voices.length}`);
    }
};

function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}

// ============================================================================
// SPEECH SYNTHESIS (Text-to-Speech)
// ============================================================================
function speak(text) {
    if (!('speechSynthesis' in window) || !text) {
        DEBUG.log('❌ Speech synthesis not supported or empty text');
        console.warn('Speech synthesis not supported or empty text');
        return;
    }
    
    DEBUG.log(`📢 speak() called: "${text.substring(0, 50)}..."`);
    console.log('speak() called with:', text.substring(0, 100));
    
    // Pre-load voices on iOS - critical for Safari
    speechSynthesis.getVoices();
    
    const utt = new SpeechSynthesisUtterance(text);
    utt.rate = 1.0;
    utt.pitch = 1.0;
    utt.volume = 1.0;
    
    // Get voices again after pre-load
    const voices = speechSynthesis.getVoices();
    DEBUG.log(`🎤 Available voices: ${voices.length}`);
    console.log('Available voices:', voices.length);
    
    if (voices.length > 0) {
        const preferred = voices.find(v =>
            v.name.includes('Samantha') ||
            v.name.includes('Victoria')
        );
        if (preferred) {
            utt.voice = preferred;
            DEBUG.log(`✓ Using voice: ${preferred.name}`);
            console.log('Using voice:', preferred.name);
        } else {
            utt.voice = voices[0];
            DEBUG.log(`⚠️ Voice not found, using: ${voices[0].name}`);
        }
    } else {
        DEBUG.log('⚠️ No voices available - using system default');
    }
    
    utt.onerror = (event) => {
        DEBUG.log(`❌ TTS Error: ${event.error}`);
        console.error('TTS error:', event.error);
    };
    
    utt.onstart = () => {
        DEBUG.log('▶️ Speech started');
        console.log('Speech started');
    };
    
    utt.onend = () => {
        DEBUG.log('⏸️ Speech ended');
        console.log('Speech ended');
    };
    
    utt.onpause = () => DEBUG.log('⏸️ Speech paused');
    utt.onresume = () => DEBUG.log('▶️ Speech resumed');
    
    DEBUG.log('→ Calling speechSynthesis.speak()');
    console.log('Calling speechSynthesis.speak()');
    speechSynthesis.speak(utt);
}

// ============================================================================
// RELAY API CALL
// ============================================================================
// Patch callRelay to show CORS/network troubleshooting for fetch errors
async function callRelay(payload) {
    if (!CONFIG.relayUrl) {
        throw new Error('Please configure the Relay URL in Settings');
    }
    let url = CONFIG.relayUrl;
    let response;
    try {
        response = await fetch(url, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload)
        });
    } catch (err) {
        addMessage('error', 'Network error: failed to fetch.\nThis is usually a CORS or HTTPS problem.\nMake sure you are online, using HTTPS, and the relay endpoint is accessible from your device.');
        throw err;
    }
    if (!response.ok) {
        const errText = await response.text();
        addMessage('error', `Relay error ${response.status}: ${errText}`);
        throw new Error(`Server error ${response.status}: ${errText.substring(0, 200)}`);
    }
    return await response.json();
}

// ============================================================================
// HANDLE TEXT QUERY
// ============================================================================
async function handleTextQuery(queryText) {
    if (!queryText.trim() || isProcessing) return;
    isProcessing = true;
    micBtn.disabled = true;
    sendBtn.disabled = true;

    addMessage('user', queryText);
    addProcessingMessage();

    try {
        const result = await callRelay({ queryText });
        removeProcessingMessage();

        if (result.success) {
            addMessage('assistant', result.responseText || 'No response');
            speak(result.responseText);
        } else {
            addMessage('error', result.error || result.errorMessage || 'Query failed');
        }
    } catch (err) {
        removeProcessingMessage();
        addMessage('error', err.message);
    } finally {
        isProcessing = false;
        micBtn.disabled = false;
        sendBtn.disabled = false;
    }
}

// ============================================================================
// HANDLE AUDIO QUERY
// ============================================================================
async function handleAudioQuery(audioBlob) {
    isProcessing = true;
    micBtn.disabled = true;
    sendBtn.disabled = true;

    addMessage('user', '🎤 [Voice message]');
    addProcessingMessage();

    try {
        // Convert blob to base64
        const arrayBuffer = await audioBlob.arrayBuffer();
        const bytes = new Uint8Array(arrayBuffer);
        let binary = '';
        for (let i = 0; i < bytes.length; i++) {
            binary += String.fromCharCode(bytes[i]);
        }
        const base64 = btoa(binary);

        const result = await callRelay({
            audioData: base64,
            mimeType: audioBlob.type
        });

        removeProcessingMessage();

        // Show what was transcribed
        if (result.queryText) {
            // Update the user message to show transcription
            const userMsgs = conversation.querySelectorAll('.msg.user');
            const lastUser = userMsgs[userMsgs.length - 1];
            if (lastUser) {
                lastUser.innerHTML = `<p>${escapeHtml(result.queryText)}</p><span class="timestamp">🎤 transcribed</span>`;
            }
        }

        if (result.success) {
            addMessage('assistant', result.responseText || 'No response');
            speak(result.responseText);
        } else {
            addMessage('error', result.error || result.errorMessage || 'Query failed');
        }
    } catch (err) {
        removeProcessingMessage();
        addMessage('error', err.message);
    } finally {
        isProcessing = false;
        micBtn.disabled = false;
        sendBtn.disabled = false;
    }
}

// ============================================================================
// AUDIO RECORDING (MediaRecorder — works on iOS Safari)
// ============================================================================
async function startRecording() {
    try {
        const stream = await navigator.mediaDevices.getUserMedia({
            audio: { channelCount: 1, sampleRate: 16000 }
        });

        // Pick best supported MIME type (iOS Safari = audio/mp4)
        let mimeType = 'audio/webm';
        if (!MediaRecorder.isTypeSupported(mimeType)) mimeType = 'audio/mp4';
        if (!MediaRecorder.isTypeSupported(mimeType)) mimeType = 'audio/ogg';
        if (!MediaRecorder.isTypeSupported(mimeType)) mimeType = '';

        mediaRecorder = new MediaRecorder(stream, mimeType ? { mimeType } : {});
        audioChunks = [];

        mediaRecorder.ondataavailable = (e) => {
            if (e.data.size > 0) audioChunks.push(e.data);
        };

        mediaRecorder.onstop = () => {
            stream.getTracks().forEach(t => t.stop());
            const blob = new Blob(audioChunks, { type: mediaRecorder.mimeType || 'audio/mp4' });
            recordingOverlay.classList.add('hidden');
            isRecording = false;
            if (blob.size > 0) {
                handleAudioQuery(blob);
            }
        };

        mediaRecorder.start();
        isRecording = true;
        recordingOverlay.classList.remove('hidden');

    } catch (err) {
        console.error('Mic error:', err);
        if (err.name === 'NotAllowedError') {
            addMessage('error', 'Microphone access denied. Please allow microphone in your browser settings.');
        } else {
            addMessage('error', 'Could not access microphone: ' + err.message);
        }
    }
}

function stopRecording() {
    if (mediaRecorder && mediaRecorder.state !== 'inactive') {
        mediaRecorder.stop();
    }
}

// ============================================================================
// EVENT LISTENERS
// ============================================================================
micBtn.addEventListener('click', () => {
    if (isProcessing) return;
    if (isRecording) {
        stopRecording();
    } else {
        startRecording();
    }
});

stopBtn.addEventListener('click', stopRecording);

sendBtn.addEventListener('click', () => {
    const q = textInput.value.trim();
    if (q) {
        handleTextQuery(q);
        textInput.value = '';
    }
});

textInput.addEventListener('keypress', (e) => {
    if (e.key === 'Enter') {
        const q = textInput.value.trim();
        if (q) {
            handleTextQuery(q);
            textInput.value = '';
        }
    }
});

settingsBtn.addEventListener('click', toggleSettings);
saveSettingsBtn.addEventListener('click', saveSettings);
cancelSettingsBtn.addEventListener('click', () => settingsPanel.classList.add('hidden'));

// ============================================================================
// INIT
// ============================================================================
document.addEventListener('DOMContentLoaded', () => {
    // Load voices for TTS
    if ('speechSynthesis' in window) {
        speechSynthesis.getVoices();
        speechSynthesis.onvoiceschanged = () => speechSynthesis.getVoices();
    }
    
    // Debug panel close button
    const closeDebugBtn = document.getElementById('closeDebugBtn') || document.getElementById('closedebugBtn');
    if (closeDebugBtn) {
        closeDebugBtn.addEventListener('click', toggleDebugPanel);
    }

    // Always show mic button, but disable if not supported
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
        micBtn.disabled = true;
        micBtn.title = 'Microphone not supported on this browser';
        addMessage('system', 'Microphone not supported on this browser. Use text input instead.');
    } else {
        micBtn.disabled = false;
        micBtn.title = 'Tap to record voice';
    }

    // Show settings if not configured
    if (!CONFIG.relayUrl) {
        setTimeout(() => {
            addMessage('system', 'Please configure your connection in Settings (gear icon).');
            toggleSettings();
        }, 300);
    }

    // Register service worker
    if ('serviceWorker' in navigator) {
        navigator.serviceWorker.register('sw.js').catch(() => {});
    }

    // Initial connectivity check
    checkConnectivity().catch(() => {});
});

// Global error handler for debugging
window.addEventListener('error', function(event) {
    addMessage('error', 'JS Error: ' + event.message + (event.filename ? ('\n' + event.filename + ':' + event.lineno) : ''));
});
window.addEventListener('unhandledrejection', function(event) {
    addMessage('error', 'Promise Error: ' + (event.reason && event.reason.message ? event.reason.message : event.reason));
});
