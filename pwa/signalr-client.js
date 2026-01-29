/**
 * BC Voice Assistant - SignalR Real-Time Client
 * Provides persistent WebSocket connection with automatic reconnection
 */

class BCVoiceConnection {
    constructor(options = {}) {
        this.signalRUrl = options.signalRUrl || '';
        this.httpFallbackUrl = options.httpFallbackUrl || '';
        this.connection = null;
        this.isConnected = false;
        this.pendingRequests = new Map();
        this.reconnectAttempts = 0;
        this.maxReconnectAttempts = 5;
        this.reconnectDelay = 1000;
        
        // Callbacks
        this.onStatusChange = options.onStatusChange || (() => {});
        this.onResponse = options.onResponse || (() => {});
        this.onError = options.onError || (() => {});
    }
    
    /**
     * Initialize SignalR connection
     */
    async connect() {
        if (!this.signalRUrl) {
            console.log('No SignalR URL configured, using HTTP fallback');
            return false;
        }
        
        try {
            // Get SignalR connection info
            const negotiateResponse = await fetch(`${this.signalRUrl}/api/negotiate`, {
                method: 'POST'
            });
            
            if (!negotiateResponse.ok) {
                throw new Error('Failed to negotiate SignalR connection');
            }
            
            const connectionInfo = await negotiateResponse.json();
            
            // Create SignalR connection
            this.connection = new signalR.HubConnectionBuilder()
                .withUrl(connectionInfo.url, {
                    accessTokenFactory: () => connectionInfo.accessToken
                })
                .withAutomaticReconnect({
                    nextRetryDelayInMilliseconds: (retryContext) => {
                        if (retryContext.previousRetryCount >= this.maxReconnectAttempts) {
                            return null; // Stop retrying
                        }
                        return Math.min(1000 * Math.pow(2, retryContext.previousRetryCount), 30000);
                    }
                })
                .configureLogging(signalR.LogLevel.Information)
                .build();
            
            // Set up event handlers
            this.setupEventHandlers();
            
            // Start connection
            await this.connection.start();
            this.isConnected = true;
            this.reconnectAttempts = 0;
            this.onStatusChange('connected', 'Real-time connection established');
            
            console.log('SignalR connected');
            return true;
            
        } catch (error) {
            console.error('SignalR connection failed:', error);
            this.isConnected = false;
            this.onStatusChange('fallback', 'Using standard connection');
            return false;
        }
    }
    
    /**
     * Set up SignalR event handlers
     */
    setupEventHandlers() {
        // Query processing status
        this.connection.on('queryStatus', (data) => {
            console.log('Query status:', data);
            this.onStatusChange('processing', data.message);
        });
        
        // Query response
        this.connection.on('queryResponse', (data) => {
            console.log('Query response:', data);
            const pending = this.pendingRequests.get(data.requestId);
            if (pending) {
                pending.resolve(data);
                this.pendingRequests.delete(data.requestId);
            }
            this.onResponse(data);
        });
        
        // Query error
        this.connection.on('queryError', (data) => {
            console.error('Query error:', data);
            const pending = this.pendingRequests.get(data.requestId);
            if (pending) {
                pending.reject(new Error(data.error));
                this.pendingRequests.delete(data.requestId);
            }
            this.onError(data);
        });
        
        // Connection state changes
        this.connection.onreconnecting((error) => {
            this.isConnected = false;
            this.onStatusChange('reconnecting', 'Reconnecting...');
            console.log('SignalR reconnecting:', error);
        });
        
        this.connection.onreconnected((connectionId) => {
            this.isConnected = true;
            this.onStatusChange('connected', 'Reconnected');
            console.log('SignalR reconnected:', connectionId);
        });
        
        this.connection.onclose((error) => {
            this.isConnected = false;
            this.onStatusChange('disconnected', 'Connection closed');
            console.log('SignalR closed:', error);
        });
    }
    
    /**
     * Send voice query
     */
    async sendQuery(queryText) {
        const requestId = `${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
        
        // Try SignalR first if connected
        if (this.isConnected && this.connection) {
            return this.sendViaSignalR(queryText, requestId);
        }
        
        // Fall back to HTTP
        return this.sendViaHTTP(queryText);
    }
    
    /**
     * Send query via SignalR (real-time)
     */
    async sendViaSignalR(queryText, requestId) {
        return new Promise((resolve, reject) => {
            // Store pending request
            this.pendingRequests.set(requestId, { resolve, reject });
            
            // Set timeout
            const timeout = setTimeout(() => {
                this.pendingRequests.delete(requestId);
                reject(new Error('Query timeout'));
            }, 30000);
            
            // Send via SignalR
            this.connection.invoke('voiceQuery', queryText, requestId)
                .catch((error) => {
                    clearTimeout(timeout);
                    this.pendingRequests.delete(requestId);
                    // Fall back to HTTP on SignalR error
                    console.warn('SignalR invoke failed, falling back to HTTP:', error);
                    this.sendViaHTTP(queryText).then(resolve).catch(reject);
                });
        });
    }
    
    /**
     * Send query via HTTP (fallback)
     */
    async sendViaHTTP(queryText) {
        const url = this.httpFallbackUrl || `${this.signalRUrl}/api/query`;
        
        const response = await fetch(url, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({ queryText })
        });
        
        if (!response.ok) {
            const errorText = await response.text();
            throw new Error(`HTTP error: ${response.status} - ${errorText}`);
        }
        
        return await response.json();
    }
    
    /**
     * Disconnect
     */
    async disconnect() {
        if (this.connection) {
            await this.connection.stop();
            this.connection = null;
        }
        this.isConnected = false;
    }
}

// Export for use in app.js
window.BCVoiceConnection = BCVoiceConnection;
