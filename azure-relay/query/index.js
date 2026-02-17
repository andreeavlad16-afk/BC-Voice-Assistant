/**
 * HTTP fallback for voice queries
 * Used when SignalR connection isn't available
 */

const fetch = require('node-fetch');

function buildBcVoiceApiUrl(functionKey) {
    const baseUrl = process.env.BC_ENVIRONMENT_URL;
    const companyId = process.env.BC_COMPANY_ID;
    const companyName = process.env.BC_COMPANY_NAME || process.env.BC_COMPANY;

    if (companyId) {
        return `${baseUrl}/api/hackathon/voiceAssistant/v1.0/companies(${companyId})/voiceCommands?code=${functionKey}`;
    }

    if (companyName) {
        const encodedCompany = encodeURIComponent(companyName);
        return `${baseUrl}/api/hackathon/voiceAssistant/v1.0/voiceCommands?company=${encodedCompany}&code=${functionKey}`;
    }

    return `${baseUrl}/api/hackathon/voiceAssistant/v1.0/voiceCommands?code=${functionKey}`;
}

async function callBCVoiceAPI(queryText, functionKey) {
    // Use BC Function App endpoint with function key authentication
    // This is service-to-service, not user authentication
    const apiUrl = buildBcVoiceApiUrl(functionKey);
    
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
        
        // Try to call BC API if endpoint is configured
        if (process.env.BC_ENVIRONMENT_URL && process.env.BC_FUNCTION_KEY) {
            try {
                const result = await callBCVoiceAPI(queryText, process.env.BC_FUNCTION_KEY);
                context.res = {
                    status: 200,
                    jsonBody: result
                };
                return;
            } catch (bcError) {
                context.log(`⚠️ BC API call failed: ${bcError.message}`);
                // Fall through to simple response
            }
        }

        // Fallback: return simple response
        context.res = {
            status: 200,
            jsonBody: { 
                status: 'Query received',
                query: queryText,
                message: 'BC API not configured. Configure BC_ENVIRONMENT_URL and BC_FUNCTION_KEY.'
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
