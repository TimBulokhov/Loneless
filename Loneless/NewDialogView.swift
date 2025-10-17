//
//  NewDialogView.swift
//  Loneless
//
//  Created by Assistant on 16.10.2025.
//

import SwiftUI

struct NewDialogView: View {
    @ObservedObject var store: DialogStore
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var gender: String = "female"
    @State private var age: String = ""
    @State private var context: String = ""

    var body: some View {
        Form {
            Section("Собеседник") {
                TextField("Имя", text: $name)
                Picker("Пол", selection: $gender) {
                    Text("Женский").tag("female")
                    Text("Мужской").tag("male")
                    Text("Другое").tag("other")
                }
                TextField("Возраст", text: $age)
                    .keyboardType(.numberPad)
            }
            Section("Контекст") {
                TextField("Кратко о чём общение", text: $context, axis: .vertical)
                    .lineLimit(2...5)
            }
            Section {
                Button("Создать диалог") {
                    let ageInt = Int(age)
                    store.createDialog(name: name, gender: gender, age: ageInt, context: context.isEmpty ? nil : context)
                    dismiss()
                }
            }
        }
        .navigationTitle("Новый диалог")
    }
}


