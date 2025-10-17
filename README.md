# 💬 Loneless - AI Chat App

AI-powered chat application with voice messages, image analysis, and random messages built with SwiftUI for iOS.

## ✨ Features

### 🎤 Voice Messages
- Record and send voice messages
- Voice message transcription using OpenAI Whisper
- Voice response toggle (green speaker icon)
- Voice responses work automatically or on command

### 🖼️ Image Analysis
- Send images and get detailed analysis
- Uses OpenAI GPT-4 Vision for accurate recognition
- Retry logic for network timeouts
- Smart image description prompts

### 🎲 Random Messages
- Automatic random messages every 1-3 hours
- 8 different playful message prompts
- Uses Gemini 2.5 Pro for quality responses
- Retry logic for timeouts

### 💬 Chat Features
- Multiple AI models support (Gemini, OpenAI)
- API key rotation system
- Usage tracking and limits
- Character consistency management
- Typing indicators and notifications

## 🛠️ Technical Stack

- **Language**: Swift
- **Framework**: SwiftUI
- **AI Services**: 
  - Google Gemini (chat, image analysis)
  - OpenAI (voice transcription, image analysis)
- **Architecture**: MVVM
- **Storage**: UserDefaults, Core Data

## 🚀 Getting Started

1. Clone the repository
2. Open `Loneless.xcodeproj` in Xcode
3. Add your API keys in `Secrets.swift`:
   - OpenAI API key for voice transcription
   - Gemini API key for chat and image analysis
4. Build and run on iOS device or simulator

## 📱 Screenshots

*Coming soon...*

## 🔧 Configuration

### API Keys
- **OpenAI**: For voice transcription and image analysis
- **Gemini**: For chat responses and image analysis

### Voice Settings
- Toggle voice responses on/off
- Voice messages are transcribed and used for context
- No duplicate text messages in chat

### Random Messages
- Configurable interval (1-3 hours)
- 8 different message types
- Automatic retry on failures

## 📄 License

This project is licensed under the MIT License.

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📞 Support

If you have any questions or issues, please open an issue on GitHub.

---

Made with ❤️ using SwiftUI and AI
