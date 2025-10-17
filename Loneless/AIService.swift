//
//  AIService.swift
//  Loneless
//
//  Created by Assistant on 16.10.2025.
//

import Foundation

final class AIService {
    struct Config {
        var apiKey: String
        var model: String
        var systemPrompt: String
        var baseURL: String = "https://api.openai.com/v1"
    }

    private let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }
    
    // Создаем URLSession с увеличенным таймаутом для Vision API
    private func createVisionURLSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60.0 // 60 секунд
        config.timeoutIntervalForResource = 120.0 // 2 минуты
        return URLSession(configuration: config)
    }

    func send(messages: [ChatMessage], config: Config) async throws -> String {
        // Для Gemini используем другой endpoint
        let endpoint = config.baseURL.contains("generativelanguage") ? 
            "\(config.baseURL)/models/\(config.model):generateContent" : 
            "\(config.baseURL)/chat/completions"
        let url = URL(string: endpoint)!

        struct RequestMessage: Codable {
            let role: String
            let content: String
        }

        var payloadMessages: [RequestMessage] = [
            .init(role: "system", content: config.systemPrompt)
        ]
        for m in messages {
            // Для Gemini используем роли "user" и "model" вместо "assistant"
            let role = if config.baseURL.contains("generativelanguage") {
                m.role == .user ? "user" : "model"
            } else {
                m.role == .user ? "user" : "assistant"
            }
            payloadMessages.append(.init(role: role, content: m.text))
        }

        let data: Data
        if config.baseURL.contains("generativelanguage") {
            // Gemini API формат
            struct GeminiContent: Codable {
                let parts: [GeminiPart]
            }
            struct GeminiPart: Codable {
                let text: String
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
            
            var contents: [GeminiMessage] = []
            for msg in payloadMessages {
                // Для Gemini API роли: "user" и "model"
                let geminiRole = if msg.role == "system" {
                    "user"
                } else if msg.role == "assistant" {
                    "model"
                } else {
                    msg.role
                }
                contents.append(GeminiMessage(
                    role: geminiRole,
                    parts: [GeminiPart(text: msg.content)]
                ))
            }
            
            let body = GeminiRequestBody(
                contents: contents,
                generationConfig: GeminiGenerationConfig(temperature: 0.8)
            )
            data = try JSONEncoder().encode(body)
        } else {
            // OpenAI API формат
            struct RequestBody: Codable {
                let model: String
                let messages: [RequestMessage]
                let temperature: Double
            }
            let body = RequestBody(model: config.model, messages: payloadMessages, temperature: 0.8)
            data = try JSONEncoder().encode(body)
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Для Gemini используем query parameter вместо Bearer token
        if config.baseURL.contains("generativelanguage") {
            let urlWithKey = URL(string: "\(endpoint)?key=\(config.apiKey)")!
            req.url = urlWithKey
        } else {
            req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.httpBody = data

        let (respData, resp) = try await urlSession.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: respData, encoding: .utf8) ?? ""
            throw NSError(domain: "AIService", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: text])
        }

        if config.baseURL.contains("generativelanguage") {
            // Gemini API формат ответа
            struct GeminiCandidate: Codable {
                let content: GeminiContent
            }
            struct GeminiContent: Codable {
                let parts: [GeminiPart]
            }
            struct GeminiPart: Codable {
                let text: String
            }
            struct GeminiResponse: Codable {
                let candidates: [GeminiCandidate]
            }
            let decoded = try JSONDecoder().decode(GeminiResponse.self, from: respData)
            return decoded.candidates.first?.content.parts.first?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } else {
            // OpenAI API формат ответа
            struct Choice: Codable { let message: Message }
            struct Message: Codable { let content: String }
            struct ResponseBody: Codable { let choices: [Choice] }
            let decoded = try JSONDecoder().decode(ResponseBody.self, from: respData)
            return decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
    }

    func sendStream(
        messages: [ChatMessage],
        config: Config,
        onDelta: @escaping (String) -> Void
    ) async throws {
        // Для Gemini используем обычный send без streaming
        if config.baseURL.contains("generativelanguage") {
            let response = try await send(messages: messages, config: config)
            onDelta(response)
            return
        }
        
        let url = URL(string: "\(config.baseURL)/chat/completions")!

        struct RequestMessage: Codable { let role: String; let content: String }
        var payloadMessages: [RequestMessage] = [ .init(role: "system", content: config.systemPrompt) ]
        for m in messages {
            // Для Gemini используем роли "user" и "model" вместо "assistant"
            let role = if config.baseURL.contains("generativelanguage") {
                m.role == .user ? "user" : "model"
            } else {
                m.role == .user ? "user" : "assistant"
            }
            payloadMessages.append(.init(role: role, content: m.text))
        }

        struct RequestBody: Codable { let model: String; let messages: [RequestMessage]; let temperature: Double; let stream: Bool }
        let body = RequestBody(model: config.model, messages: payloadMessages, temperature: 0.8, stream: true)
        let data = try JSONEncoder().encode(body)

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = data

        do {
            let (bytes, response) = try await urlSession.bytes(for: req)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                let (edata, eresp) = try await urlSession.data(for: req)
                let code = (eresp as? HTTPURLResponse)?.statusCode ?? -1
                let text = String(data: edata, encoding: .utf8) ?? ""
                throw NSError(domain: "AIService", code: code, userInfo: [NSLocalizedDescriptionKey: text])
            }

            var accumulator = Data()
            for try await chunk in bytes {
                accumulator.append(chunk)
                while let range = accumulator.firstRange(of: Data([0x0A])) { // \n
                    let lineData = accumulator.subdata(in: 0..<range.lowerBound)
                    accumulator.removeSubrange(0..<(range.upperBound))
                    guard let line = String(data: lineData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty else {
                        continue
                    }
                    if line == "data: [DONE]" { return }
                    if line.hasPrefix("data:") {
                        let jsonString = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                        guard let jsonData = jsonString.data(using: .utf8) else { continue }
                        do {
                            struct Delta: Codable { let content: String? }
                            struct Choice: Codable { let delta: Delta }
                            struct StreamChunk: Codable { let choices: [Choice] }
                            let decoded = try JSONDecoder().decode(StreamChunk.self, from: jsonData)
                            if let piece = decoded.choices.first?.delta.content, !piece.isEmpty {
                                onDelta(piece)
                            }
                        } catch { continue }
                    }
                }
            }
        } catch {
            // Transport error: retry non-stream to surface body
            if var obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                obj["stream"] = false
                var non = URLRequest(url: url)
                non.httpMethod = "POST"
                non.setValue("application/json", forHTTPHeaderField: "Content-Type")
                non.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
                non.httpBody = try? JSONSerialization.data(withJSONObject: obj)
                let (edata, eresp) = try await urlSession.data(for: non)
                let code = (eresp as? HTTPURLResponse)?.statusCode ?? -1
                let text = String(data: edata, encoding: .utf8) ?? error.localizedDescription
                throw NSError(domain: "AIService", code: code, userInfo: [NSLocalizedDescriptionKey: text])
            } else {
                throw error
            }
        }
    }
    
    // MARK: - Gemini Audio Processing
    func processAudioWithGemini(audioData: Data, mimeType: String, prompt: String, config: Config) async throws -> String {
        guard config.baseURL.contains("generativelanguage") else {
            throw NSError(domain: "AIService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Audio processing only supported for Gemini"])
        }
        
        let endpoint = "\(config.baseURL)/models/\(config.model):generateContent"
        let url = URL(string: endpoint)!
        
        // Gemini 2.0 Flash Preview поддерживает аудио
        struct GeminiAudioPart: Codable {
            let inlineData: GeminiInlineData
        }
        
        struct GeminiInlineData: Codable {
            let mimeType: String
            let data: String
        }
        
        struct GeminiContent: Codable {
            let parts: [GeminiPart]
        }
        
        struct GeminiPart: Codable {
            let text: String?
            let inlineData: GeminiInlineData?
            
            init(text: String) {
                self.text = text
                self.inlineData = nil
            }
            
            init(audioData: Data, mimeType: String) {
                self.text = nil
                self.inlineData = GeminiInlineData(
                    mimeType: mimeType,
                    data: audioData.base64EncodedString()
                )
            }
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
                parts: [
                    GeminiPart(text: prompt),
                    GeminiPart(audioData: audioData, mimeType: mimeType)
                ]
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
            throw NSError(domain: "AIService", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: text])
        }
        
        // Парсим ответ Gemini
        struct GeminiCandidate: Codable {
            let content: GeminiContent
        }
        
        struct GeminiResponse: Codable {
            let candidates: [GeminiCandidate]
        }
        
        let decoded = try JSONDecoder().decode(GeminiResponse.self, from: respData)
        return decoded.candidates.first?.content.parts.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
    
    // MARK: - Gemini Image Processing
    func processImageWithGemini(imageData: Data, mimeType: String, prompt: String, config: Config) async throws -> String {
        guard config.baseURL.contains("generativelanguage") else {
            throw NSError(domain: "AIService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Image processing only supported for Gemini"])
        }
        
        let endpoint = "\(config.baseURL)/models/\(config.model):generateContent"
        let url = URL(string: endpoint)!
        
        // Gemini 2.0 Flash Preview поддерживает изображения
        struct GeminiImagePart: Codable {
            let inlineData: GeminiInlineData
        }
        
        struct GeminiInlineData: Codable {
            let mimeType: String
            let data: String
        }
        
        struct GeminiContent: Codable {
            let parts: [GeminiPart]
        }
        
        struct GeminiPart: Codable {
            let text: String?
            let inlineData: GeminiInlineData?
            
            init(text: String) {
                self.text = text
                self.inlineData = nil
            }
            
            init(imageData: Data, mimeType: String) {
                self.text = nil
                self.inlineData = GeminiInlineData(
                    mimeType: mimeType,
                    data: imageData.base64EncodedString()
                )
            }
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
                parts: [
                    GeminiPart(text: prompt),
                    GeminiPart(imageData: imageData, mimeType: mimeType)
                ]
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
            throw NSError(domain: "AIService", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: text])
        }
        
        // Парсим ответ Gemini
        struct GeminiCandidate: Codable {
            let content: GeminiContent
        }
        
        struct GeminiResponse: Codable {
            let candidates: [GeminiCandidate]
        }
        
        let decoded = try JSONDecoder().decode(GeminiResponse.self, from: respData)
        return decoded.candidates.first?.content.parts.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}


