# Conversation Stitcher

A simple iOS app that allows users to upload screenshots of message conversations and uses Apple's Vision API to stitch them together into a complete conversation.

## Features

- Upload multiple screenshots of message conversations
- Extract text from images using Vision API
- Stitch extracted text in the order images were selected
- Display the complete conversation

## Requirements

- iOS 16.0+
- Xcode 15.0+
- Swift 5.9+

## How to Use

1. Open the app and tap "Upload Screenshots"
2. Select one or more screenshots from your photo library
3. Tap "Stitch Conversation" to process the images
4. View the extracted conversation text
5. Add more screenshots or clear all to start over

## Implementation Details

This app demonstrates several key iOS technologies:

- **SwiftUI** for the user interface
- **PhotosUI** for selecting images from the photo library
- **Vision** framework for text recognition (OCR)
- Asynchronous processing with **DispatchGroup**

## Privacy

The app processes all images locally on your device. No data is sent to external servers.

## License

This project is available as open source under the MIT license. 