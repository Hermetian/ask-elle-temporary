import SwiftUI
import Vision
import Foundation
import UIKit

// MARK: - Services

// Service for OCR processing
public class OCRService {
    
    public func recognizeText(in image: UIImage, pageIndex: Int, completion: @escaping ([OCRResult]?, Error?) -> Void) {
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

// Service for text cleaning and processing
public class TextProcessingService {
    
    public static let shared = TextProcessingService()
    
    public func cleanMessageText(_ text: String) -> (cleanedText: String, metadata: MessageMetadata) {
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
    
    public func isMetadata(_ text: String) -> Bool {
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
    
    public func parseTimestamp(_ timestampString: String?) -> Date? {
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
    
    public func isLikelyUserMessage(_ text: String) -> Bool {
        let lowercasedText = text.lowercased()
        let userIndicators = ["i ", "i'm ", "i'll ", "i've ", "i'd ", "me ", "my ", "mine ", "myself "]
        
        for indicator in userIndicators {
            if lowercasedText.contains(indicator) {
                return true
            }
        }
        
        return false
    }
    
    public func messagesMatch(_ text1: String, _ text2: String) -> Bool {
        let cleanText1 = cleanText(text1)
        let cleanText2 = cleanText(text2)
        
        // Simple string similarity check
        return cleanText1 == cleanText2 || 
               cleanText1.contains(cleanText2) || 
               cleanText2.contains(cleanText1)
    }
    
    // Helper method to clean text without returning metadata
    private func cleanText(_ text: String) -> String {
        // Remove special characters and normalize whitespace
        let cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        
        return cleanedText
    }
}

// Message classification and ordering service
public class MessageProcessingService {
    
    private let textProcessor = TextProcessingService()
    
    public init() {}
    
    public func classifyBubbles(from ocrResults: [OCRResult]) -> [MessageBubble] {
        var bubbles: [MessageBubble] = []
        
        for result in ocrResults {
            // Clean the text
            let (cleanedText, metadata) = textProcessor.cleanMessageText(result.text)
            
            // Skip if empty after cleaning or if it's a system message with no content
            if cleanedText.isEmpty || (metadata.isSystemMessage && cleanedText.count < 3) {
                continue
            }
            
            // Determine bubble position
            let position = determineBubblePosition(result.boundingBox)
            
            // Determine if it's likely from the user
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
    
    public func determineBubblePosition(_ boundingBox: CGRect) -> MessageBubble.BubblePosition {
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
    
    public func sortBubblesWithinPage(_ bubbles: [MessageBubble]) -> [MessageBubble] {
        // Sort by vertical position, top to bottom
        return bubbles.sorted {
            // VNRecognizedTextObservation uses coordinate system where 0,0 is bottom-left
            return 1.0 - $0.boundingBox.origin.y < 1.0 - $1.boundingBox.origin.y
        }
    }
    
    public func analyzeScreenshotForOverlap(_ ocrResults: [OCRResult]) -> ScreenshotMetadata {
        let pageIndex = ocrResults.first?.pageIndex ?? 0
        
        // Sort by vertical position
        let sortedResults = ocrResults.sorted {
            return 1.0 - $0.boundingBox.origin.y < 1.0 - $1.boundingBox.origin.y
        }
        
        // Get top and bottom messages for overlap detection
        let topMessages = Array(sortedResults.prefix(min(3, sortedResults.count)))
        let bottomMessages = Array(sortedResults.suffix(min(3, sortedResults.count)))
        
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
            bottomMessages: bottomMessages,
            topMessages: topMessages
        )
    }
    
    // Convert MessageBubbles to the final Message model
    public func convertToMessages(_ bubbles: [MessageBubble]) -> [Message] {
        return bubbles.map { bubble in
            Message(
                text: bubble.text,
                isFromUser: bubble.isLikelyFromUser,
                originalPosition: bubble.boundingBox,
                originalPageIndex: bubble.pageIndex,
                metadata: bubble.metadata
            )
        }
    }
}

// MARK: - Conversation Stitching Service

public class ConversationStitchingService {
    private let ocrService = OCRService()
    private let textProcessor = TextProcessingService()
    private let messageProcessor = MessageProcessingService()
    
    public init() {}
    
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
        
        group.notify(queue: .main) {
            // Check for errors
            if allOCRResults.isEmpty && !errors.isEmpty {
                completion(nil, errors.first)
                return
            }
            
            // Step 2: Analyze screenshots for overlaps and ordering
            let screenshotMetadata = self.analyzeScreenshotsForOrdering(allOCRResults, images.count)
            
            // Step 3: Classify, clean, and order messages
            let messages = self.processAndOrderMessages(allOCRResults, screenshotMetadata)
            
            completion(messages, nil)
        }
    }
    
    private func analyzeScreenshotsForOrdering(_ ocrResults: [OCRResult], _ imageCount: Int) -> [ScreenshotMetadata] {
        // Group OCR results by page
        let resultsByPage = Dictionary(grouping: ocrResults) { $0.pageIndex }
        
        // Create metadata for each screenshot
        var metadata: [ScreenshotMetadata] = []
        for pageIndex in 0..<imageCount {
            if let pageResults = resultsByPage[pageIndex] {
                metadata.append(messageProcessor.analyzeScreenshotForOverlap(pageResults))
            } else {
                // Empty page fallback
                metadata.append(ScreenshotMetadata(
                    pageIndex: pageIndex,
                    earliestTimestamp: nil,
                    latestTimestamp: nil,
                    bottomMessages: [],
                    topMessages: []
                ))
            }
        }
        
        // Detect overlaps between screenshots
        metadata = detectScreenshotOverlaps(metadata)
        
        // Determine chronological order
        metadata = determineChronologicalOrder(metadata)
        
        return metadata
    }
    
    private func detectScreenshotOverlaps(_ metadata: [ScreenshotMetadata]) -> [ScreenshotMetadata] {
        var result = metadata
        
        for i in 0..<result.count {
            for j in 0..<result.count where i != j {
                if screenshotsOverlap(result[i], result[j]) {
                    result[i].overlapsWithPages.append(j)
                }
            }
        }
        
        return result
    }
    
    private func screenshotsOverlap(_ metadata1: ScreenshotMetadata, _ metadata2: ScreenshotMetadata) -> Bool {
        // Check timestamp-based overlap
        if let latest1 = metadata1.latestTimestamp, 
           let earliest2 = metadata2.earliestTimestamp,
           latest1 < earliest2 {
            return true
        }
        
        // Check content-based overlap
        for result1 in metadata1.bottomMessages {
            for result2 in metadata2.topMessages {
                if textProcessor.messagesMatch(result1.text, result2.text) {
                    return true
                }
            }
        }
        
        // Also check the reverse direction
        for result1 in metadata1.topMessages {
            for result2 in metadata2.bottomMessages {
                if textProcessor.messagesMatch(result1.text, result2.text) {
                    return true
                }
            }
        }
        
        return false
    }
    
    private func determineChronologicalOrder(_ metadata: [ScreenshotMetadata]) -> [ScreenshotMetadata] {
        var result = metadata
        
        // Assign initial ranks based on timestamps
        for i in 0..<result.count {
            for j in 0..<result.count where i != j {
                if let latestI = result[i].latestTimestamp, 
                   let earliestJ = result[j].earliestTimestamp,
                   latestI < earliestJ {
                    // i comes before j
                    result[i].chronologicalRank -= 1
                    result[j].chronologicalRank += 1
                }
            }
        }
        
        // Enhance ranking based on overlap relationships
        for i in 0..<result.count {
            for j in result[i].overlapsWithPages {
                // Check if i likely comes before j based on top/bottom message matching
                if isPage1BeforePage2(result[i], result[j]) {
                    result[i].chronologicalRank -= 1
                    result[j].chronologicalRank += 1
                }
            }
        }
        
        // Sort by chronological rank
        return result.sorted { $0.chronologicalRank < $1.chronologicalRank }
    }
    
    private func isPage1BeforePage2(_ metadata1: ScreenshotMetadata, _ metadata2: ScreenshotMetadata) -> Bool {
        // Check for timestamp-based ordering
        if let latest1 = metadata1.latestTimestamp, 
           let earliest2 = metadata2.earliestTimestamp {
            return latest1 < earliest2
        }
        
        // Check for bottom-to-top content matching
        for result1 in metadata1.bottomMessages {
            for result2 in metadata2.topMessages {
                if textProcessor.messagesMatch(result1.text, result2.text) {
                    return true
                }
            }
        }
        
        // Default fallback to initial order
        return metadata1.pageIndex < metadata2.pageIndex
    }
    
    private func processAndOrderMessages(_ ocrResults: [OCRResult], _ orderedMetadata: [ScreenshotMetadata]) -> [Message] {
        // Group OCR results by page
        let resultsByPage = Dictionary(grouping: ocrResults) { $0.pageIndex }
        var allMessages: [Message] = []
        var chronologicalIndex = 0
        
        // Process each page in determined order
        for metadata in orderedMetadata {
            if let pageResults = resultsByPage[metadata.pageIndex] {
                // Classify and clean bubbles
                let bubbles = messageProcessor.classifyBubbles(from: pageResults)
                
                // Sort bubbles within the page
                let sortedBubbles = messageProcessor.sortBubblesWithinPage(bubbles)
                
                // Convert to messages and add chronological index
                let messages = messageProcessor.convertToMessages(sortedBubbles)
                for var message in messages {
                    message.chronologicalIndex = chronologicalIndex
                    chronologicalIndex += 1
                    allMessages.append(message)
                }
            }
        }
        
        // Remove duplicates from overlapping regions
        let uniqueMessages = removeDuplicateMessages(allMessages)
        
        // Sort by final chronological index
        return uniqueMessages.sorted { $0.chronologicalIndex < $1.chronologicalIndex }
    }
    
    private func removeDuplicateMessages(_ messages: [Message]) -> [Message] {
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