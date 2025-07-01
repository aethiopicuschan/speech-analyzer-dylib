@preconcurrency import AVFoundation
import AVFoundation
import Foundation
import Speech

/// Type alias for a C-style callback function that receives a C string and user data pointer.
public typealias TranscriptionCallback = @convention(c) (UnsafePointer<CChar>?, UnsafeRawPointer?)
    -> Void

// MARK: --- File Transcription ------------------------------------------------

@available(macOS 26.0, *)
@_cdecl("sw_transcribeFile")
public func sw_transcribeFile(
    cFilePath: UnsafePointer<CChar>?,
    /// C string representing the file path to transcribe
    cLocale: UnsafePointer<CChar>?,
    /// C string representing the locale identifier
    callback: TranscriptionCallback?,
    /// Callback to receive transcript or error message
    userData: UnsafeRawPointer?/// Pointer to user-defined data passed through callback
) -> Int32 {
    guard let cFilePath = cFilePath else { return -1 }
    let fileURL = URL(fileURLWithPath: String(cString: cFilePath))
    let locale = cLocale.flatMap { Locale(identifier: String(cString: $0)) } ?? .current

    // Launch asynchronous transcription task
    Task {
        do {
            let text = try await transcribeFile(from: fileURL, locale: locale)
            text.withCString { ptr in
                if let cb = callback { cb(ptr, userData) }
            }
        } catch {
            let msg = "Error: \(error)"
            msg.withCString { ptr in
                if let cb = callback { cb(ptr, userData) }
            }
        }
    }
    return 0
}

@available(macOS 26.0, *)
/// Transcribes the audio file at the given URL asynchronously using the specified locale.
/// - Parameters:
///   - url: The file URL of the audio to transcribe.
///   - locale: The locale to use for transcription.
/// - Returns: The full transcription as a String.
private func transcribeFile(from url: URL, locale: Locale) async throws -> String {
    let transcriber = SpeechTranscriber(locale: locale, preset: .offlineTranscription)
    var resultText = ""

    // Aggregate results (errors are propagated to the caller)
    let collect = Task.detached {
        for try await r in transcriber.results {
            let s = String(r.text.characters)
            resultText += s
        }
        return resultText
    }

    let audioFile = try AVAudioFile(forReading: url)
    let analyzer = SpeechAnalyzer(modules: [transcriber])
    if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
        try await analyzer.finalizeAndFinish(through: lastSample)
    }

    _ = try await collect.value
    return resultText
}

// MARK: --- Raw data Transcription ------------------------------------------------

@available(macOS 26.0, *)
@_cdecl("sw_transcribeData")
public func sw_transcribeData(
    bytes: UnsafePointer<UInt8>?,
    size: Int,
    /// Number of bytes in the audio data buffer
    cLocale: UnsafePointer<CChar>?,
    /// C string representing the locale identifier
    callback: TranscriptionCallback?,
    /// Callback to receive the transcript or error message
    userData: UnsafeRawPointer?
) -> Int32 {
    // Ensure we have valid audio data
    guard let bytes = bytes, size > 0 else { return -1 }

    // Convert the raw bytes into a Data object
    let audioData = Data(bytes: bytes, count: size)
    // Determine the locale (fallback to current)
    let locale = cLocale.flatMap { Locale(identifier: String(cString: $0)) } ?? .current

    Task {
        // Create a temporary file URL
        let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("tmp")
        do {
            // Write the audio data to disk
            try audioData.write(to: tmpURL)
            // Transcribe using the existing file-based function
            let text = try await transcribeFile(from: tmpURL, locale: locale)
            // Return the result via the callback
            text.withCString { ptr in
                if let cb = callback { cb(ptr, userData) }
            }
        } catch {
            // Convert any error to a string and return it
            let msg = "Error: \(error)"
            msg.withCString { ptr in
                if let cb = callback { cb(ptr, userData) }
            }
        }
        // Clean up the temporary file
        try? FileManager.default.removeItem(at: tmpURL)
    }

    return 0
}

// MARK: --- Microphone Transcription ------------------------------------------

@available(macOS 26.0, *)
@_cdecl("sw_startMicrophoneTranscription")
public func sw_startMicrophoneTranscription(
    cLocale: UnsafePointer<CChar>?,
    /// C string locale identifier
    callback: TranscriptionCallback?,
    /// Callback to receive live transcripts or errors
    userData: UnsafeRawPointer?/// Pointer to user-defined data passed through callback
) -> Int32 {
    let locale = cLocale.flatMap { Locale(identifier: String(cString: $0)) } ?? .current

    // Launch asynchronous microphone transcription task
    Task {
        do {
            try await transcribeMicrophone(locale: locale, callback: callback, userData: userData)
        } catch {
            let msg = "Error: \(error)"
            msg.withCString { ptr in
                if let cb = callback { cb(ptr, userData) }
            }
        }
    }
    return 0
}

@available(macOS 26.0, *)
/// Performs live transcription from the microphone asynchronously, streaming results via callback.
/// - Parameters:
///   - locale: The locale to use for transcription.
///   - callback: C callback to receive partial transcripts or errors.
///   - userData: User data pointer forwarded to callback.
private func transcribeMicrophone(
    locale: Locale,
    callback: TranscriptionCallback?,
    userData: UnsafeRawPointer?
) async throws {
    let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveLiveTranscription)

    // Verify that the locale is supported
    guard
        await SpeechTranscriber.supportedLocales.contains(where: {
            $0.identifier == locale.identifier
        })
    else {
        throw NSError(
            domain: "SpeechWrapper",
            code: -2,
            userInfo: [NSLocalizedDescriptionKey: "Locale not supported"]
        )
    }

    // Download and install model if not already installed
    let isInstalled = await SpeechTranscriber.installedLocales.contains {
        $0.identifier == locale.identifier
    }
    if !isInstalled {
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]
        ) {
            try await request.downloadAndInstall()
        }
    }

    // Obtain the best available audio format compatible with our transcriber module
    guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
    else {
        throw NSError(
            domain: "SpeechWrapper",
            code: -3,
            userInfo: [NSLocalizedDescriptionKey: "Failed to obtain audio format"]
        )
    }

    let engine = AVAudioEngine()
    let inputFormat = engine.inputNode.outputFormat(forBus: 0)
    // Create an audio converter from the input format to the desired analysis format
    guard let converter = AVAudioConverter(from: inputFormat, to: format) else {
        throw NSError(
            domain: "SpeechWrapper",
            code: -4,
            userInfo: [NSLocalizedDescriptionKey: "Failed to create audio converter"]
        )
    }

    // Create asynchronous stream to feed analyzer with converted audio buffers
    let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
    let analyzer = SpeechAnalyzer(modules: [transcriber])
    engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
        Task {
            // Create output PCM buffer matching the analysis format
            guard
                let pcmBuf = AVAudioPCMBuffer(
                    pcmFormat: format,
                    frameCapacity: AVAudioFrameCount(buffer.frameLength))
            else { return }
            var error: NSError?
            // Perform synchronous format conversion
            converter.convert(to: pcmBuf, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            // Yield AnalyzerInput using designated initializer
            continuation.yield(
                AnalyzerInput(buffer: pcmBuf, bufferStartTime: nil)
            )
        }
    }

    // Start audio engine and begin analysis
    try engine.start()
    try await analyzer.start(inputSequence: stream)

    // Stream transcription results back via callback
    for try await result in transcriber.results {
        let plain = String(result.text.characters)
        plain.withCString { ptr in
            if let cb = callback { cb(ptr, userData) }
        }
    }

    // Stop engine and finalize analysis when input ends
    engine.stop()
    try? await analyzer.finalizeAndFinishThroughEndOfInput()
}
