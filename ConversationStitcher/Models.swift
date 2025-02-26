import SwiftUI
import Vision

// MARK: - Data Models

// Raw OCR result from a screenshot
public struct OCRResult {
    public let text: String
    public let boundingBox: CGRect
    public let confidence: Float
    public let pageIndex: Int
    public let originalObservation: VNRecognizedTextObservation?
    
    public init(text: String, boundingBox: CGRect, confidence: Float, pageIndex: Int, originalObservation: VNRecognizedTextObservation?) {
        self.text = text
        self.boundingBox = boundingBox
        self.confidence = confidence
        self.pageIndex = pageIndex
        self.originalObservation = originalObservation
    }
}

// Message metadata to track timestamps and cleaned content
public struct MessageMetadata {
    public let timestamp: Date?
    public let timestampString: String?
    public let isSystemMessage: Bool
    public let artifactsRemoved: [String]  // For debugging, track what was cleaned
    
    public init(timestamp: Date?, timestampString: String?, isSystemMessage: Bool, artifactsRemoved: [String]) {
        self.timestamp = timestamp
        self.timestampString = timestampString
        self.isSystemMessage = isSystemMessage
        self.artifactsRemoved = artifactsRemoved
    }
}

// Message bubble model for intermediate processing
public struct MessageBubble {
    public let text: String
    public let boundingBox: CGRect
    public let pageIndex: Int
    public let position: BubblePosition // left, right, or center
    public let isLikelyFromUser: Bool
    public let metadata: MessageMetadata
    
    public enum BubblePosition {
        case left
        case right 
        case center
    }
    
    public init(text: String, boundingBox: CGRect, pageIndex: Int, position: BubblePosition, isLikelyFromUser: Bool, metadata: MessageMetadata) {
        self.text = text
        self.boundingBox = boundingBox
        self.pageIndex = pageIndex
        self.position = position
        self.isLikelyFromUser = isLikelyFromUser
        self.metadata = metadata
    }
}

// Final message model for display
public struct Message: Identifiable {
    public let id = UUID()
    public let text: String
    public let isFromUser: Bool
    public let originalPosition: CGRect
    public let originalPageIndex: Int
    public var chronologicalIndex: Int = 0  // For sorting in the final timeline
    public var metadata: MessageMetadata?
    
    public init(text: String, isFromUser: Bool, originalPosition: CGRect, originalPageIndex: Int, metadata: MessageMetadata? = nil) {
        self.text = text
        self.isFromUser = isFromUser
        self.originalPosition = originalPosition
        self.originalPageIndex = originalPageIndex
        self.metadata = metadata
    }
}

// Screenshot metadata for better ordering
public struct ScreenshotMetadata {
    public let pageIndex: Int
    public let earliestTimestamp: Date?
    public let latestTimestamp: Date?
    public let bottomMessages: [OCRResult]
    public let topMessages: [OCRResult]
    public var overlapsWithPages: [Int] = []
    public var chronologicalRank: Int = 0
    
    public init(pageIndex: Int, earliestTimestamp: Date?, latestTimestamp: Date?, bottomMessages: [OCRResult], topMessages: [OCRResult]) {
        self.pageIndex = pageIndex
        self.earliestTimestamp = earliestTimestamp
        self.latestTimestamp = latestTimestamp
        self.bottomMessages = bottomMessages
        self.topMessages = topMessages
    }
}

// Helper struct for holding messages with their positions
struct MessageWithPosition {
    let text: String
    let boundingBox: CGRect
    let pageIndex: Int
    let originalObservation: VNRecognizedTextObservation?
}

// Stores data for a screenshot and its analyzed messages
struct ScreenshotData {
    let image: UIImage
    let messages: [MessageWithPosition]
    var chronologicalRank: Int = 0  // Lower value = earlier in time
    var overlapsWithScreenshots: [Int] = []  // Indices of screenshots that have overlap with this one
} 