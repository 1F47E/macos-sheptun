# Speech to Text API Documentation
[View on OpenAI Platform](https://platform.openai.com/docs/guides/speech-to-text?lang=curl)

## Overview
Learn how to turn audio into text. The Audio API provides two speech to text endpoints:

- transcriptions
- translations

Historically, both endpoints have been backed by our open source Whisper model (whisper-1). The transcriptions endpoint now also supports higher quality model snapshots, with limited parameter support:

- gpt-4o-mini-transcribe
- gpt-4o-transcribe

All endpoints can be used to:
- Transcribe audio into whatever language the audio is in
- Translate and transcribe the audio into English

File uploads are currently limited to 25 MB, and the following input file types are supported: mp3, mp4, mpeg, mpga, m4a, wav, and webm.

## Quickstart

### Transcriptions

The transcriptions API takes as input the audio file you want to transcribe and the desired output file format for the transcription of the audio. All models support the same set of input formats. On output, whisper-1 supports a range of formats (json, text, srt, verbose_json, vtt); the newer gpt-4o-mini-transcribe and gpt-4o-transcribe snapshots currently only support json or plain text responses.

Transcribe audio
```
curl --request POST \
--url https://api.openai.com/v1/audio/transcriptions \
--header "Authorization: Bearer $OPENAI_API_KEY" \
--header 'Content-Type: multipart/form-data' \
--form file=@/path/to/file/audio.mp3 \
--form model=whisper-1
```

By default, the response type will be json with the raw text included.


```
{
  "text": "Imagine the wildest idea that you've ever had, and you're curious about how it might scale to something that's a 100, a 1,000 times bigger.
....
}
```

The Audio API also allows you to set additional parameters in a request. For example, if you want to set the response_format as text, your request would look like the following:

### Additional options
=
```
curl --request POST \
--url https://api.openai.com/v1/audio/transcriptions \
--header "Authorization: Bearer $OPENAI_API_KEY" \
--header 'Content-Type: multipart/form-data' \
--form file=@/path/to/file/speech.mp3 \
--form model=whisper-1 \
--form response_format=text
```

The API Reference includes the full list of available parameters.

The newer gpt-4o-mini-transcribe and gpt-4o-transcribe models currently have a limited parameter surface: they only support json or text response formats. Other parameters, such as timestamp_granularities, require verbose_json output and are therefore only available when using whisper-1.

Translations
The translations API takes as input the audio file in any of the supported languages and transcribes, if necessary, the audio into English. This differs from our /Transcriptions endpoint since the output is not in the original input language and is instead translated to English text. This endpoint supports only the whisper-1 model.

## Translate audio

```
curl --request POST \
--url https://api.openai.com/v1/audio/translations \
--header "Authorization: Bearer $OPENAI_API_KEY" \
--header 'Content-Type: multipart/form-data' \
--form file=@/path/to/file/german.mp3 \
--form model=whisper-1 \
```

In this case, the inputted audio was german and the outputted text looks like:

Hello, my name is Wolfgang and I come from Germany. Where are you heading today?
We only support translation into English at this time.

Supported languages
We currently support the following languages through both the transcriptions and translations endpoint:

Afrikaans, Arabic, Armenian, Azerbaijani, Belarusian, Bosnian, Bulgarian, Catalan, Chinese, Croatian, Czech, Danish, Dutch, English, Estonian, Finnish, French, Galician, German, Greek, Hebrew, Hindi, Hungarian, Icelandic, Indonesian, Italian, Japanese, Kannada, Kazakh, Korean, Latvian, Lithuanian, Macedonian, Malay, Marathi, Maori, Nepali, Norwegian, Persian, Polish, Portuguese, Romanian, Russian, Serbian, Slovak, Slovenian, Spanish, Swahili, Swedish, Tagalog, Tamil, Thai, Turkish, Ukrainian, Urdu, Vietnamese, and Welsh.

While the underlying model was trained on 98 languages, we only list the languages that exceeded <50% word error rate (WER) which is an industry standard benchmark for speech to text model accuracy. The model will return results for languages not listed above but the quality will be low.

We support some ISO 639-1 and 639-3 language codes for GPT-4o based models. For language codes we don’t have, try prompting for specific languages (i.e., “Output in English”).

