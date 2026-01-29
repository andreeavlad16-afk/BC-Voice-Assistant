# Android App Integration Guide - BC Voice Assistant

## Overview

Custom Android app to send voice queries to Business Central via Azure Function.

**Why Custom App Needed:**
- ❌ BC Mobile App doesn't allow microphone access
- ✅ Custom Android app can record audio and send to Azure Function
- ✅ Azure Function handles transcription + query processing + response

---

## Architecture

```
Android App
    ↓ Record Audio (Microphone)
    ↓ Send to Azure Function
https://func-bcvoice-prod.azurewebsites.net/api/voiceQuery
    ↓ Transcribe (Whisper)
    ↓ Analyze (GPT-4o-mini)
    ↓ Query BC via OData
    ↓ Return Response
Android App displays result
```

---

## API Endpoint

### Base URL
```
https://func-bcvoice-prod.azurewebsites.net
```

### Endpoints Available

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/voiceQuery` | POST | Complete flow: Audio → Text → Query → Response |
| `/api/transcribe` | POST | Audio → Text only |
| `/api/query` | POST | Text query → Response |

**Recommended:** Use `/api/voiceQuery` for simplest integration.

---

## Authentication

### Get Function Key

1. Open Azure Portal
2. Navigate to Function App: `func-bcvoice-prod`
3. Go to: Functions → voiceQuery → Function Keys
4. Copy the `default` key

**Add to HTTP headers:**
```
x-functions-key: [your-function-key]
```

**Alternative:** Use host-level key (works for all functions):
- Go to Function App → App Keys → Host keys
- Copy `default` or `_master` key

---

## Android Implementation

### 1. Add Dependencies (build.gradle)

```gradle
dependencies {
    // HTTP client
    implementation 'com.squareup.okhttp3:okhttp:4.12.0'
    
    // JSON parsing
    implementation 'com.google.code.gson:gson:2.10.1'
    
    // Coroutines for async
    implementation 'org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3'
    
    // Permissions
    implementation 'androidx.core:core-ktx:1.12.0'
}
```

### 2. AndroidManifest.xml Permissions

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.INTERNET" />
```

### 3. Audio Recording (WebM format recommended)

```kotlin
class AudioRecorder(private val context: Context) {
    private var mediaRecorder: MediaRecorder? = null
    private var outputFile: File? = null
    
    fun startRecording(): File {
        outputFile = File(context.cacheDir, "voice_query_${System.currentTimeMillis()}.webm")
        
        mediaRecorder = MediaRecorder().apply {
            setAudioSource(MediaRecorder.AudioSource.MIC)
            setOutputFormat(MediaRecorder.OutputFormat.WEBM)
            setAudioEncoder(MediaRecorder.AudioEncoder.OPUS)
            setAudioSamplingRate(16000)
            setAudioEncodingBitRate(128000)
            setOutputFile(outputFile!!.absolutePath)
            prepare()
            start()
        }
        
        return outputFile!!
    }
    
    fun stopRecording() {
        mediaRecorder?.apply {
            stop()
            release()
        }
        mediaRecorder = null
    }
}
```

### 4. API Client

```kotlin
class BCVoiceAPIClient {
    private val client = OkHttpClient()
    private val baseUrl = "https://func-bcvoice-prod.azurewebsites.net"
    private val functionKey = "YOUR_FUNCTION_KEY_HERE" // Get from Azure Portal
    
    suspend fun sendVoiceQuery(audioFile: File): Result<String> = withContext(Dispatchers.IO) {
        try {
            val requestBody = MultipartBody.Builder()
                .setType(MultipartBody.FORM)
                .addFormDataPart(
                    "file", 
                    audioFile.name,
                    audioFile.asRequestBody("audio/webm".toMediaType())
                )
                .build()
            
            val request = Request.Builder()
                .url("$baseUrl/api/voiceQuery")
                .header("x-functions-key", functionKey)
                .post(requestBody)
                .build()
            
            val response = client.newCall(request).execute()
            
            if (response.isSuccessful) {
                Result.success(response.body?.string() ?: "")
            } else {
                Result.failure(Exception("API Error: ${response.code}"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }
    
    suspend fun sendTextQuery(queryText: String): Result<String> = withContext(Dispatchers.IO) {
        try {
            val json = JSONObject().apply {
                put("query", queryText)
            }
            
            val requestBody = json.toString()
                .toRequestBody("application/json".toMediaType())
            
            val request = Request.Builder()
                .url("$baseUrl/api/query")
                .header("x-functions-key", functionKey)
                .post(requestBody)
                .build()
            
            val response = client.newCall(request).execute()
            
            if (response.isSuccessful) {
                Result.success(response.body?.string() ?: "")
            } else {
                Result.failure(Exception("API Error: ${response.code}"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }
}
```

### 5. ViewModel (MVVM Pattern)

```kotlin
class VoiceQueryViewModel : ViewModel() {
    private val apiClient = BCVoiceAPIClient()
    private val audioRecorder = AudioRecorder(context)
    
    private val _queryResult = MutableLiveData<String>()
    val queryResult: LiveData<String> = _queryResult
    
    private val _isRecording = MutableLiveData<Boolean>(false)
    val isRecording: LiveData<Boolean> = _isRecording
    
    private val _isLoading = MutableLiveData<Boolean>(false)
    val isLoading: LiveData<Boolean> = _isLoading
    
    private var currentAudioFile: File? = null
    
    fun startRecording() {
        currentAudioFile = audioRecorder.startRecording()
        _isRecording.value = true
    }
    
    fun stopRecordingAndQuery() {
        audioRecorder.stopRecording()
        _isRecording.value = false
        
        currentAudioFile?.let { file ->
            viewModelScope.launch {
                _isLoading.value = true
                
                val result = apiClient.sendVoiceQuery(file)
                
                result.onSuccess { response ->
                    _queryResult.value = response
                }.onFailure { error ->
                    _queryResult.value = "Error: ${error.message}"
                }
                
                _isLoading.value = false
                file.delete() // Cleanup
            }
        }
    }
    
    fun sendTextQuery(text: String) {
        viewModelScope.launch {
            _isLoading.value = true
            
            val result = apiClient.sendTextQuery(text)
            
            result.onSuccess { response ->
                _queryResult.value = response
            }.onFailure { error ->
                _queryResult.value = "Error: ${error.message}"
            }
            
            _isLoading.value = false
        }
    }
}
```

### 6. UI Activity

```kotlin
class VoiceQueryActivity : AppCompatActivity() {
    private val viewModel: VoiceQueryViewModel by viewModels()
    private lateinit var binding: ActivityVoiceQueryBinding
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityVoiceQueryBinding.inflate(layoutInflater)
        setContentView(binding.root)
        
        // Check/Request microphone permission
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) 
            != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 1)
        }
        
        // Observe recording state
        viewModel.isRecording.observe(this) { isRecording ->
            if (isRecording) {
                binding.btnRecord.text = "Stop & Send"
                binding.btnRecord.setBackgroundColor(Color.RED)
            } else {
                binding.btnRecord.text = "Start Recording"
                binding.btnRecord.setBackgroundColor(Color.GREEN)
            }
        }
        
        // Observe loading state
        viewModel.isLoading.observe(this) { isLoading ->
            binding.progressBar.visibility = if (isLoading) View.VISIBLE else View.GONE
            binding.btnRecord.isEnabled = !isLoading
        }
        
        // Observe query result
        viewModel.queryResult.observe(this) { result ->
            binding.tvResult.text = result
        }
        
        // Record button click
        binding.btnRecord.setOnClickListener {
            if (viewModel.isRecording.value == true) {
                viewModel.stopRecordingAndQuery()
            } else {
                viewModel.startRecording()
            }
        }
        
        // Text query button
        binding.btnTextQuery.setOnClickListener {
            val text = binding.etQuery.text.toString()
            if (text.isNotEmpty()) {
                viewModel.sendTextQuery(text)
            }
        }
    }
}
```

### 7. Layout XML (activity_voice_query.xml)

```xml
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical"
    android:padding="16dp">
    
    <TextView
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:text="BC Voice Assistant"
        android:textSize="24sp"
        android:textStyle="bold"
        android:gravity="center"
        android:paddingBottom="24dp" />
    
    <!-- Voice Query Section -->
    <Button
        android:id="@+id/btnRecord"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:text="Start Recording"
        android:textSize="18sp"
        android:padding="16dp" />
    
    <TextView
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:text="Or type your question:"
        android:paddingTop="24dp"
        android:paddingBottom="8dp" />
    
    <!-- Text Query Section -->
    <EditText
        android:id="@+id/etQuery"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:hint="e.g., How many locations do we have?"
        android:minHeight="48dp" />
    
    <Button
        android:id="@+id/btnTextQuery"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:text="Send Query"
        android:layout_marginTop="8dp" />
    
    <!-- Loading Indicator -->
    <ProgressBar
        android:id="@+id/progressBar"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_gravity="center"
        android:layout_marginTop="16dp"
        android:visibility="gone" />
    
    <!-- Result Display -->
    <ScrollView
        android:layout_width="match_parent"
        android:layout_height="0dp"
        android:layout_weight="1"
        android:layout_marginTop="24dp">
        
        <TextView
            android:id="@+id/tvResult"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:text="Results will appear here..."
            android:textSize="16sp"
            android:padding="16dp"
            android:background="@android:color/white"
            android:elevation="2dp" />
    </ScrollView>
</LinearLayout>
```

---

## Testing

### 1. Test Transcription Only

```bash
# Using curl (from command line)
curl -X POST https://func-bcvoice-prod.azurewebsites.net/api/transcribe \
  -H "x-functions-key: YOUR_KEY" \
  -F "file=@test_audio.webm"

# Expected response:
"How many locations do we have"
```

### 2. Test Text Query

```bash
curl -X POST https://func-bcvoice-prod.azurewebsites.net/api/query \
  -H "x-functions-key: YOUR_KEY" \
  -H "Content-Type: application/json" \
  -d '{"query": "How many locations do we have?"}'

# Expected response:
"There are 5 locations"
```

### 3. Test Complete Voice Query

```bash
curl -X POST https://func-bcvoice-prod.azurewebsites.net/api/voiceQuery \
  -H "x-functions-key: YOUR_KEY" \
  -F "file=@test_audio.webm"

# Expected response:
"There are 5 locations"
```

---

## Audio Format Requirements

### Supported Formats
- **WebM** (Recommended - best for Android)
- MP3
- WAV
- M4A
- OGG

### Recording Settings (WebM)
```kotlin
setAudioSource(MediaRecorder.AudioSource.MIC)
setOutputFormat(MediaRecorder.OutputFormat.WEBM)
setAudioEncoder(MediaRecorder.AudioEncoder.OPUS)
setAudioSamplingRate(16000)  // 16kHz
setAudioEncodingBitRate(128000)  // 128kbps
```

---

## Error Handling

### Common Errors

| Status Code | Meaning | Solution |
|-------------|---------|----------|
| 401 | Unauthorized | Check function key is correct |
| 400 | Bad Request | Check audio file format |
| 500 | Server Error | Check Azure Function logs in Application Insights |
| 503 | Service Unavailable | Function cold start, retry after 30 seconds |

### Android Error Handling

```kotlin
result.onFailure { error ->
    when (error) {
        is IOException -> {
            // Network error
            showError("Network error. Check internet connection.")
        }
        is HttpException -> {
            // API error
            when (error.code()) {
                401 -> showError("Authentication failed")
                500 -> showError("Server error. Please try again.")
                else -> showError("API error: ${error.message}")
            }
        }
        else -> {
            showError("Unknown error: ${error.message}")
        }
    }
}
```

---

## Security Best Practices

### 1. Store Function Key Securely

**Don't hardcode:**
```kotlin
// ❌ BAD
const val FUNCTION_KEY = "abc123..."
```

**Use BuildConfig or encrypted storage:**
```kotlin
// ✅ GOOD - build.gradle
buildTypes {
    release {
        buildConfigField "String", "FUNCTION_KEY", "\"${project.findProperty('FUNCTION_KEY')}\""
    }
}

// Access in code
val functionKey = BuildConfig.FUNCTION_KEY
```

### 2. Use HTTPS Only
Already configured - Azure Functions use HTTPS by default.

### 3. Implement Timeout
```kotlin
val client = OkHttpClient.Builder()
    .connectTimeout(30, TimeUnit.SECONDS)
    .readTimeout(60, TimeUnit.SECONDS)
    .writeTimeout(60, TimeUnit.SECONDS)
    .build()
```

---

## Monitoring

### View Logs in Azure Portal
1. Go to Function App: `func-bcvoice-prod`
2. Click: Application Insights → appi-bcvoice-prod-6lwg2qhbnsydo
3. Click: Logs
4. Query recent requests:
```kusto
requests
| where timestamp > ago(1h)
| where operation_Name == "voiceQuery"
| project timestamp, resultCode, duration, customDimensions
```

---

## Example User Flow

1. **User opens Android app**
2. **Taps "Start Recording"** button
3. **Speaks:** "How many locations do we have?"
4. **Taps "Stop & Send"** button
5. **App shows:** Loading spinner
6. **Azure Function:**
   - Receives audio file
   - Transcribes to text: "How many locations do we have?"
   - Sends to BC Voice Command API
   - BC queries OData
   - Returns: "There are 5 locations"
7. **App displays:** "There are 5 locations"

**Total time:** 2-4 seconds

---

## Cost Estimate

### Azure Consumption Plan
- **Free tier:** 1 million requests/month
- **After free tier:** $0.20 per million requests
- **Your usage:** ~$0 for typical usage

### Example: 1,000 queries/day = 30,000/month
- Cost: **FREE** (well within free tier)

---

## Next Steps

1. ✅ Azure Function deployed and working
2. ⬜ Get function key from Azure Portal
3. ⬜ Create Android Studio project
4. ⬜ Add dependencies and permissions
5. ⬜ Implement audio recording
6. ⬜ Implement API client
7. ⬜ Build UI
8. ⬜ Test with real device
9. ⬜ Deploy to users

---

## Support

**If Android app shows errors:**
1. Check Application Insights logs in Azure Portal
2. Verify function key is correct
3. Test endpoint with curl/Postman first
4. Check audio file size (<10MB)
5. Verify internet connectivity

**Function App Status:**
https://func-bcvoice-prod.azurewebsites.net/api/health (if health endpoint exists)

---

## Summary

✅ **Azure Function ready** for Android integration  
✅ **Simple API** - just POST audio file  
✅ **Fast response** - 2-4 seconds typical  
✅ **Free tier** - no cost for typical usage  
✅ **Production ready** - includes logging and monitoring  

The Android app just needs to:
1. Record audio (WebM format)
2. POST to `/api/voiceQuery`
3. Display response text

That's it! 🎉
