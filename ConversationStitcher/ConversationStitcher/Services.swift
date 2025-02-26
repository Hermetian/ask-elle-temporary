import SwiftUI
import Vision

// MARK: - Data Models

// Final message model for display
public struct Message: Identifiable {
    public let id = UUID()
    public let text: String
    public let isFromUser: Bool
    public let originalPosition: CGRect
    public let originalPageIndex: Int
    public var chronologicalIndex: Int = 0  // For sorting in the final timeline
    public var metadata: MessageMetadata?
}

// Raw OCR result from a screenshot
struct OCRResult {
    let text: String
    let boundingBox: CGRect
    let confidence: Float
    let pageIndex: Int
    let originalObservation: VNRecognizedTextObservation?
}

// Message metadata to track timestamps and cleaned content
public struct MessageMetadata {
    public let timestamp: Date?
    public let timestampString: String?
    public let isSystemMessage: Bool
    public let artifactsRemoved: [String]  // For debugging, track what was cleaned
}

// Processed message bubble with position and content information
struct MessageBubble {
    let text: String
    let boundingBox: CGRect
    let pageIndex: Int
    let position: BubblePosition // left, right, or center
    let isLikelyFromUser: Bool
    let metadata: MessageMetadata
    
    enum BubblePosition {
        case left
        case right 
        case center
    }
}

// Screenshot metadata for better ordering
struct ScreenshotMetadata {
    let pageIndex: Int
    let earliestTimestamp: Date?
    let latestTimestamp: Date?
    let bottomMessages: [OCRResult]
    let topMessages: [OCRResult]
    var overlapsWithPages: [Int] = []
    var chronologicalRank: Int = 0
}

// MARK: - Services

// Service for OCR processing
class OCRService {
    
    func recognizeText(in image: UIImage, pageIndex: Int, completion: @escaping ([OCRResult]?, Error?) -> Void) {
        guard let cgImage = image.cgImage else {
            completion(nil, NSError(domain: "ConversationStitcher", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to get CGImage"]))
            return
        }
        
        let request = VNRecognizeTextRequest { request, error in
            if let error = error {
                completion(nil, error)
                return
            }
            
            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                completion(nil, NSError(domain: "ConversationStitcher", code: 2, userInfo: [NSLocalizedDescriptionKey: "No text observations found"]))
                return
            }
            
            var results: [OCRResult] = []
            
            for observation in observations {
                if let recognizedText = observation.topCandidates(1).first {
                    let text = recognizedText.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        results.append(OCRResult(
                            text: text,
                            boundingBox: observation.boundingBox,
                            confidence: recognizedText.confidence,
                            pageIndex: pageIndex,
                            originalObservation: observation
                        ))
                    }
                }
            }
            
            completion(results, nil)
        }
        
        // Configure the recognition level
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US"]
        request.customWords = ["iMessage", "SMS", "MMS"]
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                print("Text recognition error: \(error)")
                completion(nil, error)
            }
        }
    }
}

// Text cleaning and processing service
class TextProcessingService {
    
    func cleanMessageText(_ text: String) -> (cleanedText: String, metadata: MessageMetadata) {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var removedArtifacts: [String] = []
        var timestampString: String? = nil
        
        // Extract timestamp if present
        let timestampPattern = #"\d{1,2}:\d{2}(:\d{2})?\s*(AM|PM|am|pm)?"#
        if let range = result.range(of: timestampPattern, options: .regularExpression) {
            timestampString = String(result[range])
            result = result.replacingOccurrences(of: timestampPattern, with: "", options: .regularExpression)
            removedArtifacts.append("timestamp: \(timestampString ?? "unknown")")
        }
        
        // Remove iMessage indicators
        let iMessagePatterns = [
            "iMessage",
            "Message",
            "Text Message",
            "SMS",
            "MMS",
            "Delivered",
            "Read",
            "Sent",
            "Not Delivered",
            "Today",
            "Yesterday",
            "Last week"
        ]
        
        for pattern in iMessagePatterns {
            if result.contains(pattern) {
                result = result.replacingOccurrences(of: pattern, with: "", options: .caseInsensitive)
                removedArtifacts.append(pattern)
            }
        }
        
        // Additional patterns to clean
        if result.range(of: #"^[•\*\-\s]*"#, options: .regularExpression) != nil {
            result = result.replacingOccurrences(of: #"^[•\*\-\s]*"#, with: "", options: .regularExpression)
            removedArtifacts.append("bullet or list marker")
        }
        
        // Remove common date patterns
        let datePattern = #"(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\.?\s+\d{1,2}(st|nd|rd|th)?(,?\s+\d{2,4})?"#
        if result.range(of: datePattern, options: .regularExpression) != nil {
            result = result.replacingOccurrences(of: datePattern, with: "", options: .regularExpression)
            removedArtifacts.append("date")
        }
        
        // Trim again after all the replacements
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Determine if this is likely a system message
        let isSystemMessage = isMetadata(text)
        
        return (
            cleanedText: result,
            metadata: MessageMetadata(
                timestamp: parseTimestamp(timestampString),
                timestampString: timestampString,
                isSystemMessage: isSystemMessage,
                artifactsRemoved: removedArtifacts
            )
        )
    }
    
    func isMetadata(_ text: String) -> Bool {
        let lowercaseText = text.lowercased()
        let metadataKeywords = [
            "imessage", "message", "text message", "sms", "mms", "delivered", "read", "sent",
            "today", "yesterday", "last week", "now", "edited", "delete", "notification",
            "typing", "seen", "read receipt", "read at", "received", "sent with", "via"
        ]
        
        for keyword in metadataKeywords {
            if lowercaseText.contains(keyword) {
                return true
            }
        }
        
        // Check for standalone timestamp-like patterns
        if lowercaseText.range(of: #"^\d{1,2}:\d{2}(:\d{2})?\s*(am|pm)?$"#, options: .regularExpression) != nil {
            return true
        }
        
        return false
    }
    
    func parseTimestamp(_ timestampString: String?) -> Date? {
        guard let timestampString = timestampString else { return nil }
        
        // Parse time components
        let components = timestampString.components(separatedBy: ":")
        guard components.count >= 2 else { return nil }
        
        guard let hourStr = components.first,
              let hour = Int(hourStr),
              let minuteStr = components[1].components(separatedBy: CharacterSet.decimalDigits.inverted).first,
              let minute = Int(minuteStr) else {
            return nil
        }
        
        var adjustedHour = hour
        
        // Handle AM/PM
        let lowercasedTime = timestampString.lowercased()
        if lowercasedTime.contains("pm") && hour < 12 {
            adjustedHour += 12
        } else if lowercasedTime.contains("am") && hour == 12 {
            adjustedHour = 0
        }
        
        // Create date components for today with the parsed time
        var dateComponents = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        dateComponents.hour = adjustedHour
        dateComponents.minute = minute
        
        return Calendar.current.date(from: dateComponents)
    }
    
    func isLikelyUserMessage(_ text: String) -> Bool {
        let lowercasedText = text.lowercased()
        let userIndicators = ["i ", "i'm ", "i'll ", "i've ", "i'd ", "me ", "my ", "mine ", "myself "]
        
        for indicator in userIndicators {
            if lowercasedText.contains(indicator) {
                return true
            }
        }
        
        return false
    }
    
    func messagesMatch(_ text1: String, _ text2: String) -> Bool {
        let cleanText1 = cleanText(text1)
        let cleanText2 = cleanText(text2)
        
        // Simple string similarity check
        return cleanText1 == cleanText2 || 
               cleanText1.contains(cleanText2) || 
               cleanText2.contains(cleanText1)
    }
    
    func cleanText(_ text: String) -> String {
        let (cleanedText, _) = cleanMessageText(text)
        return cleanedText
    }
}

// Message classification and ordering service 
class MessageProcessingService {
    private let textProcessor = TextProcessingService()
    
    func classifyBubbles(from ocrResults: [OCRResult]) -> [MessageBubble] {
        var bubbles: [MessageBubble] = []
        
        for result in ocrResults {
            // Clean the text and extract metadata
            let (cleanedText, metadata) = textProcessor.cleanMessageText(result.text)
            
            // Skip if empty after cleaning or if it's a system message with no content
            if cleanedText.isEmpty || (metadata.isSystemMessage && cleanedText.count < 3) {
                continue
            }
            
            // Determine bubble position based on horizontal location
            let position = determineBubblePosition(result.boundingBox)
            
            // Determine if likely from user based on position and content
            let isLikelyFromUser: Bool
            if position == .right {
                isLikelyFromUser = true
            } else if position == .left {
                isLikelyFromUser = false
            } else {
                // For center bubbles, try to determine from content
                isLikelyFromUser = textProcessor.isLikelyUserMessage(cleanedText)
            }
            
            bubbles.append(MessageBubble(
                text: cleanedText,
                boundingBox: result.boundingBox,
                pageIndex: result.pageIndex,
                position: position,
                isLikelyFromUser: isLikelyFromUser,
                metadata: metadata
            ))
        }
        
        return bubbles
    }
    
    func determineBubblePosition(_ boundingBox: CGRect) -> MessageBubble.BubblePosition {
        let screenMidPoint: CGFloat = 0.5 // Normalized width midpoint
        let messageCenterX = boundingBox.midX
        
        if messageCenterX < (screenMidPoint - 0.15) {
            return .left
        } else if messageCenterX > (screenMidPoint + 0.15) {
            return .right
        } else {
            return .center
        }
    }
    
    func sortBubblesWithinPage(_ bubbles: [MessageBubble]) -> [MessageBubble] {
        // Sort by vertical position, top to bottom
        return bubbles.sorted {
            // VNRecognizedTextObservation uses coordinate system where 0,0 is bottom-left
            return 1.0 - $0.boundingBox.origin.y < 1.0 - $1.boundingBox.origin.y
        }
    }
    
    func getTopMessages(from messages: [OCRResult]) -> [OCRResult] {
        // Get the top 3 messages from the array
        let sortedMessages = messages.sorted { 
            // VNRecognizedTextObservation uses coordinate system where 0,0 is bottom-left
            return 1.0 - $0.boundingBox.origin.y < 1.0 - $1.boundingBox.origin.y
        }
        
        return Array(sortedMessages.prefix(min(3, sortedMessages.count)))
    }
    
    func getBottomMessages(from messages: [OCRResult]) -> [OCRResult] {
        // Get the bottom 3 messages from the array
        let sortedMessages = messages.sorted { 
            // VNRecognizedTextObservation uses coordinate system where 0,0 is bottom-left
            return 1.0 - $0.boundingBox.origin.y > 1.0 - $1.boundingBox.origin.y
        }
        
        return Array(sortedMessages.prefix(min(3, sortedMessages.count)))
    }
    
    func analyzeScreenshotForOverlap(_ ocrResults: [OCRResult]) -> ScreenshotMetadata {
        let pageIndex = ocrResults.first?.pageIndex ?? 0
        
        // Find timestamps if available
        var earliestTimestamp: Date? = nil
        var latestTimestamp: Date? = nil
        
        for result in ocrResults {
            let (_, metadata) = textProcessor.cleanMessageText(result.text)
            if let timestamp = metadata.timestamp {
                if earliestTimestamp == nil || timestamp < earliestTimestamp! {
                    earliestTimestamp = timestamp
                }
                if latestTimestamp == nil || timestamp > latestTimestamp! {
                    latestTimestamp = timestamp
                }
            }
        }
        
        return ScreenshotMetadata(
            pageIndex: pageIndex,
            earliestTimestamp: earliestTimestamp,
            latestTimestamp: latestTimestamp,
            bottomMessages: getBottomMessages(from: ocrResults),
            topMessages: getTopMessages(from: ocrResults)
        )
    }
}

// Conversation Stitching Service - orchestrates the entire process
public class ConversationStitchingService {
    private let ocrService = OCRService()
    private let textProcessor = TextProcessingService()
    private let messageProcessor = MessageProcessingService()
    
    // Process screenshots and return stitched messages
    public func processScreenshots(_ images: [UIImage], completion: @escaping ([Message]?, Error?) -> Void) {
        guard !images.isEmpty else {
            completion([], nil)
            return
        }
        
        let group = DispatchGroup()
        var allOCRResults: [OCRResult] = []
        var errors: [Error] = []
        
        // Step 1: Process each screenshot with OCR
        for (index, image) in images.enumerated() {
            group.enter()
            
            ocrService.recognizeText(in: image, pageIndex: index) { results, error in
                defer { group.leave() }
                
                if let error = error {
                    errors.append(error)
                } else if let results = results {
                    allOCRResults.append(contentsOf: results)
                }
            }
        }
        
        // Once all OCR is complete, process and stitch
        group.notify(queue: .main) {
            if allOCRResults.isEmpty && !errors.isEmpty {
                completion(nil, errors.first)
                return
            }
            
            // Step 2: Create screenshot metadata for ordering
            let screenshotMetadata = self.createScreenshotMetadata(allOCRResults, images.count)
            
            // Step 3: Determine overlap and ordering
            let orderedScreenshots = self.determineScreenshotOrder(screenshotMetadata)
            
            // Step 4: Process messages in order
            let messages = self.processMessagesInOrder(allOCRResults, orderedScreenshots)
            
            completion(messages, nil)
        }
    }
    
    private func createScreenshotMetadata(_ results: [OCRResult], _ imageCount: Int) -> [ScreenshotMetadata] {
        // Group results by page
        let resultsByPage = Dictionary(grouping: results) { $0.pageIndex }
        
        // Create metadata for each page
        var metadata: [ScreenshotMetadata] = []
        
        for pageIndex in 0..<imageCount {
            if let pageResults = resultsByPage[pageIndex] {
                metadata.append(messageProcessor.analyzeScreenshotForOverlap(pageResults))
            } else {
                // Empty page
                metadata.append(ScreenshotMetadata(
                    pageIndex: pageIndex,
                    earliestTimestamp: nil,
                    latestTimestamp: nil, 
                    bottomMessages: [],
                    topMessages: []
                ))
            }
        }
        
        return metadata
    }
    
    private func determineScreenshotOrder(_ metadata: [ScreenshotMetadata]) -> [ScreenshotMetadata] {
        var result = metadata
        
        // Find overlaps
        for i in 0..<result.count {
            for j in 0..<result.count where i != j {
                if screenshotsOverlap(result[i], result[j]) {
                    result[i].overlapsWithPages.append(j)
                }
            }
        }
        
        // Determine chronological order based on:
        // 1. Timestamps
        // 2. Content overlap
        for i in 0..<result.count {
            for j in 0..<result.count where i != j {
                // Timeline based on timestamps
                if let latestI = result[i].latestTimestamp, 
                   let earliestJ = result[j].earliestTimestamp {
                    if latestI < earliestJ {
                        // i comes before j
                        result[i].chronologicalRank -= 1
                        result[j].chronologicalRank += 1
                    }
                }
                
                // Check bottom-to-top overlap
                for message1 in result[i].bottomMessages {
                    for message2 in result[j].topMessages {
                        if self.messagesMatch(message1.text, message2.text) {
                            // i likely comes before j
                            result[i].chronologicalRank -= 1
                            result[j].chronologicalRank += 1
                        }
                    }
                }
            }
        }
        
        // Sort by chronological rank
        return result.sorted { $0.chronologicalRank < $1.chronologicalRank }
    }
    
    private func screenshotsOverlap(_ metadata1: ScreenshotMetadata, _ metadata2: ScreenshotMetadata) -> Bool {
        // Check for content overlap in either direction
        for message1 in metadata1.bottomMessages {
            for message2 in metadata2.topMessages {
                if self.messagesMatch(message1.text, message2.text) {
                    return true
                }
            }
        }
        
        for message1 in metadata1.topMessages {
            for message2 in metadata2.bottomMessages {
                if self.messagesMatch(message1.text, message2.text) {
                    return true
                }
            }
        }
        
        return false
    }
    
    private func processMessagesInOrder(_ results: [OCRResult], _ orderedScreenshots: [ScreenshotMetadata]) -> [Message] {
        var allMessages: [Message] = []
        var chronologicalIndex = 0
        
        // Group results by page
        let resultsByPage = Dictionary(grouping: results) { $0.pageIndex }
        
        // Process each page in determined order
        for metadata in orderedScreenshots {
            if let pageResults = resultsByPage[metadata.pageIndex] {
                // Classify and clean
                let bubbles = messageProcessor.classifyBubbles(from: pageResults)
                
                // Sort within page
                let sortedBubbles = messageProcessor.sortBubblesWithinPage(bubbles)
                
                // Convert to messages
                for bubble in sortedBubbles {
                    let message = Message(
                        text: bubble.text,
                        isFromUser: bubble.isLikelyFromUser,
                        originalPosition: bubble.boundingBox,
                        originalPageIndex: bubble.pageIndex,
                        chronologicalIndex: chronologicalIndex,
                        metadata: bubble.metadata
                    )
                    chronologicalIndex += 1
                    allMessages.append(message)
                }
            }
        }
        
        // Remove duplicates
        return removeDuplicates(allMessages)
    }
    
    private func removeDuplicates(_ messages: [Message]) -> [Message] {
        var uniqueMessages: [Message] = []
        var seenTexts = Set<String>()
        
        for message in messages {
            let normalizedText = message.text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalizedText.isEmpty && !seenTexts.contains(normalizedText) {
                seenTexts.insert(normalizedText)
                uniqueMessages.append(message)
            }
        }
        
        return uniqueMessages
    }
} 