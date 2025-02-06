//
//  Todo.swift
//  pocketbase-realtime-watchos
//
//  Created by Niklas Bauer on 06.02.25.
//


import SwiftUI

struct Todo: Codable, Identifiable {
    let id: String
    var title: String
    var status: Bool
}



class TodoService: ObservableObject {
    @Published var todos: [Todo] = []
    @Published var errorMessage: String?
    
    private let baseURL = "http://192.168.0.84:8080"
    private var currentToken: String?
    private var clientId: String?
    private let collection = "todos"
    
    func initialize(with authService: AuthService) {
        guard let token = authService.authToken else {
            errorMessage = "No auth token available"
            return
        }
        self.currentToken = token
        fetchInitialTodos(token: token)
    }
    
    func toggleStatus(todo: Todo) async {
        guard let token = currentToken else { return }
        guard let url = URL(string: "\(baseURL)/api/collections/todos/records/\(todo.id)") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let updatedTodo = ["status": !todo.status]
        
        do {
            request.httpBody = try JSONEncoder().encode(updatedTodo)
            let (_, _) = try await URLSession.shared.data(for: request)
            
        } catch {
            print("Failed to toggle todo status: \(error)")
        }
    }
    
    private func fetchInitialTodos(token: String) {
        guard let url = URL(string: "\(baseURL)/api/collections/todos/records") else { return }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let data = data {
                do {
                    let response = try JSONDecoder().decode(ListResponse.self, from: data)
                    print(response)
                    DispatchQueue.main.async {
                        self?.todos = response.items
                    }
                } catch {
                    print("Failed to fetch initial todos: \(error)")
                }
            }
        }.resume()
    }
    
    
    
    // MARK: - Response Models
    private struct ListResponse: Codable {
        let page: Int
        let perPage: Int
        let totalItems: Int
        let totalPages: Int
        let items: [Todo]
    }
}


struct TodoListView: View {
    @StateObject private var todoService = TodoService()
    @EnvironmentObject var authService: AuthService
    
    var body: some View {
        List(todoService.todos) { todo in
            Button(action: {
                Task {
                    await todoService.toggleStatus(todo: todo)
                }
            }) {
                VStack(alignment: .leading) {
                    Text(todo.title)
                        .strikethrough(todo.status)
                    Text("ID: \(todo.id)")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .buttonStyle(PlainButtonStyle())
        }
        .navigationTitle("Todos")
        .onAppear {
            todoService.initialize(with: authService)
        }
    }
}
