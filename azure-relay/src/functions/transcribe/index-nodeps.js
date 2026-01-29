const https = require('https');
const { URL } = require('url');

/**
 * Azure Function: Audio Transcription Proxy (No External Dependencies)
 * 
 * Receives base64 audio from BC Mobile App and forwards to Azure OpenAI Whisper API
 * Uses only built-in Node.js modules
 */

function makeHttpsRequest(url, options, body) {
    return new Promise((resolve, reject) => {
        const parsedUrl = new URL(url);
        
        const requestOptions = {
            hostname: parsedUrl.hostname,
            port: parsedUrl.port || 443,
            path: parsedUrl.pathname + parsedUrl.search,
            method: options.method || 'POST',
            headers: options.headers || {}
        };

        const req = https.request(requestOptions, (res) => {
            let data = '';
            res.on('data', (chunk) => { data += chunk; });
            res.on('end', () => {
                resolve({ statusCode: res.statusCode, body: data, headers: res.headers });
            });
        });

        req.on('error', reject);
        if (body) req.write(body);
        req.end();
    });
}

function createMultipartBody(audioBuffer, filename, mimeType) {
    const boundary = `----WebKitFormBoundary${Date.now()}${Math.random().toString(36)}`;
    const CRLF = '\r\n';
    
    let body = '';
    
    // Add file field
    body += `--${boundary}${CRLF}`;
    body += `Content-Disposition: form-data; name="file"; filename="${filename}"${CRLF}`;
    body += `Content-Type: ${mimeType}${CRLF}${CRLF}`;
    
    // Convert body to Buffer, append audio, then add closing boundary
    const preable = Buffer.from(body, 'utf8');
    const epilogue = Buffer.from(`${CRLF}--${boundary}--${CRLF}`, 'utf8');
    
    return {
        boundary,
        body: Buffer.concat([preable, audioBuffer, epilogue])
    };
}

module.exports = async function (context, req) {
    context.log('Transcription request received (no-deps version)');

    try {
        const body = req.body;
        const { audioData, mimeType } = body;

        if (!audioData) {
            context.res = {
                status: 400,
                body: JSON.stringify({ error: 'No audio data provided' })
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
        context.log(`Audio buffer size: ${audioBuffer.length} bytes`);

        // Check for Azure OpenAI configuration
        const endpoint = process.env.AZURE_OPENAI_ENDPOINT;
        const apiKey = process.env.AZURE_OPENAI_KEY;
        const deployment = process.env.AZURE_OPENAI_WHISPER_DEPLOYMENT;
        const apiVersion = process.env.AZURE_OPENAI_API_VERSION || '2024-10-21';

        if (!endpoint || !apiKey || !deployment) {
            throw new Error('Azure OpenAI configuration missing. Required: AZURE_OPENAI_ENDPOINT, AZURE_OPENAI_KEY, AZURE_OPENAI_WHISPER_DEPLOYMENT');
        }

        // Build Azure OpenAI Whisper URL
        const whisperUrl = `${endpoint}/openai/deployments/${deployment}/audio/transcriptions?api-version=${apiVersion}`;
        context.log(`Calling: ${whisperUrl}`);

        // Create multipart form data
        const { boundary, body: multipartBody } = createMultipartBody(
            audioBuffer,
            `audio.${extension}`,
            mimeType || 'audio/mp4'
        );

        // Call Azure OpenAI Whisper API
        const response = await makeHttpsRequest(whisperUrl, {
            method: 'POST',
            headers: {
                'api-key': apiKey,
                'Content-Type': `multipart/form-data; boundary=${boundary}`,
                'Content-Length': multipartBody.length
            }
        }, multipartBody);

        context.log(`Whisper API response status: ${response.statusCode}`);

        if (response.statusCode !== 200) {
            context.log(`❌ Whisper API error: ${response.body}`);
            context.res = {
                status: response.statusCode,
                body: JSON.stringify({
                    error: 'Transcription failed',
                    details: response.body
                })
            };
            return;
        }

        // Parse and return transcription
        const result = JSON.parse(response.body);
        context.log(`✓ Transcription successful: "${result.text}"`);

        context.res = {
            status: 200,
            body: JSON.stringify({
                text: result.text,
                language: result.language || 'en'
            })
        };

    } catch (error) {
        context.log(`❌ Error: ${error.message}`);
        context.log(error.stack);
        
        context.res = {
            status: 500,
            body: JSON.stringify({
                error: 'Internal server error',
                message: error.message
            })
        };
    }
};
