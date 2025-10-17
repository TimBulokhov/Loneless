//
//  ImageGenerationService.swift
//  Loneless
//
//  Created by Assistant on 16.10.2025.
//

import Foundation
import UIKit

final class ImageGenerationService {
    struct Config {
        let apiKey: String
        let model: String
        let baseURL: String
    }
    
    private let urlSession: URLSession
    
    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }
    
    // MARK: - Gemini Image Generation
    func generateImageWithGemini(prompt: String, config: Config) async throws -> Data {
        let endpoint = "\(config.baseURL)/models/\(config.model):generateContent"
        let url = URL(string: endpoint)!
        
        struct GeminiPart: Codable {
            let text: String
        }
        
        struct GeminiContent: Codable {
            let parts: [GeminiPart]
        }
        
        struct GeminiMessage: Codable {
            let role: String
            let parts: [GeminiPart]
        }
        
        struct GeminiRequestBody: Codable {
            let contents: [GeminiMessage]
            let generationConfig: GeminiGenerationConfig
        }
        
        struct GeminiGenerationConfig: Codable {
            let temperature: Double
        }
        
        let contents = [
            GeminiMessage(
                role: "user",
                parts: [GeminiPart(text: prompt)]
            )
        ]
        
        let body = GeminiRequestBody(
            contents: contents,
            generationConfig: GeminiGenerationConfig(temperature: 0.8)
        )
        
        let data = try JSONEncoder().encode(body)
        
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        
        // Для Gemini используем query parameter
        let urlWithKey = URL(string: "\(endpoint)?key=\(config.apiKey)")!
        req.url = urlWithKey
        
        let (respData, resp) = try await urlSession.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: respData, encoding: .utf8) ?? ""
            throw NSError(domain: "ImageGenerationService", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: text])
        }
        
        // Парсим ответ Gemini
        struct GeminiCandidate: Codable {
            let content: GeminiContent
        }
        
        struct GeminiResponse: Codable {
            let candidates: [GeminiCandidate]
        }
        
        let decoded = try JSONDecoder().decode(GeminiResponse.self, from: respData)
        let responseText = decoded.candidates.first?.content.parts.first?.text ?? ""
        
        // Если Gemini вернул URL изображения, загружаем его
        if let imageURL = extractImageURL(from: responseText) {
            return try await downloadImage(from: imageURL)
        } else {
            throw NSError(domain: "ImageGenerationService", code: 400, userInfo: [NSLocalizedDescriptionKey: "No image URL found in response"])
        }
    }
    
    // MARK: - DALL-E Image Generation (Fallback)
    func generateImageWithDALLE(prompt: String, config: Config) async throws -> Data {
        let url = URL(string: "\(config.baseURL)/images/generations")!
        
        struct DALLERequestBody: Codable {
            let model: String
            let prompt: String
            let n: Int
            let size: String
            let quality: String
        }
        
        let body = DALLERequestBody(
            model: config.model,
            prompt: prompt,
            n: 1,
            size: "1024x1024",
            quality: "standard"
        )
        
        let data = try JSONEncoder().encode(body)
        
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = data
        
        let (respData, resp) = try await urlSession.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: respData, encoding: .utf8) ?? ""
            throw NSError(domain: "ImageGenerationService", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: text])
        }
        
        // Парсим ответ DALL-E
        struct DALLEImage: Codable {
            let url: String
        }
        
        struct DALLEResponse: Codable {
            let data: [DALLEImage]
        }
        
        let decoded = try JSONDecoder().decode(DALLEResponse.self, from: respData)
        guard let imageURL = decoded.data.first?.url else {
            throw NSError(domain: "ImageGenerationService", code: 400, userInfo: [NSLocalizedDescriptionKey: "No image URL in response"])
        }
        
        return try await downloadImage(from: imageURL)
    }
    
    // MARK: - Helper Methods
    private func extractImageURL(from text: String) -> String? {
        // Ищем URL изображения в тексте ответа
        let urlPattern = #"https?://[^\s]+\.(jpg|jpeg|png|gif|webp)"#
        let regex = try? NSRegularExpression(pattern: urlPattern, options: .caseInsensitive)
        let range = NSRange(location: 0, length: text.utf16.count)
        
        if let match = regex?.firstMatch(in: text, options: [], range: range) {
            return String(text[Range(match.range, in: text)!])
        }
        
        return nil
    }
    
    private func downloadImage(from urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "ImageGenerationService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid image URL"])
        }
        
        let (data, response) = try await urlSession.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw NSError(domain: "ImageGenerationService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Failed to download image"])
        }
        
        return data
    }
}

// MARK: - Character Consistency Manager
final class CharacterConsistencyManager {
    private let userDefaults = UserDefaults.standard
    private let characterKey = "ai_character_description"
    
    // Сохраняем описание персонажа для консистентности
    func saveCharacterDescription(_ description: String) {
        userDefaults.set(description, forKey: characterKey)
    }
    
    // Получаем описание персонажа
    func getCharacterDescription() -> String {
        return userDefaults.string(forKey: characterKey) ?? getDefaultCharacterDescription()
    }
    
    // Генерируем промпт с учетом консистентности персонажа
    func generateConsistentPrompt(basePrompt: String) -> String {
        let characterDescription = getCharacterDescription()
        return "\(characterDescription). \(basePrompt). Сохрани тот же внешний вид и стиль персонажа."
    }
    
    private func getDefaultCharacterDescription() -> String {
        return """
        Молодая девушка 20-25 лет, красивая и привлекательная. 
        Длинные темные волосы, карие глаза, милая улыбка. 
        Стиль одежды: современный, элегантный, иногда игривый. 
        Выражение лица: дружелюбное, заботливое, иногда игривое.
        """
    }
}
