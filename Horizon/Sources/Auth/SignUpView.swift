import SwiftUI

struct SignUpView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss
    @State private var email    = ""
    @State private var password = ""
    @State private var confirm  = ""
    @State private var showConfirmationNotice = false

    private var passwordsMatch: Bool { password == confirm }
    private var canSubmit: Bool { !email.isEmpty && password.count >= 6 && passwordsMatch }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                        .textContentType(.newPassword)
                    SecureField("Confirm Password", text: $confirm)
                        .textContentType(.newPassword)
                }

                if !password.isEmpty && !passwordsMatch {
                    Section {
                        Text("Passwords don't match")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                if showConfirmationNotice {
                    Section {
                        Label {
                            Text("Check your email for a confirmation link, then sign in.")
                        } icon: {
                            Image(systemName: "envelope.badge")
                                .foregroundStyle(Color.accentColor)
                        }
                        .font(.callout)
                    }
                }

                if let error = authStore.error {
                    Section {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(errorMessage(error))
                                    .foregroundStyle(.red)
                                if isEmailTakenError(error) {
                                    Text("Try signing in instead, or use a different email.")
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                }
                            }
                        } icon: {
                            Image(systemName: "exclamationmark.circle")
                                .foregroundStyle(.red)
                        }
                        .font(.callout)
                    }
                }

                Section {
                    Button("Create Account") {
                        Task { await submit() }
                    }
                    .disabled(!canSubmit || authStore.isLoading)
                }
            }
            .navigationTitle("Create Account")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .overlay { if authStore.isLoading { ProgressView() } }
        }
    }

    private func submit() async {
        showConfirmationNotice = false
        await authStore.signUp(email: email, password: password)

        if authStore.error != nil { return }

        if authStore.isSignedIn {
            dismiss()
        } else {
            showConfirmationNotice = true
        }
    }

    private func errorMessage(_ raw: String) -> String {
        if isEmailTakenError(raw) { return "An account with this email already exists." }
        return raw
    }

    private func isEmailTakenError(_ message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("already registered") ||
               lower.contains("already exists") ||
               lower.contains("user already")
    }
}
