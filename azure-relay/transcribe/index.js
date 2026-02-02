const FormData = require('form-data');
const fetch = require('node-fetch');

/**
 * Azure Function: Audio Transcription Proxy
 * 
 * Receives base64 audio from BC Mobile App and forwards to OpenAI Whisper API
 * Solves the AL multipart/form-data limitation
 */

module.exports = async function (context, req) {
    context.log('Transcription request received');

    try {
        const body = req.body;
        const { audioData, mimeType } = body;

        if (!audioData) {
            context.res = {
                status: 400,
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ error: 'No audio data provided' })
            };
            return;
        }

        // Check if Whisper is configured
        const useAzureOpenAI = process.env.AZURE_OPENAI_ENDPOINT && process.env.AZURE_OPENAI_KEY && process.env.AZURE_OPENAI_WHISPER_DEPLOYMENT;
        const useOpenAI = process.env.OPENAI_API_KEY;

        if (!useAzureOpenAI && !useOpenAI) {
            context.log('❌ No Whisper API configured');
            context.res = {
                status: 500,
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ 
                    error: 'Whisper transcription not configured',
                    details: 'Missing AZURE_OPENAI_WHISPER_DEPLOYMENT or OPENAI_API_KEY'
                })
            };
            return;
        }

        context.log(`Using ${useAzureOpenAI ? 'Azure OpenAI' : 'OpenAI'} Whisper`);

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
        const apiUrl = useAzureOpenAI
            ? `${process.env.AZURE_OPENAI_ENDPOINT}/openai/deployments/${process.env.AZURE_OPENAI_WHISPER_DEPLOYMENT}/audio/transcriptions?api-version=2024-10-21`
            : 'https://api.openai.com/v1/audio/transcriptions';

        const headers = useAzureOpenAI
            ? { 'api-key': process.env.AZURE_OPENAI_KEY }
            : { 'Authorization': `Bearer ${process.env.OPENAI_API_KEY}` };

        context.log(`Whisper API URL: ${apiUrl}`);
        context.log(`Audio size: ${audioBuffer.length} bytes, format: ${extension}`);

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
            context.log(`❌ Whisper API error (${response.status}): ${errorText}`);
            context.res = {
                status: response.status,
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ 
                    error: 'Transcription failed',
                    details: errorText,
                    statusCode: response.status,
                    apiUrl: apiUrl.replace(/api-key=[^&]*/, 'api-key=***')
                })
            };
            return;
        }

        const result = await response.json();
        
        context.log(`✅ Transcription successful: "${result.text}"`);
        
        const responseBody = {
            text: result.text,
            success: true
        };
        
        const bodyString = JSON.stringify(responseBody);
        context.log(`Response body string: ${bodyString}`);
        
        context.res = {
            status: 200,
            headers: { 
                'Content-Type': 'application/json; charset=utf-8',
                'Content-Length': Buffer.byteLength(bodyString, 'utf8').toString()
            },
            body: bodyString
        };

    } catch (error) {
        context.log(`❌ Transcription error: ${error.message}`);
        context.res = {
            status: 500,
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ 
                error: 'Internal server error',
                message: error.message 
            })
        };
    }
};
