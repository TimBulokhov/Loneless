//
//  MessageRowView.swift
//  Loneless
//
//  Created by Assistant on 16.10.2025.
//

import SwiftUI
import Combine

struct MessageRowView: View {
    let message: ChatMessage
    @State private var avatar: UIImage?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .assistant {
                if let avatar {
                    Image(uiImage: avatar)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 28, height: 28)
                        .clipShape(Circle())
                } else {
                    Image(systemName: "heart.circle.fill")
                        .foregroundStyle(.pink)
                        .font(.system(size: 28))
                }
            }
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                if !message.attachments.isEmpty {
                    ForEach(message.attachments) { att in
                        switch att.kind {
                        case .image:
                            if let ui = UIImage(data: att.data) {
                                Image(uiImage: ui)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(maxWidth: 220, maxHeight: 220)
                                    .clipped()
                                    .cornerRadius(10)
                            }
                        case .audio:
                            VoiceMessageView(attachment: att, isUserMessage: message.role == .user)
                        }
                    }
                }
                if !message.text.isEmpty {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(message.text)
                            .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
                            .padding(10)
                            .background(message.role == .user ? Color.blue.opacity(0.15) : Color.pink.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        if message.role == .user {
                            HStack(spacing: 4) {
                                Spacer()
                                Text(formatTime(message.createdAt))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Image(systemName: message.readAt == nil ? "checkmark" : "checkmark.circle.fill")
                                    .font(.caption2)
                                    .foregroundColor(message.readAt == nil ? Color.secondary : Color.blue)
                                    .help(message.readAt != nil ? "Прочитано \(formatTime(message.readAt!))" : "Доставлено")
                            }
                        } else {
                            Text(formatTime(message.createdAt))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } else if !message.attachments.isEmpty {
                    // Если есть только вложения без текста, показываем время
                    if message.role == .user {
                        HStack(spacing: 4) {
                            Spacer()
                            Text(formatTime(message.createdAt))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Image(systemName: message.readAt == nil ? "checkmark" : "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundColor(message.readAt == nil ? Color.secondary : Color.blue)
                                .help(message.readAt != nil ? "Прочитано \(formatTime(message.readAt!))" : "Доставлено")
                        }
                    } else {
                        Text(formatTime(message.createdAt))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            if message.role == .user {
                // Аватарка пользователя
                if let userProfile = getUserProfile(), let avatarData = userProfile.avatarData,
                   let uiImage = UIImage(data: avatarData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 28, height: 28)
                        .clipShape(Circle())
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.system(size: 28))
                }
            }
        }
        .listRowSeparator(.hidden)
        .id(message.id)
        .onAppear { loadAvatar() }
    }
    
    private func getUserProfile() -> UserProfile? {
        if let data = UserDefaults.standard.data(forKey: "user_profile"),
           let profile = try? JSONDecoder().decode(UserProfile.self, from: data) {
            return profile
        }
        return nil
    }

    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    private func loadAvatar() {
        // Read avatar from DialogStore via NotificationCenter to avoid passing store through props
        if let app = UIApplication.shared.delegate as? UIApplicationDelegate {}; // no-op for compatibility
        // Fallback: read from a shared singleton would be better; here use UserDefaults data if present
        if let data = UserDefaults.standard.data(forKey: "current_dialog_avatar"), let img = UIImage(data: data) {
            self.avatar = img
        }
    }
}


