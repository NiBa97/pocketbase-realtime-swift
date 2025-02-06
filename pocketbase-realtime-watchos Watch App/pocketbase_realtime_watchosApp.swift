//
//  pocketbase_realtime_watchosApp.swift
//  pocketbase-realtime-watchos Watch App
//
//  Created by Niklas Bauer on 06.02.25.
//
import SwiftUI


struct AuthResponse: Codable {
    let token: String
    let record: UserRecord
}

struct UserRecord: Codable {
    let id: String
    let email: String
    let name: String
}

class AuthService: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: UserRecord?
    
    private let baseURL = "http://192.168.0.84:8080/api"
    private(set) var authToken: String?

    func login(email: String, password: String) async throws {
        guard let url = URL(string: "\(baseURL)/collections/users/auth-with-password") else {
            throw URLError(.badURL)
        }
        
        let body = ["identity": email, "password": password]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        if httpResponse.statusCode == 200 {
            let authResponse = try JSONDecoder().decode(AuthResponse.self, from: data)
            await MainActor.run {
                self.authToken = authResponse.token
                self.currentUser = authResponse.record
                self.isAuthenticated = true
            }
        } else {
            throw URLError(.badServerResponse)
        }
    }
    
    func logout() {
        authToken = nil
        currentUser = nil
        isAuthenticated = false
    }
}

struct LoginView: View {
    @StateObject private var authService = AuthService()
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage = ""
    @State private var isLoading = false
    
    var body: some View {
        NavigationView {
            if authService.isAuthenticated {
                    TodoListView().environmentObject(authService)
            } else {
                VStack(spacing: 20) {
                    Text("Login")
                        .font(.title)
                        .padding(.top, 50)
                    
                    TextField("Email", text: $email)

                    
                    SecureField("Password", text: $password)
                    
                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                    
                    Button(action: {
                        Task {
                            isLoading = true
                            do {
                                try await authService.login(email: email, password: password)
                                errorMessage = ""
                            } catch let error as NSError {
                                print("Full error: \(error)")
                                print("Debug description: \(error.debugDescription)")
                                print("Localized description: \(error.localizedDescription)")
                                print("Underlying error: \(String(describing: error.userInfo[NSUnderlyingErrorKey]))")
                                errorMessage = error.localizedDescription
                            }
                            isLoading = false
                        }
                    }) {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text("Login")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoading)
                    
                    Spacer()
                }
            }
        }
    }
}



@main
struct pocketbase_realtime_watchos_Watch_AppApp: App {
    @StateObject private var authService = AuthService()

    var body: some Scene {
            WindowGroup {
                    LoginView().environmentObject(authService)
            }
        }
}

