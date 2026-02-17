/**
 * BC Voice Assistant - Progressive Web App
 * Standalone voice interface for Business Central
 * Supports Android & iOS with full microphone access
 */

// ============================================================================
// CONFIGURATION
// ============================================================================
const CONFIG = {
    // Azure AD / Entra ID settings
    clientId: localStorage.getItem('bc_clientId') || '',
    tenantId: localStorage.getItem('bc_tenantId') || '',
    bcEnvironment: localStorage.getItem('bc_environment') || '',
    relayUrl: localStorage.getItem('bc_relayUrl') || '',
    companyName: localStorage.getItem('bc_company') || 'CRONUS UK Ltd.',
    
    // BC API endpoint
    get apiEndpoint() {
        // Add company parameter to avoid "default company cannot be found" error
        const companyParam = this.companyName
            ? `?company=${encodeURIComponent(this.companyName)}`
            : '';
        return `${this.bcEnvironment}/api/hackathon/voiceAssistant/v1.0/voiceCommands${companyParam}`;
    },
    
    // Azure AD scopes - Business Central API access
    get scopes() {
        // IMPORTANT: Use generic BC API scope for multi-tenant authentication
        // Using environment-specific scope (with tenant ID) causes tenant mismatch errors
        // The generic scope works across all BC environments and tenants
        return ['https://api.businesscentral.dynamics.com/.default'];
    }
};

// ============================================================================
// SIGNALR REAL-TIME CONNECTION
// ============================================================================
let bcConnection = null;

function initializeRealTimeConnection() {
    if (!CONFIG.relayUrl) {
        console.log('Real-time relay not configured - using HTTP fallback');
        return;
    }
    
    bcConnection = new BCVoiceConnection({
        relayUrl: CONFIG.relayUrl,
        bcApiUrl: CONFIG.apiEndpoint,
        getAccessToken: acquireToken,
        onMessage: handleBCResponse,
        onStatusChange: handleConnectionStatusChange
    });
    
    // Connect in background
    bcConnection.connect().catch(err => {
        console.warn('Real-time connection failed, using HTTP:', err);
    });
}

function handleBCResponse(response) {
    if (response.success) {
        addMessage('assistant', response.responseText);
        speak(response.responseText);
    } else {
        const errorMsg = response.errorMessage || 'Unable to process your query';
        addMessage('assistant', `⚠️ ${errorMsg}`);
        speak(errorMsg);
    }
    updateStatus('idle', 'Tap microphone to start');
}

function handleConnectionStatusChange(status, message) {
    const statusMap = {
        'connecting': { dot: 'idle', text: 'Connecting...' },
        'connected': { dot: 'connected', text: '🔗 Real-time connected' },
        'reconnecting': { dot: 'idle', text: 'Reconnecting...' },
        'disconnected': { dot: 'error', text: 'Disconnected (using HTTP)' },
        'error': { dot: 'error', text: message || 'Connection error' }
    };
    
    const state = statusMap[status] || { dot: 'idle', text: message };
    updateConnectionStatus(state.dot, state.text);
}

// ============================================================================
// MOBILE DETECTION
// ============================================================================
function isMobileDevice() {
    return /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(navigator.userAgent) ||
           (navigator.maxTouchPoints && navigator.maxTouchPoints > 2);
}

// ============================================================================
// MSAL (Microsoft Authentication Library) Setup
// ============================================================================
let msalInstance = null;
let accessToken = null;

function initializeMsal() {
    if (!CONFIG.clientId || !CONFIG.tenantId) {
        console.log('MSAL not configured - waiting for settings');
        return;
    }
    
    const msalConfig = {
        auth: {
            clientId: CONFIG.clientId,
            // Use tenant-specific authority (app is single-tenant only)
            authority: `https://login.microsoftonline.com/${CONFIG.tenantId}`,
            redirectUri: window.location.origin  // e.g., http://localhost:3000
        },
        cache: {
            cacheLocation: 'localStorage',
            storeAuthStateInCookie: true
        }
    };
    
    msalInstance = new msal.PublicClientApplication(msalConfig);
    
    // Handle redirect response (critical for mobile)
    msalInstance.handleRedirectPromise()
        .then(response => {
            if (response) {
                accessToken = response.accessToken;
                updateConnectionStatus('connected', '✅ Signed in successfully!');
                // Close settings panel after successful mobile login
                setTimeout(() => {
                    const panel = document.getElementById('settingsPanel');
                    if (panel) panel.classList.add('hidden');
                }, 1500);
            }
        })
        .catch(error => {
            console.error('Redirect error:', error);
            updateConnectionStatus('error', 'Authentication failed');
        });
}

async function acquireToken() {
    if (!msalInstance) {
        throw new Error('Please configure BC connection settings first');
    }
    
    const accounts = msalInstance.getAllAccounts();
    
    if (accounts.length === 0) {
        // No user logged in - show error instead of auto-login
        // Auto-login causes nested popup issues
        console.log('No accounts found - user must sign in via Settings');
        throw new Error('Please sign in first. Click Settings (⚙️) → Save & Connect');
    }
    
    // Request access token with BC API scopes
    const request = {
        scopes: CONFIG.scopes,
        account: accounts[0]
    };
    
    try {
        const response = await msalInstance.acquireTokenSilent(request);
        // Use access token (not ID token) for BC API calls
        accessToken = response.accessToken;
        return accessToken;
    } catch (error) {
        console.error('Token acquisition error:', error);
        
        // Try interactive token acquisition
        if (isMobileDevice()) {
            // Mobile: Use redirect
            const tokenRequest = {
                ...request,
                redirectUri: window.location.origin
            };
            await msalInstance.acquireTokenRedirect(tokenRequest);
            // Will redirect - code after this won't execute
            throw new Error('Redirecting to sign in...');
        } else {
            // Desktop: Use popup
            try {
                const response = await msalInstance.acquireTokenPopup(request);
                accessToken = response.accessToken;
                return accessToken;
            } catch (popupError) {
                console.error('Popup token acquisition failed:', popupError);
                throw popupError;
            }
        }
    }
}

// ============================================================================
// SPEECH RECOGNITION
// ============================================================================
let recognition = null;
let isListening = false;

function initializeSpeechRecognition() {
    const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
    
    if (!SpeechRecognition) {
        console.warn('Speech Recognition not supported');
        document.getElementById('micButton').style.display = 'none';
        return;
    }
    
    recognition = new SpeechRecognition();
    recognition.continuous = false;
    recognition.interimResults = true;
    recognition.lang = 'en-US';
    
    recognition.onstart = () => {
        isListening = true;
        updateListeningState(true);
        updateStatus('listening', 'Listening...');
    };
    
    recognition.onend = () => {
        isListening = false;
        updateListeningState(false);
        updateStatus('idle', 'Tap microphone to start');
    };
    
    recognition.onresult = (event) => {
        const result = event.results[event.results.length - 1];
        const transcript = result[0].transcript;
        
        if (result.isFinal) {
            handleUserQuery(transcript);
        } else {
            updateStatus('listening', transcript);
        }
    };
    
    recognition.onerror = (event) => {
        console.error('Speech recognition error:', event.error);
        isListening = false;
        updateListeningState(false);
        
        if (event.error === 'not-allowed') {
            updateStatus('error', 'Microphone access denied. Please allow microphone access.');
            addMessage('system', '⚠️ Microphone access was denied. Please check your browser settings or use the text input below.');
        } else {
            updateStatus('error', `Speech error: ${event.error}`);
        }
    };
}

function toggleListening() {
    if (!recognition) {
        addMessage('system', '⚠️ Speech recognition not available on this device. Please use text input.');
        return;
    }
    
    if (isListening) {
        recognition.stop();
    } else {
        try {
            recognition.start();
        } catch (error) {
            console.error('Failed to start recognition:', error);
            updateStatus('error', 'Failed to start microphone');
        }
    }
}

// ============================================================================
// SPEECH SYNTHESIS (Text-to-Speech)
// ============================================================================
let pendingTTS = null;

function speak(text) {
    if (!('speechSynthesis' in window)) {
        DEBUG.log('❌ Speech synthesis not supported');
        console.warn('Speech synthesis not supported');
        return;
    }
    
    if (!text || text.trim().length === 0) {
        DEBUG.log('❌ Empty text provided');
        console.warn('speak() called with empty text');
        return;
    }
    
    DEBUG.log(`📢 speak() called: "${text.substring(0, 50)}..."`);
    console.log('speak() called with:', text.substring(0, 100));
    
    // iOS Safari: speechSynthesis.speak() hangs if not called from user gesture
    // Store text and show play button instead
    const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent);
    if (isIOS) {
        DEBUG.log('📱 iOS detected - storing TTS for manual playback');
        pendingTTS = text;
        showPlayButton();
        return;
    }
    
    // Non-iOS: play immediately
    playTTS(text);
}

function playTTS(text) {
    DEBUG.log(`🔊 Playing TTS: "${text.substring(0, 50)}..."`);
    
    // Cancel any ongoing speech
    speechSynthesis.cancel();
    
    // Pre-load voices
    speechSynthesis.getVoices();
    
    const utterance = new SpeechSynthesisUtterance(text);
    utterance.rate = 1.0;
    utterance.pitch = 1.0;
    utterance.volume = 1.0;
    
    // Try to use Samantha or Victoria on iOS
    const voices = speechSynthesis.getVoices();
    DEBUG.log(`🎤 Available voices: ${voices.length}`);
    console.log('Available voices:', voices.length);
    
    if (voices.length > 0) {
        const preferredVoice = voices.find(v => 
            v.name.includes('Samantha') || 
            v.name.includes('Victoria')
        );
        if (preferredVoice) {
            utterance.voice = preferredVoice;
            DEBUG.log(`✓ Using voice: ${preferredVoice.name}`);
            console.log('Using voice:', preferredVoice.name);
        } else {
            utterance.voice = voices[0];
            DEBUG.log(`⚠️ Voice not found, using: ${voices[0].name}`);
            console.log('Preferred voice not found, using:', voices[0].name);
        }
    } else {
        DEBUG.log('⚠️ No voices available - using system default');
    }
    
    utterance.onerror = (event) => {
        DEBUG.log(`❌ TTS Error: ${event.error}`);
        console.error('Speech synthesis error:', event.error);
        hidePlayButton();
    };
    
    utterance.onstart = () => {
        DEBUG.log('▶️ Speech started');
        console.log('Speech started');
        updateStatus('speaking', 'Speaking...');
        hidePlayButton();
    };
    
    utterance.onend = () => {
        DEBUG.log('⏸️ Speech ended');
        console.log('Speech ended');
        updateStatus('idle', 'Tap microphone to start');
        pendingTTS = null;
    };
    
    utterance.onpause = () => DEBUG.log('⏸️ Speech paused');
    utterance.onresume = () => DEBUG.log('▶️ Speech resumed');
    
    DEBUG.log('→ Calling speechSynthesis.speak()');
    console.log('Calling speechSynthesis.speak()');
    speechSynthesis.speak(utterance);
}

function showPlayButton() {
    let playBtn = document.getElementById('playTTSBtn');
    if (!playBtn) {
        playBtn = document.createElement('button');
        playBtn.id = 'playTTSBtn';
        playBtn.innerHTML = '🔊 Tap to play response';
        playBtn.style.cssText = 'position:fixed;bottom:90px;left:50%;transform:translateX(-50%);background:#0078d4;color:#fff;border:none;padding:12px 24px;border-radius:24px;font-size:16px;font-weight:bold;box-shadow:0 4px 12px rgba(0,0,0,0.3);z-index:1000;cursor:pointer;animation:pulse 1.5s infinite;';
        playBtn.onclick = () => {
            if (pendingTTS) {
                playTTS(pendingTTS);
            }
        };
        document.body.appendChild(playBtn);
        
        // Add pulse animation
        if (!document.getElementById('playBtnStyle')) {
            const style = document.createElement('style');
            style.id = 'playBtnStyle';
            style.textContent = '@keyframes pulse { 0%, 100% { transform: translateX(-50%) scale(1); } 50% { transform: translateX(-50%) scale(1.05); } }';
            document.head.appendChild(style);
        }
    }
    playBtn.style.display = 'block';
}

function hidePlayButton() {
    const playBtn = document.getElementById('playTTSBtn');
    if (playBtn) {
        playBtn.style.display = 'none';
    }
}

// ============================================================================
// BC API COMMUNICATION
// ============================================================================
async function sendQueryToBC(queryText) {
    updateStatus('processing', 'Processing query...');
    
    try {
        const token = await acquireToken();
        
        const response = await fetch(CONFIG.apiEndpoint, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${token}`
            },
            body: JSON.stringify({
                queryText: queryText
            })
        });
        
        if (!response.ok) {
            const errorText = await response.text();
            throw new Error(`BC API error: ${response.status} - ${errorText}`);
        }
        
        const data = await response.json();
        return {
            success: data.success,
            responseText: data.responseText || 'No response received',
            structuredData: data.structuredData,
            errorMessage: data.errorMessage
        };
    } catch (error) {
        console.error('BC API error:', error);
        throw error;
    }
}

// ============================================================================
// QUERY HANDLING
// ============================================================================
async function handleUserQuery(queryText) {
    addMessage('user', queryText);
    updateStatus('processing', 'Processing query...');
    
    try {
        // Use real-time connection if available, otherwise direct HTTP
        if (bcConnection && bcConnection.isConnected) {
            // SignalR - response comes via handleBCResponse callback
            await bcConnection.sendQuery(queryText);
            // Status update handled by callback
        } else {
            // Direct HTTP to BC
            const result = await sendQueryToBC(queryText);
            handleBCResponse(result);
        }
    } catch (error) {
        const errorMsg = error.message.includes('configure') 
            ? 'Please configure BC connection settings first (tap ⚙️)'
            : 'Sorry, I encountered an error connecting to Business Central.';
        addMessage('assistant', `❌ ${errorMsg}`);
        speak(errorMsg);
        updateStatus('error', 'Error processing query');
    }
}

// ============================================================================
// UI HELPERS
// ============================================================================
function addMessage(type, text) {
    const conversation = document.getElementById('conversation');
    const messageDiv = document.createElement('div');
    messageDiv.className = `message ${type}`;
    // Use textContent instead of innerHTML to prevent XSS
    const p = document.createElement('p');
    p.textContent = text;
    messageDiv.appendChild(p);
    conversation.appendChild(messageDiv);
    conversation.scrollTop = conversation.scrollHeight;
}

function updateStatus(state, text) {
    const statusEl = document.getElementById('status');
    const statusText = statusEl.querySelector('.status-text');
    const statusDot = statusEl.querySelector('.status-dot');
    
    statusText.textContent = text;
    statusDot.className = `status-dot ${state}`;
}

function updateListeningState(listening) {
    const micButton = document.getElementById('micButton');
    const visualizer = document.getElementById('visualizer');
    
    if (listening) {
        micButton.classList.add('listening');
        visualizer.classList.remove('hidden');
    } else {
        micButton.classList.remove('listening');
        visualizer.classList.add('hidden');
    }
}

function updateConnectionStatus(state, message) {
    const statusEl = document.getElementById('connectionStatus');
    statusEl.className = `connection-status ${state}`;
    statusEl.textContent = message;
}

// ============================================================================
// SETTINGS MANAGEMENT
// ============================================================================
function loadSettings() {
    document.getElementById('bcEnvironment').value = CONFIG.bcEnvironment;
    document.getElementById('companyName').value = CONFIG.companyName;
    document.getElementById('clientId').value = CONFIG.clientId;
    document.getElementById('tenantId').value = CONFIG.tenantId;
    document.getElementById('relayUrl').value = CONFIG.relayUrl;
}

function saveSettings() {
    const bcEnvironment = document.getElementById('bcEnvironment').value.trim();
    const companyName = document.getElementById('companyName').value.trim();
    const clientId = document.getElementById('clientId').value.trim();
    const tenantId = document.getElementById('tenantId').value.trim();
    const relayUrl = document.getElementById('relayUrl').value.trim();
    
    // Remove trailing slashes
    const cleanBcUrl = bcEnvironment.replace(/\/$/, '');
    const cleanRelayUrl = relayUrl.replace(/\/$/, '');
    
    localStorage.setItem('bc_environment', cleanBcUrl);
    localStorage.setItem('bc_company', companyName);
    localStorage.setItem('bc_clientId', clientId);
    localStorage.setItem('bc_tenantId', tenantId);
    localStorage.setItem('bc_relayUrl', cleanRelayUrl);
    
    CONFIG.bcEnvironment = cleanBcUrl;
    CONFIG.companyName = companyName;
    CONFIG.clientId = clientId;
    CONFIG.tenantId = tenantId;
    CONFIG.relayUrl = cleanRelayUrl;
    
    // Clear MSAL cache by clearing all auth-related localStorage
    // This forces fresh authentication with new settings
    if (msalInstance) {
        const keys = Object.keys(localStorage);
        keys.forEach(key => {
            if (key.startsWith('msal.')) {
                localStorage.removeItem(key);
            }
        });
    }
    
    // Reinitialize MSAL
    initializeMsal();
    
    // Initialize real-time connection if relay configured
    if (cleanRelayUrl) {
        initializeRealTimeConnection();
    }
    
    // Try to connect (use redirect for mobile, popup for desktop)
    if (isMobileDevice()) {
        // Mobile: Use redirect flow
        updateConnectionStatus('connecting', '🔄 Redirecting to sign in...');
        const loginRequest = {
            scopes: CONFIG.scopes,
            redirectUri: window.location.origin
        };
        msalInstance.loginRedirect(loginRequest).catch(error => {
            console.error('Mobile login redirect failed:', error);
            updateConnectionStatus('error', 'Sign-in failed: ' + error.message);
        });
    } else {
        // Desktop: Use popup flow
        acquireToken()
            .then(() => {
                updateConnectionStatus('connected', 'Successfully connected!');
                setTimeout(() => {
                    document.getElementById('settingsPanel').classList.add('hidden');
                }, 1500);
            })
            .catch(error => {
                updateConnectionStatus('error', 'Connection failed: ' + error.message);
            });
    }
}

function toggleSettings() {
    const panel = document.getElementById('settingsPanel');
    panel.classList.toggle('hidden');
    if (!panel.classList.contains('hidden')) {
        loadSettings();
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
// TEXT INPUT HANDLING
// ============================================================================
function handleTextSubmit() {
    const input = document.getElementById('textInput');
    const query = input.value.trim();
    
    if (query) {
        handleUserQuery(query);
        input.value = '';
    }
}

// ============================================================================
// PWA INSTALL HANDLING
// ============================================================================
let deferredInstallPrompt = null;

function initializePWAInstall() {
    window.addEventListener('beforeinstallprompt', (e) => {
        // Prevent the mini-infobar from appearing on mobile
        e.preventDefault();
        deferredInstallPrompt = e;
        
        // Show install button
        const installBtn = document.getElementById('installBtn');
        if (installBtn) {
            installBtn.classList.remove('hidden');
        }
    });
    
    window.addEventListener('appinstalled', () => {
        console.log('PWA was installed');
        deferredInstallPrompt = null;
        const installBtn = document.getElementById('installBtn');
        if (installBtn) {
            installBtn.classList.add('hidden');
        }
    });
}

async function handleInstallClick() {
    if (!deferredInstallPrompt) {
        return;
    }
    
    // Show the install prompt
    deferredInstallPrompt.prompt();
    
    // Wait for the user to respond to the prompt
    const { outcome } = await deferredInstallPrompt.userChoice;
    console.log(`User response to install prompt: ${outcome}`);
    
    // Clear the deferred prompt
    deferredInstallPrompt = null;
    
    // Hide the install button
    const installBtn = document.getElementById('installBtn');
    if (installBtn) {
        installBtn.classList.add('hidden');
    }
}

// ============================================================================
// MOBILE MENU HANDLING
// ============================================================================
function toggleMobileMenu() {
    const mobileNav = document.getElementById('mobileNav');
    if (mobileNav) {
        mobileNav.classList.toggle('hidden');
    }
}

function handleNavAction(action) {
    const mobileNav = document.getElementById('mobileNav');
    if (mobileNav) {
        mobileNav.classList.add('hidden');
    }
    
    switch(action) {
        case 'settings':
            toggleSettings();
            break;
        case 'help':
            addMessage('system', '🎤 Just tap the microphone and ask about your Business Central data! Try: "Show me top customers" or "What are my sales today?"');
            break;
        case 'about':
            addMessage('system', '📱 BC Voice Assistant v2.2 - A voice-powered interface for Microsoft Dynamics 365 Business Central.');
            break;
        case 'debug':
            toggleDebugPanel();
            break;
    }
}

// ============================================================================
// LOADING STATE MANAGEMENT
// ============================================================================
function hideLoadingIndicator() {
    const loadingIndicator = document.getElementById('loadingIndicator');
    if (loadingIndicator) {
        loadingIndicator.style.opacity = '0';
        setTimeout(() => {
            loadingIndicator.style.display = 'none';
        }, 300);
    }
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

// ============================================================================
// INITIALIZATION
// ============================================================================
document.addEventListener('DOMContentLoaded', () => {
    // Initialize components
    initializeSpeechRecognition();
    initializeMsal();
    initializeRealTimeConnection();
    initializePWAInstall();
    
    // Event listeners
    document.getElementById('micButton').addEventListener('click', toggleListening);
    document.getElementById('settingsBtn').addEventListener('click', toggleSettings);
    document.getElementById('saveSettings').addEventListener('click', saveSettings);
    document.getElementById('closeSettings').addEventListener('click', () => {
        document.getElementById('settingsPanel').classList.add('hidden');
    });
    document.getElementById('sendTextBtn').addEventListener('click', handleTextSubmit);
    document.getElementById('textInput').addEventListener('keypress', (e) => {
        if (e.key === 'Enter') handleTextSubmit();
    });
    
    // PWA Install button
    const installBtn = document.getElementById('installBtn');
    if (installBtn) {
        installBtn.addEventListener('click', handleInstallClick);
    }
    
    // Mobile menu
    const mobileMenuBtn = document.getElementById('mobileMenuBtn');
    if (mobileMenuBtn) {
        mobileMenuBtn.addEventListener('click', toggleMobileMenu);
    }
    
    const navClose = document.querySelector('.nav-close');
    if (navClose) {
        navClose.addEventListener('click', toggleMobileMenu);
    }
    
    // Nav menu actions
    document.querySelectorAll('.nav-menu a').forEach(link => {
        link.addEventListener('click', (e) => {
            e.preventDefault();
            const action = e.currentTarget.dataset.action;
            if (action) {
                handleNavAction(action);
            }
        });
    });
    
    // Load voices for speech synthesis
    if ('speechSynthesis' in window) {
        speechSynthesis.getVoices();
        speechSynthesis.onvoiceschanged = () => speechSynthesis.getVoices();
    }
    
    // Debug panel close button
    const closeDebugBtn = document.getElementById('closeDebugBtn') || document.getElementById('closedebugBtn');
    if (closeDebugBtn) {
        closeDebugBtn.addEventListener('click', toggleDebugPanel);
    }
    
    // Show debug menu if ?debug=true in URL or localStorage debug mode enabled
    const urlParams = new URLSearchParams(window.location.search);
    const debugParam = urlParams.get('debug');
    const debugMode = debugParam === 'true' || localStorage.getItem('debugMode') === 'true';
    
    if (debugParam === 'true') {
        localStorage.setItem('debugMode', 'true');
    } else if (debugParam === 'false') {
        localStorage.removeItem('debugMode');
    }
    
    const debugMenuItem = document.getElementById('debugMenuItem');
    if (debugMenuItem) {
        debugMenuItem.style.display = debugMode ? 'block' : 'none';
    }
    
    // Show settings if not configured
    if (!CONFIG.bcEnvironment || !CONFIG.clientId) {
        setTimeout(() => {
            addMessage('system', '👋 Welcome! Please configure your BC connection settings to get started.');
            toggleSettings();
        }, 500);
    }
    
    // Register service worker for PWA
    if ('serviceWorker' in navigator) {
        navigator.serviceWorker.register('sw.js')
            .then(reg => console.log('Service Worker registered'))
            .catch(err => console.log('Service Worker registration failed:', err));
    }
    
    // Hide loading indicator when everything is ready
    window.addEventListener('load', () => {
        setTimeout(hideLoadingIndicator, 500);
    });
});
