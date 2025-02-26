import SwiftUI
import PhotosUI

public class ConversationViewModel: ObservableObject {
    // Published properties to update the UI when values change
    @Published public var selectedImages: [UIImage] = []
    @Published public var parsedMessages: [Message] = []
    @Published public var isRecognizing: Bool = false
    @Published public var selectedItems: [PhotosPickerItem] = []
    @Published public var errorMessage: String? = nil
    @Published public var showError: Bool = false
    
    // Services
    private let stitchingService = ConversationStitchingService()
    
    public init() {}
    
    // Process selected images to extract and stitch a conversation
    public func processImages() {
        guard !selectedImages.isEmpty else { return }
        
        isRecognizing = true
        parsedMessages = []
        
        stitchingService.processScreenshots(selectedImages) { [weak self] messages, error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.isRecognizing = false
                
                if let error = error {
                    self.handleError("Error processing screenshots: \(error.localizedDescription)")
                } else if let messages = messages {
                    self.parsedMessages = messages
                }
            }
        }
    }
    
    // Handle loading of selected PhotosPickerItems
    public func loadSelectedImages(from items: [PhotosPickerItem]) {
        Task {
            var newImages: [UIImage] = []
            
            for item in items {
                do {
                    if let data = try await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        newImages.append(image)
                    }
                } catch {
                    handleError("Failed to load an image: \(error.localizedDescription)")
                }
            }
            
            if !newImages.isEmpty {
                await MainActor.run {
                    self.selectedImages.append(contentsOf: newImages)
                }
            }
        }
    }
    
    // Clear all selected data
    public func clearAll() {
        selectedImages = []
        parsedMessages = []
        selectedItems = []
    }
    
    // Handle errors
    public func handleError(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.errorMessage = message
            self.showError = true
            print("Error: \(message)")
        }
    }
} 