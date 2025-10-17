//
//  DialogsView.swift
//  Loneless
//
//  Created by Assistant on 16.10.2025.
//

import SwiftUI

struct DialogsView: View {
    @ObservedObject var store: DialogStore
    @State private var renamingDialog: ChatDialog?
    @State private var newTitle: String = ""

    var body: some View {
        List {
            Section {
                NavigationLink {
                    NewDialogView(store: store)
                } label: {
                    Label("Новый диалог", systemImage: "plus.circle.fill")
                }
                
                NavigationLink {
                    UserProfileView()
                } label: {
                    Label("Мой профиль", systemImage: "person.circle")
                }
            }
            ForEach(store.dialogs) { dialog in
                HStack {
                    VStack(alignment: .leading) {
                        Text(dialog.title.isEmpty ? "Диалог" : dialog.title)
                            .font(.headline)
                        Text(dialog.messages.last?.text ?? "Пусто")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if store.currentDialogId == dialog.id {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { store.currentDialogId = dialog.id }
                .onLongPressGesture {
                    // Открываем полноценное редактирование
                    store.currentDialogId = dialog.id
                    // Навигация к редактированию через скрытую ссылку
                    renamingDialog = dialog
                    newTitle = dialog.title
                }
            }
            .onDelete(perform: store.delete)
        }
        .navigationTitle("Диалоги")
        .toolbar { }
        .sheet(isPresented: Binding(get: { renamingDialog != nil }, set: { if !$0 { renamingDialog = nil } })) {
            NavigationStack { EditDialogView(store: store) }
        }
    }
}


