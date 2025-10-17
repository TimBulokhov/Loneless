//
//  AIProvider.swift
//  Loneless
//
//  Created by Assistant on 16.10.2025.
//

import Foundation

protocol AIProvider {
    func send(messages: [ChatMessage], systemPrompt: String) async throws -> String
    func sendStream(messages: [ChatMessage], systemPrompt: String, onDelta: @escaping (String) -> Void) async throws
    func describeImage(_ image: Data, mimeType: String, prompt: String, systemPrompt: String) async throws -> String
    func transcribeAudio(_ audio: Data, mimeType: String, prompt: String) async throws -> String
}

final class OpenAIProvider: AIProvider {
    private let service: AIService
    private let model: String
    private let apiKey: String
    private let baseURL: String

    init(service: AIService, model: String, apiKey: String, baseURL: String = "https://api.openai.com/v1") {
        self.service = service
        self.model = model
        self.apiKey = apiKey
        self.baseURL = baseURL
    }

    func send(messages: [ChatMessage], systemPrompt: String) async throws -> String {
        return try await service.send(messages: messages, config: .init(apiKey: apiKey, model: model, systemPrompt: systemPrompt, baseURL: baseURL))
    }

    func sendStream(messages: [ChatMessage], systemPrompt: String, onDelta: @escaping (String) -> Void) async throws {
        try await service.sendStream(messages: messages, config: .init(apiKey: apiKey, model: model, systemPrompt: systemPrompt, baseURL: baseURL), onDelta: onDelta)
    }

    func describeImage(_ image: Data, mimeType: String, prompt: String, systemPrompt: String) async throws -> String {
        // Для Gemini используем vision API
        if baseURL.contains("generativelanguage") {
            return try await describeImageWithGemini(image: image, mimeType: mimeType, prompt: prompt, systemPrompt: systemPrompt)
        }
        
        // OpenAI vision API формат
        struct Part: Codable { let type: String; let text: String?; let image_url: URLPart? }
        struct URLPart: Codable { let url: String }
        struct Message: Codable { let role: String; let content: [Part] }
        struct Body: Codable { let model: String; let messages: [Message] }

        let base64 = image.base64EncodedString()
        let imageURL = "data:\(mimeType);base64,\(base64)"
        let messages: [Message] = [
            .init(role: "system", content: [.init(type: "text", text: systemPrompt, image_url: nil)]),
            .init(role: "user", content: [
                .init(type: "text", text: prompt, image_url: nil),
                .init(type: "image_url", text: nil, image_url: .init(url: imageURL))
            ])
        ]
        let body = Body(model: model, messages: messages)
        var req = URLRequest(url: URL(string: "\(baseURL)/chat/completions")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = try JSONEncoder().encode(body)

        // Используем URLSession с увеличенным таймаутом для Vision API
        let visionSession = URLSession(configuration: {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 60.0
            config.timeoutIntervalForResource = 120.0
            return config
        }())
        let (data, resp) = try await visionSession.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "OpenAIProvider", code: (resp as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: text])
        }
        struct Choice: Codable { let message: Msg }
        struct Msg: Codable { let content: String }
        struct Res: Codable { let choices: [Choice] }
        let decoded = try JSONDecoder().decode(Res.self, from: data)
        return decoded.choices.first?.message.content ?? ""
    }
    
    // Функция для транскрипции с OpenAI Whisper
    private func transcribeWithWhisper(audio: Data, mimeType: String, prompt: String) async throws -> String {
        // Используем OpenAI Whisper для транскрипции
        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        req.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        var body = Data()
        func appendForm(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        func appendFile(_ name: String, filename: String, mime: String, data: Data) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: \(mime)\r\n\r\n".data(using: .utf8)!)
            body.append(data)
            body.append("\r\n".data(using: .utf8)!)
        }

        appendForm("model", "whisper-1")
        appendForm("prompt", prompt)
        appendFile("file", filename: "audio.m4a", mime: mimeType, data: audio)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "OpenAIProvider", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: text])
        }

        struct WhisperResponse: Codable { let text: String }
        let decoded = try JSONDecoder().decode(WhisperResponse.self, from: data)
        return decoded.text
    }
    
    // Функция для обработки изображений с Gemini Vision
    private func describeImageWithGemini(image: Data, mimeType: String, prompt: String, systemPrompt: String) async throws -> String {
        // Для Gemini используем нативную поддержку изображений
        return try await service.processImageWithGemini(
            imageData: image,
            mimeType: mimeType,
            prompt: prompt,
            config: .init(apiKey: apiKey, model: model, systemPrompt: systemPrompt, baseURL: baseURL)
        )
    }

    func transcribeAudio(_ audio: Data, mimeType: String, prompt: String) async throws -> String {
        // Для Gemini используем нативную обработку аудио
        if baseURL.contains("generativelanguage") {
            return try await service.processAudioWithGemini(
                audioData: audio,
                mimeType: mimeType,
                prompt: prompt,
                config: .init(apiKey: apiKey, model: model, systemPrompt: "", baseURL: baseURL)
            )
        }
        
        // Для старых версий Gemini используем заглушку
        if baseURL.contains("generativelanguage") {
            return "Извини, для транскрипции голосовых сообщений нужен OpenAI API ключ или Gemini 2.0 Flash Exp. Добавь их в настройки! 😔"
        }
        
        // Use Whisper via audio/transcriptions
        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        req.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        var body = Data()
        func appendForm(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        func appendFile(_ name: String, filename: String, mime: String, data: Data) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: \(mime)\r\n\r\n".data(using: .utf8)!)
            body.append(data)
            body.append("\r\n".data(using: .utf8)!)
        }

        appendForm("model", "whisper-1")
        appendForm("prompt", prompt)
        appendFile("file", filename: "audio.m4a", mime: mimeType, data: audio)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "OpenAIProvider", code: (resp as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: text])
        }
        struct Res: Codable { let text: String }
        return (try? JSONDecoder().decode(Res.self, from: data).text) ?? String(data: data, encoding: .utf8) ?? ""
    }
}

// Local stub using MLX/llama.cpp can be added later; provide a development fake
final class LocalStubProvider: AIProvider {
    func send(messages: [ChatMessage], systemPrompt: String) async throws -> String {
        let last = messages.last?.text ?? ""
        return "[локально] \(last.reversed())"
    }
    func sendStream(messages: [ChatMessage], systemPrompt: String, onDelta: @escaping (String) -> Void) async throws {
        let text = try await send(messages: messages, systemPrompt: systemPrompt)
        for ch in text { await Task.sleep(20_000_000); onDelta(String(ch)) }
    }
    func describeImage(_ image: Data, mimeType: String, prompt: String, systemPrompt: String) async throws -> String {
        return "[локально] Описание изображения недоступно в заглушке"
    }
    func transcribeAudio(_ audio: Data, mimeType: String, prompt: String) async throws -> String {
        return "[локально] Транскрипция недоступна в заглушке"
    }
}


