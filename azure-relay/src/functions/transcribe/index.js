const https = require('https');
const { URL } = require('url');

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
    body += `--${boundary}${CRLF}`;
    body += `Content-Disposition: form-data; name="file"; filename="${filename}"${CRLF}`;
    body += `Content-Type: ${mimeType}${CRLF}${CRLF}`;

    const preamble = Buffer.from(body, 'utf8');
    const epilogue = Buffer.from(`${CRLF}--${boundary}--${CRLF}`, 'utf8');

    return {
        boundary,
        body: Buffer.concat([preamble, audioBuffer, epilogue])
    };
}

function delay(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}

module.exports = async function (context, req) {
    context.log('Transcription request received (no-deps clean version)');

    try {
        const { audioData, mimeType } = req.body || {};

        if (!audioData) {
            context.res = {
                status: 400,
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ error: 'No audio data provided' })
            };
            return;
        }

        let extension = 'm4a';
        if (mimeType) {
            if (mimeType.includes('wav')) extension = 'wav';
            else if (mimeType.includes('webm')) extension = 'webm';
            else if (mimeType.includes('mp3')) extension = 'mp3';
            else if (mimeType.includes('ogg')) extension = 'ogg';
        }

        const audioBuffer = Buffer.from(audioData, 'base64');
        context.log(`Audio buffer size: ${audioBuffer.length} bytes`);

        const endpoint = process.env.AZURE_OPENAI_ENDPOINT;
        const apiKey = process.env.AZURE_OPENAI_KEY;
        const deployment = process.env.AZURE_OPENAI_WHISPER_DEPLOYMENT;
        const apiVersion = process.env.AZURE_OPENAI_API_VERSION || '2024-10-21';

        if (!endpoint || !apiKey || !deployment) {
            throw new Error('Azure OpenAI configuration missing. Required: AZURE_OPENAI_ENDPOINT, AZURE_OPENAI_KEY, AZURE_OPENAI_WHISPER_DEPLOYMENT');
        }

        const whisperUrl = `${endpoint}/openai/deployments/${deployment}/audio/transcriptions?api-version=${apiVersion}`;
        context.log(`Calling Whisper at ${whisperUrl}`);

        const { boundary, body: multipartBody } = createMultipartBody(
            audioBuffer,
            `audio.${extension}`,
            mimeType || 'audio/mp4'
        );

        const maxAttempts = 3;
        let attempt = 0;
        let response;

        while (attempt < maxAttempts) {
            attempt += 1;
            response = await makeHttpsRequest(whisperUrl, {
                method: 'POST',
                headers: {
                    'api-key': apiKey,
                    'Content-Type': `multipart/form-data; boundary=${boundary}`,
                    'Content-Length': multipartBody.length
                }
            }, multipartBody);

            context.log(`Whisper status: ${response.statusCode} (attempt ${attempt})`);

            if (response.statusCode !== 429) {
                break;
            }

            const retryAfterHeader = response.headers?.['retry-after'];
            const retryMs = retryAfterHeader ? parseInt(retryAfterHeader, 10) * 1000 : 1500 * attempt;
            context.log(`429 rate limit; retrying in ${retryMs} ms`);
            await delay(retryMs);
        }

        if (!response || response.statusCode !== 200) {
            context.log(`Whisper error body: ${response?.body}`);
            context.res = {
                status: response?.statusCode || 500,
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    error: 'Transcription failed',
                    details: response?.body || 'Unknown error',
                    rateLimited: response?.statusCode === 429
                })
            };
            return;
        }

        const result = JSON.parse(response.body);
        context.log(`Transcription text: ${result.text}`);

        context.res = {
            status: 200,
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                text: result.text,
                language: result.language || 'en'
            })
        };
    } catch (error) {
        context.log(`Transcription error: ${error.message}`);
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
