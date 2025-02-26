import SwiftUI
import PhotosUI
import Vision
import Foundation
import UIKit // needed for UIImage

// Import local modules - these should make the types available

// MARK: - Chat Bubble View

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
    }
}

// MARK: - Content View

struct ContentView: View {
    @StateObject private var viewModel = ConversationViewModel()
    
    var body: some View {
        NavigationStack {
            VStack {
                if viewModel.selectedImages.isEmpty {
                    emptyStateView
                } else {
                    contentView
                }
            }
            .navigationTitle("Conversation Stitcher")
            .onChange(of: viewModel.selectedItems) { newValue in
                if !newValue.isEmpty {
                    viewModel.loadSelectedImages(from: newValue)
                }
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "An error occurred")
            }
        }
    }
    
    // MARK: - Component Views
    
    private var emptyStateView: some View {
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
                selection: $viewModel.selectedItems,
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
    }
    
    private var contentView: some View {
        VStack {
            selectedImagesHeader
            thumbnailGrid
            
            if !viewModel.parsedMessages.isEmpty {
                conversationView
            }
            
            actionButtons
        }
    }
    
    private var selectedImagesHeader: some View {
        HStack {
            Text("Selected Screenshots: \(viewModel.selectedImages.count)")
                .font(.headline)
            
            Spacer()
        }
        .padding([.horizontal, .top])
    }
    
    private var thumbnailGrid: some View {
        ScrollView(.horizontal) {
            LazyHGrid(rows: [GridItem(.fixed(100))], spacing: 10) {
                ForEach(0..<viewModel.selectedImages.count, id: \.self) { index in
                    Image(uiImage: viewModel.selectedImages[index])
                        .resizable()
                        .scaledToFill()
                        .frame(width: 100, height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(.horizontal)
        }
        .frame(height: 120)
    }
    
    private var conversationView: some View {
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
                    ForEach(viewModel.parsedMessages) { message in
                        ChatBubble(message: message)
                    }
                }
                .padding(.vertical, 8)
            }
            .background(Color(.systemBackground))
        }
        .frame(maxHeight: .infinity)
    }
    
    private var actionButtons: some View {
        HStack {
            PhotosPicker(
                selection: $viewModel.selectedItems,
                matching: .images,
                photoLibrary: .shared()
            ) {
                Text("Select More")
                    .padding(.horizontal)
            }
            
            Spacer()
            
            Button("Clear All") {
                viewModel.clearAll()
            }
            
            Spacer()
            
            Button(action: {
                viewModel.processImages()
            }) {
                Text(viewModel.isRecognizing ? "Processing..." : "Stitch Conversation")
                    .padding(.horizontal)
                    .background(viewModel.isRecognizing || viewModel.selectedImages.isEmpty ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .disabled(viewModel.isRecognizing || viewModel.selectedImages.isEmpty)
        }
        .padding()
    }
}

#Preview {
    ContentView()
} 