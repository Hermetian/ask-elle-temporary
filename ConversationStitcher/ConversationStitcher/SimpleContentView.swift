import SwiftUI
import Vision
import PhotosUI

// MARK: - View Components
struct ChatBubble: View {
    let message: Message
    
    var body: some View {
        HStack {
            if message.isFromUser {
                Spacer()
            }
            
            Text(message.text)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(message.isFromUser ? Color.blue : Color(.systemGray5))
                .foregroundColor(message.isFromUser ? .white : .black)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .frame(maxWidth: 280, alignment: message.isFromUser ? .trailing : .leading)
                
            if !message.isFromUser {
                Spacer()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

// MARK: - Simplified Content View
public struct SimpleContentView: View {
    @State private var selectedImages: [UIImage] = []
    @State private var parsedMessages: [Message] = []
    @State private var isRecognizing: Bool = false
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var errorMessage: String? = nil
    @State private var showError: Bool = false
    
    private let stitchingService = ConversationStitchingService()
    
    public init() {} // Add explicit public initializer
    
    public var body: some View {
        NavigationStack {
            VStack {
                if selectedImages.isEmpty {
                    VStack {
                        Image(systemName: "photo.on.rectangle")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 100, height: 100)
                            .foregroundColor(.gray)
                        
                        Text("No screenshots selected")
                            .font(.headline)
                            .padding()
                        
                        PhotosPicker(
                            selection: $selectedItems,
                            matching: .images,
                            photoLibrary: .shared()
                        ) {
                            Text("Upload Screenshots")
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    VStack {
                        HStack {
                            Text("Selected Screenshots: \(selectedImages.count)")
                                .font(.headline)
                            
                            Spacer()
                        }
                        .padding([.horizontal, .top])
                        
                        ScrollView(.horizontal) {
                            LazyHGrid(rows: [GridItem(.fixed(100))], spacing: 10) {
                                ForEach(0..<selectedImages.count, id: \.self) { index in
                                    Image(uiImage: selectedImages[index])
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 100, height: 100)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                            }
                            .padding(.horizontal)
                        }
                        .frame(height: 120)
                        
                        if !parsedMessages.isEmpty {
                            VStack(alignment: .leading) {
                                HStack {
                                    Text("Here's what the conversation looks like:")
                                        .font(.headline)
                                    
                                    Spacer()
                                }
                                .padding(.horizontal)
                                .padding(.top, 8)
                                
                                ScrollView {
                                    LazyVStack {
                                        ForEach(parsedMessages) { message in
                                            ChatBubble(message: message)
                                        }
                                    }
                                    .padding(.vertical, 8)
                                }
                                .background(Color(.systemBackground))
                            }
                            .frame(maxHeight: .infinity)
                        }
                        
                        HStack {
                            PhotosPicker(
                                selection: $selectedItems,
                                matching: .images,
                                photoLibrary: .shared()
                            ) {
                                Text("Select More")
                                    .padding(.horizontal)
                            }
                            
                            Spacer()
                            
                            Button("Clear All") {
                                selectedImages = []
                                parsedMessages = []
                                selectedItems = []
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                processImages()
                            }) {
                                Text(isRecognizing ? "Processing..." : "Stitch Conversation")
                                    .padding(.horizontal)
                                    .background(isRecognizing || selectedImages.isEmpty ? Color.gray : Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                            }
                            .disabled(isRecognizing || selectedImages.isEmpty)
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Conversation Stitcher")
            .onChange(of: selectedItems) { newItems in
                loadSelectedImages(from: newItems)
            }
            .alert("Error", isPresented: $showError, presenting: errorMessage) { _ in
                Button("OK") { showError = false }
            } message: { message in
                Text(message)
            }
        }
    }
    
    private func loadSelectedImages(from items: [PhotosPickerItem]) {
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
    
    private func processImages() {
        guard !selectedImages.isEmpty else { return }
        
        isRecognizing = true
        parsedMessages = []
        
        stitchingService.processScreenshots(selectedImages) { messages, error in
            isRecognizing = false
            
            if let error = error {
                handleError("Error processing screenshots: \(error.localizedDescription)")
            } else if let messages = messages {
                parsedMessages = messages
            }
        }
    }
    
    private func handleError(_ message: String) {
        DispatchQueue.main.async {
            self.errorMessage = message
            self.showError = true
            print("Error: \(message)")
        }
    }
}

#Preview {
    SimpleContentView()
} 