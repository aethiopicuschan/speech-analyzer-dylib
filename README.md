# Speech Analyzer Dylib

[![License: MIT](https://img.shields.io/badge/License-MIT-brightgreen?style=flat-square)](/LICENSE)

## Description

Starting with macOS Tahoe, the [SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer) API will be introduced. To make it easier to use, I’ve set up an environment to wrap it into a dylib.

## Features

- **File Transcription**
  Call `sw_transcribeFile(const char *filePath, const char *locale, TranscriptionCallback callback, void *userData)` to transcribe an audio file asynchronously.
  - **Inputs**:
    - `filePath`: C-string path to the audio file
    - `locale`: C-string locale identifier (defaults to current locale if `NULL`)
    - `callback`: C function of type `void (*)(const char *textOrError, void *userData)`
    - `userData`: opaque pointer passed back in each callback
  - **Behavior**:
    - Launches a background task to read and process the file
    - On success, sends the full transcript to your callback
    - On failure, sends an `"Error: …"` string instead
  - **Return**: `0` if the task was started, `-1` if no file path was provided

- **Live Microphone Transcription**
  Call `sw_startMicrophoneTranscription(const char *locale, TranscriptionCallback callback, void *userData)` to begin streaming live speech from the default mic.
  - **Inputs**: same as above, except no file path
  - **Behavior**:
    - Verifies or installs the offline model for the given locale
    - Captures, converts, and analyzes mic audio in real time
    - Streams each partial transcript back via your callback as it arrives
    - Stops and finalizes automatically when the audio engine is stopped
  - **Return**: always `0` (task is fire-and-forget)

## How to compile

### Requirements

- macOS 26.0 or later
- Xcode 26.0 or later

### Steps

```sh
swift build -c release
```

Now `.build/arm64-apple-macosx/release/libSpeechAnalyzerWrapper.dylib` and `.build/SpeechAnalyzerWrapper/SpeechAnalyzerWrapper.h` will be generated.
