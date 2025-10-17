//
//  UserProfileView.swift
//  Loneless
//
//  Created by Assistant on 16.10.2025.
//

import SwiftUI
import PhotosUI

struct UserProfileView: View {
    @StateObject private var profileStore = UserProfileStore()
    @State private var showingImagePicker = false
    @State private var selectedImage: UIImage?
    
    var body: some View {
        NavigationView {
            Form {
                Section("Основная информация") {
                    HStack {
                        if let avatarData = profileStore.profile.avatarData,
                           let uiImage = UIImage(data: avatarData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 60, height: 60)
                                .clipShape(Circle())
                        } else {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.gray)
                        }
                        
                        Button("Изменить фото") {
                            showingImagePicker = true
                        }
                        .buttonStyle(.bordered)
                    }
                }
                
                Section("Личные данные") {
                    TextField("Имя", text: $profileStore.profile.name)
                    Stepper("Возраст: \(profileStore.profile.age)", value: $profileStore.profile.age, in: 18...99)
                    Picker("Пол", selection: $profileStore.profile.gender) {
                        Text("Мужской").tag(Gender.male)
                        Text("Женский").tag(Gender.female)
                    }
                }
                
                Section("Интересы и темы") {
                    TextField("О чем любишь говорить? (хобби, интересы, темы для общения)", text: $profileStore.profile.interests, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Мой профиль")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: profileStore.profile) { _, _ in
                profileStore.updateProfile(
                    name: profileStore.profile.name,
                    age: profileStore.profile.age,
                    gender: profileStore.profile.gender,
                    interests: profileStore.profile.interests,
                    avatarData: profileStore.profile.avatarData
                )
            }
            .sheet(isPresented: $showingImagePicker) {
                ImagePicker { data, mime in
                    profileStore.profile.avatarData = data
                }
            }
        }
    }
}
