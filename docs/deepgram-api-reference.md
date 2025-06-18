# Deepgram Speech-to-Text API Reference

## Listen Endpoint

**URL**: `https://api.deepgram.com/v1/listen`  
**Method**: POST

## Authentication

Include your API key in the Authorization header:
```
Authorization: Token YOUR_DEEPGRAM_API_KEY
```

## Request Headers

- `Authorization`: Required. Format: `Token YOUR_API_KEY`
- `Content-Type`: Required. Audio format (e.g., `audio/wav`, `audio/mp4`, `audio/mpeg`)

## Query Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `model` | string | `nova-2` | Model to use for transcription (e.g., `nova-2`, `nova-3`) |
| `language` | string | `en` | BCP-47 language tag |
| `detect_language` | boolean | `false` | Automatically detect the dominant language |
| `punctuate` | boolean | `false` | Add punctuation and capitalization |
| `smart_format` | boolean | `false` | Enhanced formatting (numbers, dates, etc.) |
| `diarize` | boolean | `false` | Recognize speaker changes |
| `multichannel` | boolean | `false` | Transcribe each channel separately |
| `alternatives` | integer | `1` | Number of alternative transcripts |
| `sentiment` | boolean | `false` | Analyze sentiment |
| `summarize` | boolean/string | `false` | Generate summary |
| `topics` | boolean | `false` | Identify topics |
| `intents` | boolean | `false` | Identify intents |

## Request Body

Send the audio file as binary data in the request body.

## Response Format

### Success Response (200 OK)

```json
{
  "metadata": {
    "request_id": "string",
    "sha256": "string",
    "created": "timestamp",
    "duration": number,
    "channels": number,
    "models": ["model_id"],
    "model_info": {
      "model_id": {
        "name": "string",
        "version": "string",
        "arch": "string"
      }
    }
  },
  "results": {
    "channels": [
      {
        "alternatives": [
          {
            "transcript": "string",
            "confidence": number,
            "words": [
              {
                "word": "string",
                "start": number,
                "end": number,
                "confidence": number
              }
            ]
          }
        ]
      }
    ],
    "utterances": [...],
    "summary": {...},
    "sentiments": {...},
    "topics": {...},
    "intents": {...}
  }
}
```

### Error Response

```json
{
  "err_code": "string",
  "err_msg": "string",
  "request_id": "string"
}
```

## Swift Example

```swift
import Foundation

// Specify the URL for the Deepgram API endpoint
let url = URL(string: "https://api.deepgram.com/v1/listen?model=nova-3&smart_format=true&detect_language=true")!

// Read the audio file as binary data
guard let audioData = FileManager.default.contents(atPath: audioFilePath) else {
    print("Error: Unable to read audio file")
    return
}

// Create the URLRequest object
var request = URLRequest(url: url)
request.httpMethod = "POST"

// Set request headers
request.setValue("Token YOUR_DEEPGRAM_API_KEY", forHTTPHeaderField: "Authorization")
request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")

// Set request body with audio data
request.httpBody = audioData

// Create URLSession task to perform the request
let task = URLSession.shared.dataTask(with: request) { data, response, error in
    if let error = error {
        print("Error: \(error)")
        return
    }
    
    guard let httpResponse = response as? HTTPURLResponse, 
          (200...299).contains(httpResponse.statusCode) else {
        print("Error: Invalid response")
        return
    }
    
    if let data = data {
        do {
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            print("Response: \(json)")
        } catch {
            print("Error parsing JSON: \(error)")
        }
    }
}

// Start the URLSession task
task.resume()
```

## Common Error Codes

- `400 Bad Request`: Invalid parameters or audio format
- `401 Unauthorized`: Invalid API key
- `402 Payment Required`: Insufficient credits
- `403 Forbidden`: Access denied
- `413 Payload Too Large`: Audio file too large
- `429 Too Many Requests`: Rate limit exceeded
- `500 Internal Server Error`: Server error

## Audio Format Support

Deepgram supports various audio formats including:
- WAV (audio/wav)
- MP3 (audio/mp3, audio/mpeg)
- MP4 (audio/mp4)
- M4A (audio/mp4)
- FLAC (audio/flac)
- OGG (audio/ogg)
- WebM (audio/webm)

## Best Practices

1. Use appropriate audio quality (16kHz sample rate minimum)
2. Include `smart_format=true` for better formatting
3. Use `detect_language=true` for multi-language support
4. Set appropriate `Content-Type` header matching your audio format
5. Handle errors gracefully with proper error checking

## Rate Limits

Check your account dashboard for specific rate limits. Typical limits:
- Requests per second: Varies by plan
- Maximum file size: 2GB
- Maximum duration: 5 hours per file