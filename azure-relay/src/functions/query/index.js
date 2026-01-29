/**
 * HTTP fallback for voice queries
 * Used when SignalR connection isn't available
 */

const fetch = require('node-fetch');

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
        const errorText = await response.text();
        throw new Error(`BC API error: ${response.status} - ${errorText}`);
    }
    
    return await response.json();
}

module.exports = async function (context, req) {
    try {
        const body = req.body;
        const queryText = body.queryText;
        
        if (!queryText) {
            context.res = {
                status: 400,
                jsonBody: { error: 'queryText is required' }
            };
            return;
        }
        
        // For now, return a placeholder
        // In production, you'd need proper BC authentication here
        context.res = {
            status: 200,
            jsonBody: { 
                status: 'Query endpoint ready',
                received: queryText
            }
        };
        
    } catch (error) {
        context.log(`❌ Query error: ${error.message}`);
        context.res = {
            status: 500,
            jsonBody: { error: error.message }
        };
    }
};
