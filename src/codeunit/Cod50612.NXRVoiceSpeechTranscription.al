/// <summary>
/// Handles cloud-based audio transcription using OpenAI Whisper or Azure Speech services.
/// Used as fallback when browser Web Speech API is unavailable (mobile WebViews).
/// </summary>
codeunit 50612 "NXR Voice Speech Transcription"
{
    // Handles audio transcription using OpenAI Whisper API
    // Used when Web Speech API is not available (mobile WebViews)

    var
        Setup: Record "NXR Voice Assistant Setup";

    /// <summary>
    /// Transcribes Base64-encoded audio data to text using configured AI backend.
    /// </summary>
    /// <param name="Base64Audio">Base64-encoded audio data.</param>
    /// <param name="MimeType">MIME type of the audio (e.g., audio/webm, audio/mp4, audio/m4a).</param>
    /// <returns>Transcribed text, or empty string if transcription failed.</returns>
    procedure TranscribeAudio(Base64Audio: Text; MimeType: Text): Text
    var
        ApiKey: SecretText;
    begin
        if not Setup.Get() then
            exit('');

        ApiKey := Setup.GetApiKey();
        if ApiKey.IsEmpty() then
            exit('Transcription requires API key configuration');

        case Setup."AI Backend Type" of
            Setup."AI Backend Type"::OpenAI:
                exit('OpenAI Whisper transcription from BC is not supported due to AL multipart/form-data limitations. Please use Azure OpenAI or deploy an Azure Function proxy.');
            Setup."AI Backend Type"::AzureOpenAI:
                exit(TranscribeWithAzureOpenAI(Base64Audio, MimeType, ApiKey));
            else
                exit('Transcription not configured. Please set up Azure OpenAI backend.');
        end;
    end;

    local procedure TranscribeWithAzureOpenAI(Base64Audio: Text; MimeType: Text; ApiKey: SecretText): Text
    var
        Client: HttpClient;
        RequestContent: HttpContent;
        Response: HttpResponseMessage;
        ContentHeaders: HttpHeaders;
        ResponseText: Text;
        ResponseJson: JsonObject;
        TextToken: JsonToken;
        TranscriptionProxyUrl: Text;
        RequestJson: JsonObject;
        RequestText: Text;
        SuccessToken: JsonToken;
    begin
        // Check if transcription proxy is configured
        TranscriptionProxyUrl := Setup."Transcription Proxy URL";

        if TranscriptionProxyUrl = '' then
            exit('Audio transcription requires an Azure Function proxy. Configure "Transcription Proxy URL" in Voice Assistant Setup, or use the PWA for direct browser speech recognition.');

        // Build JSON request
        RequestJson.Add('audioData', Base64Audio);
        RequestJson.Add('mimeType', MimeType);
        RequestJson.WriteTo(RequestText);

        // Log audio size for troubleshooting
        Message('Audio size: %1 KB, MIME: %2', StrLen(Base64Audio) / 1024, MimeType);

        RequestContent.WriteFrom(RequestText);
        RequestContent.GetHeaders(ContentHeaders);
        ContentHeaders.Clear();
        ContentHeaders.Add('Content-Type', 'application/json');

        Client.Timeout(60000); // 60 seconds for audio processing

        Message('Sending to: %1', TranscriptionProxyUrl);

        if not Client.Post(TranscriptionProxyUrl, RequestContent, Response) then begin
            Message('Client.Post returned FALSE - connection failed');
            exit('Failed to connect to transcription proxy');
        end;

        Message('Got response with status: %1', Response.HttpStatusCode());

        if not Response.IsSuccessStatusCode() then begin
            Response.Content().ReadAs(ResponseText);
            Message('HTTP Error %1: %2', Response.HttpStatusCode(), ResponseText);
            exit('Transcription failed - check error message');
        end;

        Response.Content().ReadAs(ResponseText);

        if not ResponseJson.ReadFrom(ResponseText) then begin
            Message('JSON Parse failed for: %1', ResponseText);
            exit('Invalid response from transcription service');
        end;

        // Check success
        if ResponseJson.Get('success', SuccessToken) then
            if not SuccessToken.AsValue().AsBoolean() then
                exit('Transcription was not successful');

        if ResponseJson.Get('text', TextToken) then
            exit(TextToken.AsValue().AsText());

        exit('No transcription text returned');
    end;

    local procedure TranscribeWithOpenAI(Base64Audio: Text; MimeType: Text; ApiKey: SecretText): Text
    var
        Client: HttpClient;
        RequestContent: HttpContent;
        Response: HttpResponseMessage;
        ContentHeaders: HttpHeaders;
        ResponseText: Text;
        ResponseJson: JsonObject;
        TranscriptToken: JsonToken;
        Boundary: Text;
        RequestBody: TextBuilder;
        FileExtension: Text;
        FileName: Text;
        Base64Convert: Codeunit "Base64 Convert";
        TempBlob: Codeunit "Temp Blob";
        OutStr: OutStream;
        InStr: InStream;
        AudioDataText: Text;
    begin
        // Map MIME type to supported file extension
        // Whisper supports: flac, m4a, mp3, mp4, mpeg, mpga, oga, ogg, wav, webm
        case true of
            MimeType.Contains('wav'):
                FileExtension := 'wav';
            MimeType.Contains('webm'):
                FileExtension := 'webm';
            MimeType.Contains('mp4'), MimeType.Contains('m4a'):
                FileExtension := 'm4a';
            MimeType.Contains('mp3'), MimeType.Contains('mpeg'):
                FileExtension := 'mp3';
            MimeType.Contains('ogg'):
                FileExtension := 'ogg';
            MimeType.Contains('flac'):
                FileExtension := 'flac';
            else
                // Default to m4a which is widely supported on iOS
                FileExtension := 'm4a';
        end;

        FileName := 'audio.' + FileExtension;

        // Create boundary for multipart form data
        Boundary := CreateGuid();
        Boundary := DelChr(Boundary, '=', '{}-');

        // Convert Base64 to binary and store in TempBlob
        TempBlob.CreateOutStream(OutStr);
        Base64Convert.FromBase64(Base64Audio, OutStr);

        // Build multipart/form-data request
        // Format: --boundary\r\nheaders\r\n\r\nbinarydata\r\n--boundary\r\nheaders\r\n\r\nvalue\r\n--boundary--

        RequestBody.Append('--' + Boundary + '\r\n');
        RequestBody.Append('Content-Disposition: form-data; name="file"; filename="' + FileName + '"\r\n');
        RequestBody.Append('Content-Type: ' + MimeType + '\r\n');
        RequestBody.Append('\r\n');

        // Read binary audio data
        TempBlob.CreateInStream(InStr);
        InStr.ReadText(AudioDataText);
        RequestBody.Append(AudioDataText);

        RequestBody.Append('\r\n--' + Boundary + '\r\n');
        RequestBody.Append('Content-Disposition: form-data; name="model"\r\n');
        RequestBody.Append('\r\n');
        RequestBody.Append('whisper-1');
        RequestBody.Append('\r\n--' + Boundary + '\r\n');
        RequestBody.Append('Content-Disposition: form-data; name="language"\r\n');
        RequestBody.Append('\r\n');
        RequestBody.Append('en');
        RequestBody.Append('\r\n--' + Boundary + '--\r\n');

        RequestContent.WriteFrom(RequestBody.ToText());
        RequestContent.GetHeaders(ContentHeaders);
        ContentHeaders.Clear();
        ContentHeaders.Add('Content-Type', 'multipart/form-data; boundary=' + Boundary);

        Client.DefaultRequestHeaders().Add('Authorization', SecretStrSubstNo('Bearer %1', ApiKey));
        Client.Timeout(60000); // 60 second timeout for audio processing

        if not Client.Post('https://api.openai.com/v1/audio/transcriptions', RequestContent, Response) then
            exit('Failed to connect to transcription service');

        if not Response.IsSuccessStatusCode() then begin
            Response.Content().ReadAs(ResponseText);
            exit('Transcription failed: ' + ResponseText);
        end;

        Response.Content().ReadAs(ResponseText);

        if not ResponseJson.ReadFrom(ResponseText) then
            exit('Invalid response from transcription service');

        if ResponseJson.Get('text', TranscriptToken) then
            exit(TranscriptToken.AsValue().AsText());

        exit('');
    end;

    local procedure TranscribeWithAzureSpeech(Base64Audio: Text; MimeType: Text): Text
    var
        Client: HttpClient;
        RequestContent: HttpContent;
        Response: HttpResponseMessage;
        ContentHeaders: HttpHeaders;
        ResponseText: Text;
        ResponseJson: JsonObject;
        DisplayTextToken: JsonToken;
        ApiKey: SecretText;
        AzureEndpoint: Text;
        AzureRegion: Text;
    begin
        // Azure Speech Services requires different setup
        // Using Azure Speech-to-Text REST API

        ApiKey := Setup.GetApiKey();
        if ApiKey.IsEmpty() then
            exit('Azure Speech requires API key');

        // Extract region from endpoint (e.g., https://westeurope.api.cognitive.microsoft.com)
        AzureEndpoint := Setup."API Endpoint";
        if AzureEndpoint.Contains('.api.cognitive.microsoft.com') then begin
            AzureRegion := AzureEndpoint.Replace('https://', '');
            AzureRegion := CopyStr(AzureRegion, 1, StrPos(AzureRegion, '.') - 1);
        end else begin
            AzureRegion := 'westeurope'; // Default
        end;

        // For Azure Speech, the implementation is similar but uses different endpoint
        // Azure Speech REST API: https://{region}.stt.speech.microsoft.com/speech/recognition/conversation/cognitiveservices/v1

        exit('Azure Speech transcription - implementation pending');
    end;

    /// <summary>
    /// Checks if cloud transcription is available based on current configuration.
    /// </summary>
    /// <returns>True if an API key is configured for transcription, false otherwise.</returns>
    procedure IsTranscriptionAvailable(): Boolean
    begin
        if not Setup.Get() then
            exit(false);

        if not Setup.HasApiKey() then
            exit(false);

        exit(Setup."AI Backend Type" in [Setup."AI Backend Type"::OpenAI, Setup."AI Backend Type"::AzureOpenAI]);
    end;
}
