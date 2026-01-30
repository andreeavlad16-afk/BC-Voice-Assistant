/**
 * Voice Query Handler
 * Receives voice queries via SignalR, calls BC API, returns response
 * Azure Functions v4 with function.json declarative bindings
 */

const fetch = require('node-fetch');

/**
 * Call BC Voice API with function key authentication
 */
async function callBCVoiceAPI(queryText, functionKey) {
    const apiUrl = `${process.env.BC_ENVIRONMENT_URL}/api/hackathon/voiceAssistant/v1.0/voiceCommands?code=${functionKey}`;
    
    const response = await fetch(apiUrl, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json'
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
        
        // Try to call BC API if configured
        let responseData = { query: queryText };
        if (process.env.BC_ENVIRONMENT_URL && process.env.BC_FUNCTION_KEY) {
            try {
                responseData = await callBCVoiceAPI(queryText, process.env.BC_FUNCTION_KEY);
            } catch (bcError) {
                context.log(`⚠️ BC API call failed: ${bcError.message}`);
                // Fall back to echo response
                responseData = { echo: queryText, error: bcError.message };
            }
        }
        
        context.bindings.signalRMessages = [{
            connectionId: connectionId,
            target: 'queryResponse',
            arguments: [{
                requestId,
                success: true,
                responseText: responseData.responseText || `Received: ${queryText}`,
                structuredData: responseData
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
