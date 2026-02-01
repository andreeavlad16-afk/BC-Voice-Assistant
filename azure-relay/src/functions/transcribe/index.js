const FormData = require('form-data');
const fetch = require('node-fetch');

/**
 * Azure Function: Audio Transcription Proxy
 * 
 * Receives base64 audio from iOS/Android app and forwards to Azure OpenAI Whisper API
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
                jsonBody: { error: 'No audio data provided' }
            };
            return;
        }

        // Check if Whisper is configured
        const useAzureOpenAI = process.env.AZURE_OPENAI_ENDPOINT && 
                               process.env.AZURE_OPENAI_KEY && 
                               process.env.AZURE_OPENAI_WHISPER_DEPLOYMENT;
        const useOpenAI = process.env.OPENAI_API_KEY;

        if (!useAzureOpenAI && !useOpenAI) {
            context.log('❌ No Whisper API configured');
            context.res = {
                status: 500,
                jsonBody: { 
                    error: 'Whisper transcription not configured',
                    details: 'Missing AZURE_OPENAI_WHISPER_DEPLOYMENT or OPENAI_API_KEY',
                    hint: 'Please configure Azure OpenAI Whisper deployment or OpenAI API key in Function App settings'
                }
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
        context.log(`Audio size: ${audioBuffer.length} bytes, format: ${extension}`);

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

        context.log(`Whisper API URL: ${apiUrl.replace(/api-key=[^&]*/, 'api-key=***')}`);

        // Forward to Whisper API with retry logic
        const maxAttempts = 3;
        let lastError = null;

        for (let attempt = 1; attempt <= maxAttempts; attempt++) {
            try {
                const response = await fetch(apiUrl, {
                    method: 'POST',
                    body: formData,
                    headers: {
                        ...formData.getHeaders(),
                        ...headers
                    }
                });

                if (response.ok) {
                    const result = await response.json();
                    context.log(`✅ Transcription successful: "${result.text}"`);
                    
                    context.res = {
                        status: 200,
                        jsonBody: {
                            text: result.text,
                            success: true
                        }
                    };
                    return;
                }

                // Handle error responses
                const errorText = await response.text();
                context.log(`❌ Whisper API error (${response.status}, attempt ${attempt}/${maxAttempts}): ${errorText}`);
                
                // If rate limited (429), retry after delay
                if (response.status === 429 && attempt < maxAttempts) {
                    const retryAfter = response.headers.get('retry-after');
                    const delayMs = retryAfter ? parseInt(retryAfter) * 1000 : 2000 * attempt;
                    context.log(`Rate limited, retrying in ${delayMs}ms...`);
                    await new Promise(resolve => setTimeout(resolve, delayMs));
                    continue;
                }

                // Store error for final response
                lastError = {
                    status: response.status,
                    details: errorText
                };

                // Don't retry on client errors (400, 401, 403, etc.)
                if (response.status >= 400 && response.status < 500 && response.status !== 429) {
                    break;
                }

            } catch (fetchError) {
                context.log(`❌ Fetch error (attempt ${attempt}/${maxAttempts}): ${fetchError.message}`);
                lastError = {
                    status: 500,
                    details: fetchError.message
                };
                
                // Retry on network errors
                if (attempt < maxAttempts) {
                    await new Promise(resolve => setTimeout(resolve, 1000 * attempt));
                    continue;
                }
            }
        }

        // All attempts failed
        context.res = {
            status: lastError?.status || 500,
            jsonBody: { 
                error: 'Transcription failed',
                details: lastError?.details || 'Unknown error',
                attempts: maxAttempts
            }
        };

    } catch (error) {
        context.log(`❌ Transcription error: ${error.message}`);
        context.log(`Stack trace: ${error.stack}`);
        context.res = {
            status: 500,
            jsonBody: { 
                error: 'Internal server error',
                message: error.message 
            }
        };
    }
};
