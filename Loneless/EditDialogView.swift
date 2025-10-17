//
//  EditDialogView.swift
//  Loneless
//
//  Created by Assistant on 16.10.2025.
//

import SwiftUI

struct EditDialogView: View {
    @ObservedObject var store: DialogStore
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var gender: String = "female"
    @State private var age: String = ""
    @State private var context: String = ""
    @State private var showPicker = false

    var body: some View {
        Form {
            Section("Собеседник") {
                TextField("Имя", text: $name)
                Picker("Пол", selection: $gender) {
                    Text("Женский").tag("female")
                    Text("Мужской").tag("male")
                    Text("Другое").tag("other")
                }
                TextField("Возраст", text: $age).keyboardType(.numberPad)
            }
            Section("Контекст") {
                TextField("Кратко о чём общение", text: $context, axis: .vertical).lineLimit(2...5)
            }
            Section("Аватарка") {
                Button("Загрузить аватарку") { showPicker = true }
                if let id = store.currentDialogId, let data = store.dialogs.first(where: { $0.id == id })?.avatarData, let ui = UIImage(data: data) {
                    Image(uiImage: ui).resizable().scaledToFill().frame(height: 160).clipped().cornerRadius(12)
                    Button("Удалить", role: .destructive) { store.setAvatar(nil) }
                }
            }
            Section { Button("Сохранить") { applyChanges(); dismiss() } }
        }
        .navigationTitle("Редактировать")
        .onAppear { load() }
        .sheet(isPresented: $showPicker) { ImagePicker { data, _ in if let data { store.setAvatar(data) } } }
    }

    private func load() {
        guard let id = store.currentDialogId, let d = store.dialogs.first(where: { $0.id == id }) else { return }
        name = d.partnerName
        gender = d.partnerGender
        age = d.partnerAge.map { String($0) } ?? ""
        context = d.context ?? ""
    }

    private func applyChanges() {
        let ctx = context.isEmpty ? nil : context
        store.updateCurrent(name: name, gender: gender, age: Int(age), context: ctx)
        if let data = store.currentDialog()?.avatarData { UserDefaults.standard.set(data, forKey: "current_dialog_avatar") } else { UserDefaults.standard.removeObject(forKey: "current_dialog_avatar") }
    }
}


