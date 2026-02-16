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
    
    // BC API endpoint
    get apiEndpoint() {
        return `${this.bcEnvironment}/api/hackathon/voiceAssistant/v1.0/voiceCommands`;
    },
    
    // Azure AD scopes - Business Central API access
    get scopes() {
        // Request BC API scope for authentication
        // Format: https://api.businesscentral.dynamics.com/user_impersonation
        // OR use the BC environment URL directly
        if (this.bcEnvironment) {
            // Use environment-specific scope (preferred for BC SaaS)
            return [`${this.bcEnvironment}/.default`];
        }
        // Fallback to generic BC API scope
        return ['https://api.businesscentral.dynamics.com/user_impersonation'];
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
            authority: `https://login.microsoftonline.com/${CONFIG.tenantId}`,
            redirectUri: window.location.origin  // e.g., http://localhost:3000
        },
        cache: {
            cacheLocation: 'localStorage',
            storeAuthStateInCookie: true
        }
    };
    
    msalInstance = new msal.PublicClientApplication(msalConfig);
    
    // Handle redirect response
    msalInstance.handleRedirectPromise()
        .then(response => {
            if (response) {
                accessToken = response.accessToken;
                updateConnectionStatus('connected', 'Connected to Business Central');
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
        throw new Error('No authenticated user found. Please sign in again.');
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
function speak(text) {
    if (!('speechSynthesis' in window)) {
        console.warn('Speech synthesis not supported');
        return;
    }
    
    // Cancel any ongoing speech
    speechSynthesis.cancel();
    
    const utterance = new SpeechSynthesisUtterance(text);
    utterance.rate = 1.0;
    utterance.pitch = 1.0;
    utterance.volume = 1.0;
    
    // Try to use a good voice
    const voices = speechSynthesis.getVoices();
    const preferredVoice = voices.find(v => 
        v.name.includes('Google') || 
        v.name.includes('Samantha') || 
        v.name.includes('Microsoft')
    );
    if (preferredVoice) {
        utterance.voice = preferredVoice;
    }
    
    utterance.onstart = () => updateStatus('speaking', 'Speaking...');
    utterance.onend = () => updateStatus('idle', 'Tap microphone to start');
    
    speechSynthesis.speak(utterance);
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
    messageDiv.innerHTML = `<p>${text}</p>`;
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
    document.getElementById('clientId').value = CONFIG.clientId;
    document.getElementById('tenantId').value = CONFIG.tenantId;
    document.getElementById('relayUrl').value = CONFIG.relayUrl;
}

function saveSettings() {
    const bcEnvironment = document.getElementById('bcEnvironment').value.trim();
    const clientId = document.getElementById('clientId').value.trim();
    const tenantId = document.getElementById('tenantId').value.trim();
    const relayUrl = document.getElementById('relayUrl').value.trim();
    
    // Remove trailing slashes
    const cleanBcUrl = bcEnvironment.replace(/\/$/, '');
    const cleanRelayUrl = relayUrl.replace(/\/$/, '');
    
    localStorage.setItem('bc_environment', cleanBcUrl);
    localStorage.setItem('bc_clientId', clientId);
    localStorage.setItem('bc_tenantId', tenantId);
    localStorage.setItem('bc_relayUrl', cleanRelayUrl);
    
    CONFIG.bcEnvironment = cleanBcUrl;
    CONFIG.clientId = clientId;
    CONFIG.tenantId = tenantId;
    CONFIG.relayUrl = cleanRelayUrl;
    
    // Clear any existing MSAL cache to avoid stale tokens
    if (msalInstance) {
        const accounts = msalInstance.getAllAccounts();
        accounts.forEach(account => {
            msalInstance.getTokenCache().removeAccount(account);
        });
    }
    
    // Reinitialize MSAL
    initializeMsal();
    
    // Initialize real-time connection if relay configured
    if (cleanRelayUrl) {
        initializeRealTimeConnection();
    }
    
    // Try to connect
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

function toggleSettings() {
    const panel = document.getElementById('settingsPanel');
    panel.classList.toggle('hidden');
    if (!panel.classList.contains('hidden')) {
        loadSettings();
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
