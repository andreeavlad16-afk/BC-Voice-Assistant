/**
 * Voice Query Handler
 * Receives voice queries via SignalR, calls BC API, returns response
 * Azure Functions v4 with function.json declarative bindings
 */

const fetch = require('node-fetch');

/**
 * Call BC Voice API
 */
async function callBCVoiceAPI(queryText, accessToken) {
    const apiUrl = `${process.env.BC_ENVIRONMENT_URL}/api/hackathon/voiceAssistant/v1.0/voiceCommands`;
    
    const response = await fetch(apiUrl, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${accessToken}`
        },
        body: JSON.stringify({
            queryText: queryText
        })
    });
    
    if (!response.ok) {
        throw new Error(`BC API error: ${response.status}`);
    }
    
    return await response.json();
}

module.exports = async function (context, invocationContext) {
    try {
        // Parse SignalR invocation
        const { connectionId, arguments: args } = invocationContext;
        const queryText = args[0];
        const requestId = args[1] || Date.now().toString();
        
        context.log(`Processing query from ${connectionId}: ${queryText}`);
        
        // Send "processing" status immediately via SignalR output binding
        context.bindings.signalRMessages = [{
            connectionId: connectionId,
            target: 'queryStatus',
            arguments: [{ 
                requestId,
                status: 'processing',
                message: 'Processing your query...'
            }]
        }];
        
        // In production, you'd get BC access token here and call BC API
        // For now, send a simple response
        
        context.bindings.signalRMessages = [{
            connectionId: connectionId,
            target: 'queryResponse',
            arguments: [{
                requestId,
                success: true,
                responseText: `Echo: ${queryText}`,
                structuredData: { query: queryText }
            }]
        }];
        
    } catch (error) {
        context.log(`❌ Voice query error: ${error.message}`);
        
        // Send error back to client via SignalR
        context.bindings.signalRMessages = [{
            connectionId: invocationContext.connectionId,
            target: 'queryError',
            arguments: [{
                requestId: invocationContext.arguments[1] || Date.now().toString(),
                error: error.message
            }]
        }];
    }
};
