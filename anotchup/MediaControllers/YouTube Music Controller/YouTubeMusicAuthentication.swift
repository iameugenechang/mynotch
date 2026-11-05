//
//  YouTubeMusicAuthentication.swift
//  anotchup
//
//  Created by Alexander on 2025-09-14.
//

import Foundation

// MARK: - Authentication Manager
actor YouTubeMusicAuthManager {
    private var accessToken: String?
    private var authenticationTask: Task<String, Error>?
    private var generation = UUID()
    private let httpClient: YouTubeMusicHTTPClient
    
    init(httpClient: YouTubeMusicHTTPClient) {
        self.httpClient = httpClient
    }
    
    var currentToken: String? {
        accessToken
    }
    
    func authenticate() async throws -> String {
        // Return existing token if valid
        if let token = accessToken {
            return token
        }
        
        // Wait for ongoing authentication if in progress
        if let task = authenticationTask {
            return try await task.value
        }
        
        // Start new authentication
        let current = generation
        let task = Task<String, Error> {
            do {
                let token = try await httpClient.authenticate()
                try Task.checkCancellation()
                await setToken(token, generation: current)
                return token
            } catch {
                await clearAuthenticationTask(generation: current)
                throw error
            }
        }
        
        authenticationTask = task
        return try await task.value
    }
    
    func invalidateToken() async {
        generation = UUID()
        accessToken = nil
        authenticationTask?.cancel()
        authenticationTask = nil
    }
    
    private func setToken(_ token: String, generation: UUID) async {
        guard self.generation == generation else { return }
        accessToken = token
        authenticationTask = nil
    }
    
    private func clearAuthenticationTask(generation: UUID) async {
        guard self.generation == generation else { return }
        authenticationTask = nil
    }
}

// MARK: - Authentication State
enum AuthenticationState: Sendable {
    case unauthenticated
    case authenticating
    case authenticated(String)
    case failed(Error)
    
    var isAuthenticated: Bool {
        if case .authenticated = self {
            return true
        }
        return false
    }
    
    var token: String? {
        if case .authenticated(let token) = self {
            return token
        }
        return nil
    }
}