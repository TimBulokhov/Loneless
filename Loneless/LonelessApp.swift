//
//  LonelessApp.swift
//  Loneless
//
//  Created by Timofey Bulokhov on 16.10.2025.
//

import SwiftUI
import UserNotifications

@main
struct LonelessApp: App {
    init() {
        requestNotificationPermission()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("Notification permission granted")
                setupNotificationCategories()
            } else if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }
    
    private func setupNotificationCategories() {
        let messageCategory = UNNotificationCategory(
            identifier: "MESSAGE_CATEGORY",
            actions: [],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([messageCategory])
        
        // Настройка делегата для показа уведомлений даже когда приложение активно
        UNUserNotificationCenter.current().delegate = NotificationDelegate()
    }
}

class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Показываем уведомление даже когда приложение активно
        completionHandler([.banner, .sound, .badge])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        // Обработка нажатия на уведомление
        completionHandler()
    }
}
