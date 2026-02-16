/**
 * Voice Relay Function
 * 
 * Complete pipeline: Audio/Text → Whisper Transcription → BC Voice Command API → Response
 * 
 * Accepts two modes:
 *   1. Audio mode: { audioData: "base64...", mimeType: "audio/webm" }
 *   2. Text mode:  { queryText: "how many customers?" }
 * 
 * Returns: { success, responseText, queryText, structuredData }
 */

const fetch = require('node-fetch');
const FormData = require('form-data');

// ============================================================================
// OAuth Token Cache
// ============================================================================
let cachedToken = null;
let tokenExpiry = 0;

async function getBCAccessToken(context) {
    // Return cached token if still valid (with 60s buffer)
    if (cachedToken && Date.now() < tokenExpiry - 60000) {
        return cachedToken;
    }

    const tenantId = process.env.BC_TENANT_ID;
    const clientId = process.env.BC_CLIENT_ID;
    const clientSecret = process.env.BC_CLIENT_SECRET;

    if (!tenantId || !clientId || !clientSecret) {
        throw new Error('BC OAuth credentials not configured (BC_TENANT_ID, BC_CLIENT_ID, BC_CLIENT_SECRET)');
    }

    const tokenUrl = `https://login.microsoftonline.com/${tenantId}/oauth2/v2.0/token`;
    const params = new URLSearchParams({
        grant_type: 'client_credentials',
        client_id: clientId,
        client_secret: clientSecret,
        scope: 'https://api.businesscentral.dynamics.com/.default'
    });

    const response = await fetch(tokenUrl, {
        method: 'POST',
        body: params,
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' }
    });

    if (!response.ok) {
        const errorText = await response.text();
        context.log(`OAuth token error: ${errorText}`);
        throw new Error(`OAuth token acquisition failed: ${response.status}`);
    }

    const tokenData = await response.json();
    cachedToken = tokenData.access_token;
    tokenExpiry = Date.now() + (tokenData.expires_in * 1000);

    context.log('✅ BC OAuth token acquired');
    return cachedToken;
}

// ============================================================================
// Whisper Transcription
// ============================================================================
async function transcribeAudio(audioData, mimeType, context) {
    // Determine file extension
    let extension = 'm4a';
    if (mimeType) {
        if (mimeType.includes('wav')) extension = 'wav';
        else if (mimeType.includes('webm')) extension = 'webm';
        else if (mimeType.includes('mp3')) extension = 'mp3';
        else if (mimeType.includes('ogg')) extension = 'ogg';
        else if (mimeType.includes('mp4')) extension = 'm4a';
    }

    const audioBuffer = Buffer.from(audioData, 'base64');
    context.log(`Audio: ${audioBuffer.length} bytes, type: ${mimeType}, ext: ${extension}`);

    const formData = new FormData();
    formData.append('file', audioBuffer, {
        filename: `audio.${extension}`,
        contentType: mimeType || 'audio/mp4'
    });
    formData.append('model', 'whisper-1');
    formData.append('language', 'en');

    // Use Azure OpenAI Whisper
    const endpoint = process.env.AZURE_OPENAI_ENDPOINT;
    const apiKey = process.env.AZURE_OPENAI_KEY;
    const whisperDeployment = process.env.AZURE_OPENAI_WHISPER_DEPLOYMENT || 'whisper';

    if (!endpoint || !apiKey) {
        throw new Error('Azure OpenAI not configured (AZURE_OPENAI_ENDPOINT, AZURE_OPENAI_KEY)');
    }

    const apiUrl = `${endpoint}openai/deployments/${whisperDeployment}/audio/transcriptions?api-version=2024-10-21`;
    
    const response = await fetch(apiUrl, {
        method: 'POST',
        body: formData,
        headers: {
            ...formData.getHeaders(),
            'api-key': apiKey
        }
    });

    if (!response.ok) {
        const errorText = await response.text();
        context.log(`Whisper error: ${errorText}`);
        throw new Error(`Transcription failed: ${response.status}`);
    }

    const result = await response.json();
    context.log(`✅ Transcribed: "${result.text}"`);
    return result.text;
}

// ============================================================================
// BC Voice Command API Call
// ============================================================================
async function callBCVoiceAPI(queryText, context) {
    const token = await getBCAccessToken(context);

    const bcEnvironmentUrl = process.env.BC_ENVIRONMENT_URL;
    const bcCompanyId = process.env.BC_COMPANY_ID;

    if (!bcEnvironmentUrl) {
        throw new Error('BC_ENVIRONMENT_URL not configured');
    }

    // Build URL with or without company ID
    let apiUrl;
    if (bcCompanyId) {
        apiUrl = `${bcEnvironmentUrl}/api/hackathon/voiceAssistant/v1.0/companies(${bcCompanyId})/voiceCommands`;
    } else {
        apiUrl = `${bcEnvironmentUrl}/api/hackathon/voiceAssistant/v1.0/voiceCommands`;
    }

    context.log(`Calling BC API: ${apiUrl}`);

    const response = await fetch(apiUrl, {
        method: 'POST',
        headers: {
            'Authorization': `Bearer ${token}`,
            'Content-Type': 'application/json'
        },
        body: JSON.stringify({ queryText })
    });

    if (!response.ok) {
        const errorText = await response.text();
        context.log(`BC API error: ${response.status} - ${errorText}`);
        throw new Error(`BC API error: ${response.status}`);
    }

    return await response.json();
}

// ============================================================================
// Main Handler
// ============================================================================
module.exports = async function (context, req) {
    // CORS headers
    const corsHeaders = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, x-functions-key'
    };

    // Handle CORS preflight
    if (req.method === 'OPTIONS') {
        context.res = {
            status: 204,
            headers: corsHeaders
        };
        return;
    }

    try {
        const body = req.body || {};
        let queryText = body.queryText;

        // Step 1: Transcribe audio if provided
        if (body.audioData) {
            context.log('Mode: Audio → Transcribe → BC');
            queryText = await transcribeAudio(body.audioData, body.mimeType, context);
        } else if (!queryText) {
            context.res = {
                status: 400,
                headers: corsHeaders,
                body: { success: false, error: 'Provide audioData (base64) or queryText' }
            };
            return;
        } else {
            context.log(`Mode: Text → BC ("${queryText}")`);
        }

        // Step 2: Call BC Voice Command API
        const bcResult = await callBCVoiceAPI(queryText, context);

        // Step 3: Return response
        context.res = {
            status: 200,
            headers: corsHeaders,
            body: {
                success: bcResult.success !== undefined ? bcResult.success : true,
                queryText: queryText,
                responseText: bcResult.responseText || 'No response from BC',
                structuredData: bcResult.structuredData || '',
                errorMessage: bcResult.errorMessage || ''
            }
        };

        context.log(`✅ Response: ${(bcResult.responseText || '').substring(0, 100)}`);

    } catch (error) {
        context.log(`❌ Error: ${error.message}`);
        context.res = {
            status: 500,
            headers: corsHeaders,
            body: {
                success: false,
                error: error.message,
                queryText: (req.body || {}).queryText || '[audio input]'
            }
        };
    }
};
