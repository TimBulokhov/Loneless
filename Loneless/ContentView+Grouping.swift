import Foundation
import SwiftUI

struct DateHeaderView: View {
    let date: Date
    var body: some View {
        Text(humanDate(date))
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
    }
    private func humanDate(_ date: Date) -> String {
        let cal = Calendar.current
        let now = Date()
        
        // Проверяем сегодня
        if cal.isDate(date, inSameDayAs: now) { 
            return "Сегодня" 
        }
        
        // Проверяем вчера
        if let yesterday = cal.date(byAdding: .day, value: -1, to: now),
           cal.isDate(date, inSameDayAs: yesterday) { 
            return "Вчера" 
        }
        
        // Проверяем позавчера
        if let dayBeforeYesterday = cal.date(byAdding: .day, value: -2, to: now),
           cal.isDate(date, inSameDayAs: dayBeforeYesterday) {
            let f = DateFormatter()
            f.locale = Locale(identifier: "ru_RU")
            f.dateFormat = "d MMMM"
            return f.string(from: date)
        }
        
        // Для более старых дат
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMMM"
        return f.string(from: date)
    }
}

extension ContentView {
    struct MessageSection {
        let date: Date
        let items: [ChatMessage]
    }

    func groupedMessages() -> [MessageSection] {
        let messages = dialogStore.messagesOfCurrent()
        guard !messages.isEmpty else { return [] }
        let cal = Calendar.current
        let grouped = Dictionary(grouping: messages) { m in
            cal.startOfDay(for: m.createdAt)
        }
        return grouped.keys.sorted().map { key in
            MessageSection(date: key, items: grouped[key]!.sorted(by: { $0.createdAt < $1.createdAt }))
        }
    }
}


