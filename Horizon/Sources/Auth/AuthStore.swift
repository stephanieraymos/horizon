import Observation
import Supabase

@Observable
@MainActor
final class AuthStore {
    var session: Session?
    var isLoading = false
    var error: String?

    var isSignedIn: Bool  { session != nil }
    var userEmail: String? { session?.user.email }

    init() {
        Task { await observeAuthState() }
    }

    private func observeAuthState() async {
        for await (_, newSession) in supabase.auth.authStateChanges {
            session = newSession
        }
    }

    func signIn(email: String, password: String) async {
        isLoading = true
        error = nil
        do {
            session = try await supabase.auth.signIn(email: email, password: password)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func signUp(email: String, password: String) async {
        isLoading = true
        error = nil
        do {
            try await supabase.auth.signUp(email: email, password: password)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func signOut() async {
        try? await supabase.auth.signOut()
        session = nil
    }

    /// Sends a password reset email. Returns true on success.
    func sendPasswordReset(email: String) async -> Bool {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            try await supabase.auth.resetPasswordForEmail(email)
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
}
