import AVFoundation
import Foundation
import SwiftUI

enum TranscriptionError: LocalizedError {
    case couldNotDownloadModel
    case failedToSetupRecognitionStream
    case invalidAudioDataType
    case localeNotSupported
    case noInternetForModelDownload
    case audioFilePathNotFound
    case speechRecognitionNotAuthorized

    var errorDescription: String? {
        switch self {
        case .couldNotDownloadModel:
            return "Could not download the model."
        case .failedToSetupRecognitionStream:
            return "Could not set up the speech recognition stream."
        case .invalidAudioDataType:
            return "Unsupported audio format."
        case .localeNotSupported:
            return "This locale is not yet supported by SpeechAnalyzer."
        case .noInternetForModelDownload:
            return "The model could not be downloaded because the user is not connected to internet."
        case .audioFilePathNotFound:
            return "Couldn't write audio to file."
        case .speechRecognitionNotAuthorized:
            return "Speech recognition access is required. Please enable it in Settings > Privacy & Security > Speech Recognition."
        }
    }

    var descriptionString: String {
        return errorDescription ?? "Unknown error"
    }
}

extension AVAudioPlayerNode {
    var currentTime: TimeInterval {
        guard let nodeTime: AVAudioTime = self.lastRenderTime,
              let playerTime: AVAudioTime = self.playerTime(forNodeTime: nodeTime)
        else { return 0 }
        return Double(playerTime.sampleTime) / playerTime.sampleRate
    }
}
