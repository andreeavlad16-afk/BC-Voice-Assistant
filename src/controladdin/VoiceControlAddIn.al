/// <summary>
/// Control add-in for voice input with browser-based speech recognition and audio recording.
/// Provides speech-to-text, text-to-speech, and audio capture capabilities.
/// </summary>
controladdin "Voice Control Add-in"
{
    RequestedHeight = 300;
    MinimumHeight = 200;
    RequestedWidth = 400;
    MinimumWidth = 300;
    VerticalStretch = true;
    VerticalShrink = true;
    HorizontalStretch = true;
    HorizontalShrink = true;

    Scripts = 'src/controladdin/scripts/VoiceControl.js';
    StyleSheets = 'src/controladdin/styles/VoiceControl.css';

    // Events triggered from JavaScript to AL
    /// <summary>
    /// Triggered when voice input is recognized or processed.
    /// </summary>
    /// <param name="inputText">The recognized text or structured JSON from voice input.</param>
    event OnVoiceInput(inputText: Text);
    /// <summary>
    /// Triggered when audio data is captured for cloud transcription.
    /// </summary>
    /// <param name="audioData">Base64-encoded audio data with metadata.</param>
    event OnAudioInput(audioData: Text);  // Base64 audio for cloud transcription
    /// <summary>
    /// Triggered when a speech recognition error occurs.
    /// </summary>
    /// <param name="errorMessage">Error message describing the speech error.</param>
    event OnSpeechError(errorMessage: Text);
    /// <summary>
    /// Triggered when the control add-in is loaded and ready for use.
    /// </summary>
    event OnReady();

    // Procedures called from AL to JavaScript
    procedure StartListening();
    procedure StopListening();
    procedure SpeakResponse(responseText: Text);
    procedure DisplayResponse(responseText: Text);
    procedure SetBackendUrl(url: Text);
    procedure OnTranscriptionResult(transcript: Text);  // Return transcription to JS
}
