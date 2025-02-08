//
//  Todo.swift
//  pocketbase-realtime-watchos
//
//  Created by Niklas Bauer on 06.02.25.
//


import SwiftUI
import EventSource

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
    private var eventSource: EventSource?
    
    func initialize(with authService: AuthService) {
        guard let token = authService.authToken else {
            errorMessage = "No auth token available"
            return
        }
        self.currentToken = token
        fetchInitialTodos(token: token)
        setupRealtimeConnection(token: token)
    }
    
    private func setupRealtimeConnection(token: String) {
        guard let url = URL(string: "\(baseURL)/api/realtime") else { return }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        eventSource = EventSource(mode: .default)
        
        Task {
            guard let dataTask = await eventSource?.dataTask(for: request) else { return }
            
            for await event in await dataTask.events() {
                switch event {
                case .open:
                    print("Connection opened")
                case .event(let serverEvent):
                    if serverEvent.event == "PB_CONNECT" {
                        await handleConnect(serverEvent)
                    } else {
                        await handleRealtimeEvent(serverEvent)
                    }
                case .error(let error):
                    print("Connection error: \(error)")
                case .closed:
                    print("Connection closed")
                }
            }
        }
    }
    
    @MainActor
    private func handleConnect(_ event: EVEvent) {
        if let data = event.data?.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let clientId = json["clientId"] as? String {
            self.clientId = clientId
            subscribeToCollection()
        }
    }
    
    @MainActor
    private func handleRealtimeEvent(_ event: EVEvent) {
        guard let data = event.data?.data(using: .utf8) else { return }
        
        do {
            let realtimeEvent = try JSONDecoder().decode(RealtimeEvent.self, from: data)
            guard let record = realtimeEvent.record else { return }
            
            switch realtimeEvent.action {
            case "create":
                todos.append(record)
            case "update":
                if let index = todos.firstIndex(where: { $0.id == record.id }) {
                    todos[index] = record
                }
            case "delete":
                todos.removeAll(where: { $0.id == record.id })
            default:
                break
            }
        } catch {
            print("Failed to decode realtime event: \(error)")
        }
    }
    
    private func subscribeToCollection() {
        guard let url = URL(string: "\(baseURL)/api/realtime"),
              let clientId = clientId,
              let token = currentToken else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload = [
            "clientId": clientId,
            "subscriptions": [collection]
        ] as [String : Any]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            
            URLSession.shared.dataTask(with: request) { _, response, error in
                if let error = error {
                    print("Subscription error: \(error)")
                }
            }.resume()
        } catch {
            print("Failed to create subscription request: \(error)")
        }
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
    
    private struct RealtimeEvent: Codable {
        let record: Todo?
        let action: String
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
