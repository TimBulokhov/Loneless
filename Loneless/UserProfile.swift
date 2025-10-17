//
//  UserProfile.swift
//  Loneless
//
//  Created by Assistant on 16.10.2025.
//

import Foundation
import SwiftUI

enum Gender: String, CaseIterable, Codable {
    case male = "male"
    case female = "female"
}

struct UserProfile: Codable, Equatable {
    var name: String = ""
    var age: Int = 25
    var gender: Gender = .male
    var interests: String = ""
    var avatarData: Data?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}

class UserProfileStore: ObservableObject {
    @Published var profile: UserProfile = UserProfile()
    
    private let userDefaults = UserDefaults.standard
    private let profileKey = "user_profile"
    
    init() {
        loadProfile()
    }
    
    func updateProfile(name: String, age: Int, gender: Gender, interests: String, avatarData: Data?) {
        profile.name = name
        profile.age = age
        profile.gender = gender
        profile.interests = interests
        profile.avatarData = avatarData
        profile.updatedAt = Date()
        saveProfile()
    }
    
    private func saveProfile() {
        if let encoded = try? JSONEncoder().encode(profile) {
            userDefaults.set(encoded, forKey: profileKey)
        }
    }
    
    private func loadProfile() {
        if let data = userDefaults.data(forKey: profileKey),
           let decoded = try? JSONDecoder().decode(UserProfile.self, from: data) {
            profile = decoded
        }
    }
}
