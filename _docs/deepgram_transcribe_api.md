https://developers.deepgram.com/reference/speech-to-text-api/listen


models

string or optional enum
Optional
AI model used to process submitted audio

nova-3
nova-3-general
nova-3-medical
nova-2
nova-2-general
nova-2-meeting
nova-2-finance
nova-2-conversationalai
nova-2-voicemail
nova-2-video
nova-2-medical
nova-2-drivethru
nova-2-automotive
nova
nova-general
nova-phonecall
nova-medical
enhanced
enhanced-general
enhanced-meeting
enhanced-phonecall
enhanced-finance
base
meeting
phonecall
finance
conversationalai
voicemail
video



detect_language
boolean
Optional
Defaults to false
Identifies the dominant language spoken in submitted audio


language
enum
Optional
Defaults to en
The BCP-47 language tag that hints at the primary spoken language. Depending on the Model and API endpoint you choose only certain languages are available






import Foundation
// Specify the URL for the Deepgram API endpoint let url = URL(string: "https://api.deepgram.com/v1/listen")!
// Specify the path to the audio file let audioFilePath = "/path/to/youraudio.wav"
// Read the audio file as binary data guard let audioData = FileManager.default.contents(atPath: audioFilePath) else {
    print("Error: Unable to read audio file")
    exit(1)
}
// Create the URLRequest object var request = URLRequest(url: url) request.httpMethod = "POST"
// Set request headers request.setValue("Token DEEPGRAM_API_KEY", forHTTPHeaderField: "Authorization") // Replace YOUR_DEEPGRAM_API_KEY with your actual API key request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
// Set request body with audio data request.httpBody = audioData
// Create URLSession task to perform the request let task = URLSession.shared.dataTask(with: request) { data, response, error in
    if let error = error {
        print("Error: \(error)")
        return
    }

    guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
        print("Error: Invalid response")
        return
    }

    if let data = data {
        if let responseBody = String(data: data, encoding: .utf8) {
            print("Response: \(responseBody)")
        } else {
            print("Error: Unable to parse response body")
        }
    } else {
        print("Error: No response data")
    }
}
// Start the URLSession task task.resume()
// Keep the program running until the URLSession task completes RunLoop.main.run()



response
{
  "metadata": {
    "request_id": "a847f427-4ad5-4d67-9b95-db801e58251c",
    "sha256": "154e291ecfa8be6ab8343560bcc109008fa7853eb5372533e8efdefc9b504c33",
    "created": "2024-05-12T18:57:13Z",
    "duration": 25.933313,
    "channels": 1,
    "models": [
      "30089e05-99d1-4376-b32e-c263170674af"
    ],
    "model_info": {
      "30089e05-99d1-4376-b32e-c263170674af": {
        "name": "2-general-nova",
        "version": "2024-01-09.29447",
        "arch": "nova-2"
      }
    },
    "summary_info": {
      "model_uuid": "67875a7f-c9c4-48a0-aa55-5bdb8a91c34a",
      "input_tokens": 95,
      "output_tokens": 63
    },
    "sentiment_info": {
      "model_uuid": "80ab3179-d113-4254-bd6b-4a2f96498695",
      "input_tokens": 105,
      "output_tokens": 105
    },
    "topics_info": {
      "model_uuid": "80ab3179-d113-4254-bd6b-4a2f96498695",
      "input_tokens": 105,
      "output_tokens": 7
    },
    "intents_info": {
      "model_uuid": "80ab3179-d113-4254-bd6b-4a2f96498695",
      "input_tokens": 105,
      "output_tokens": 4
    },
    "tags": [
      "test"
    ],
    "transaction_key": "transaction_key"
  },
  "results": {
    "channels": [
      {}
    ],
    "utterances": [
      {}
    ],
    "summary": {
      "result": "success",
      "short": "Speaker 0 discusses the significance of the first all-female spacewalk with an all-female team, stating that it is a tribute to the skilled and qualified women who were denied opportunities in the past."
    },
    "sentiments": {
      "segments": [
        {
          "text": "Yeah. As as much as, um, it's worth celebrating, uh, the first, uh, spacewalk, um, with an all-female team, I think many of us are looking forward to it just being normal. And, um, I think if it signifies anything, it is, uh, to honor the the women who came before us who, um, were skilled and qualified, um, and didn't get the the same opportunities that we have today.",
          "start_word": 0,
          "end_word": 69,
          "sentiment": "positive",
          "sentiment_score": 0.5810546875
        }
      ],
      "average": {
        "sentiment": "positive",
        "sentiment_score": 0.5810185185185185
      }
    }
  }
}
