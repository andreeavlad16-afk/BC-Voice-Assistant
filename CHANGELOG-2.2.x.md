# Changelog - Version 2.2.x

## Version 2.2.0.21 (2026-02-01)
### Fixed
- **iOS Transcription Response Parsing**: Added speech sanitization to remove literal `\n`, `\r`, `\t` characters and actual line breaks/tabs from AI responses before text-to-speech output
- Prevents text-to-speech from reading out "backslash n" and other non-audible characters

### Added
- `SanitizeForSpeech()` function in Voice Command API to clean response text
- Removes literal escape sequences and whitespace characters
- Normalizes multiple spaces to single spaces

## Version 2.2.0.20 (2026-01-31)
### Added
- **Debug Logging for iOS Transcription**: Added detailed logging in transcription response parsing to diagnose mobile client issues
- Shows exact response received from Azure Function transcription endpoint

### Fixed
- Azure Function transcription endpoint now includes explicit `Content-Length` header
- Improved response format for mobile HTTP clients

## Version 2.2.0.19 (2026-01-30)
### Fixed
- **iOS/PWA Transcription Endpoint**: Complete rewrite of `/api/transcribe` Azure Function
  - Now uses `form-data` and `node-fetch` packages for proper multipart/form-data handling
  - Fixed response format with explicit `Content-Type: application/json` headers
  - Added CORS support for PWA domain
  - Improved error handling and logging

### Technical Changes
- Replaced custom HTTPS implementation with standard npm packages
- Added retry logic for Azure OpenAI rate limits (429 errors)
- Response format: `{ "text": "...", "success": true }`
- Environment variables: `AZURE_OPENAI_ENDPOINT`, `AZURE_OPENAI_KEY`, `AZURE_OPENAI_WHISPER_DEPLOYMENT`

## Previous Versions
See [CHANGELOG-2.1.x.md](CHANGELOG-2.1.x.md) for version 2.1.x changes.
