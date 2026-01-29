let FormData, fetch;

try {
    FormData = require('form-data');
    fetch = require('node-fetch');
} catch (err) {
    console.error('Failed to load dependencies:', err.message);
}

/**
 * Azure Function: Audio Transcription Proxy
 * 
 * Receives base64 audio from BC Mobile App and forwards to OpenAI Whisper API
 * Solves the AL multipart/form-data limitation
 */

module.exports = async function (context, req) {
    context.log('Transcription request received');

    try {
        if (!FormData || !fetch) {
            throw new Error('Required dependencies (form-data, node-fetch) are not installed. Please ensure package.json dependencies are installed.');
        }
        const body = req.body;
        const { audioData, mimeType } = body;

        if (!audioData) {
            context.res = {
                status: 400,
                jsonBody: { error: 'No audio data provided' }
            };
            return;
        }

        // Determine file extension from MIME type
        let extension = 'm4a';
        if (mimeType) {
            if (mimeType.includes('wav')) extension = 'wav';
            else if (mimeType.includes('webm')) extension = 'webm';
            else if (mimeType.includes('mp3')) extension = 'mp3';
            else if (mimeType.includes('ogg')) extension = 'ogg';
        }

        // Convert base64 to buffer
        const audioBuffer = Buffer.from(audioData, 'base64');

        // Create form data for OpenAI Whisper API
        const formData = new FormData();
        formData.append('file', audioBuffer, {
            filename: `audio.${extension}`,
            contentType: mimeType || 'audio/mp4'
        });
        formData.append('model', 'whisper-1');
        formData.append('language', 'en');

        // Choose API based on configuration
        const useAzureOpenAI = process.env.AZURE_OPENAI_ENDPOINT && process.env.AZURE_OPENAI_KEY && process.env.AZURE_OPENAI_WHISPER_DEPLOYMENT;
        
        let apiUrl;
        let headers;
        
        if (useAzureOpenAI) {
            // Use Azure OpenAI Whisper deployment (requires separate Whisper model deployment)
            apiUrl = `${process.env.AZURE_OPENAI_ENDPOINT}/openai/deployments/${process.env.AZURE_OPENAI_WHISPER_DEPLOYMENT}/audio/transcriptions?api-version=2024-10-21`;
            headers = { 'api-key': process.env.AZURE_OPENAI_KEY };
        } else {
            // Fall back to public OpenAI API (default behavior)
            apiUrl = 'https://api.openai.com/v1/audio/transcriptions';
            headers = { 'Authorization': `Bearer ${process.env.OPENAI_API_KEY}` };
        }

        // Forward to Whisper API
        const response = await fetch(apiUrl, {
            method: 'POST',
            body: formData,
            headers: {
                ...formData.getHeaders(),
                ...headers
            }
        });

        if (!response.ok) {
            const errorText = await response.text();
            context.log(`❌ Whisper API error: ${errorText}`);
            context.res = {
                status: response.status,
                jsonBody: { 
                    error: 'Transcription failed',
                    details: errorText
                }
            };
            return;
        }

        const result = await response.json();
        
        context.res = {
            status: 200,
            jsonBody: {
                text: result.text,
                success: true
            }
        };

    } catch (error) {
        context.log(`❌ Transcription error: ${error.message}`);
        context.res = {
            status: 500,
            jsonBody: { 
                error: 'Internal server error',
                message: error.message 
            }
        };
    }
};
