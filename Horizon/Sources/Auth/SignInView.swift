import SwiftUI

struct SignInView: View {
    @Environment(AuthStore.self) private var authStore
    @State private var email      = ""
    @State private var password   = ""
    @State private var showSignUp = false
    @State private var resetSent  = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                }

                if resetSent {
                    Section {
                        Label {
                            Text("Password reset email sent. Check your inbox.")
                        } icon: {
                            Image(systemName: "envelope.badge")
                                .foregroundStyle(Color.accentColor)
                        }
                        .font(.callout)
                    }
                }

                if let error = authStore.error {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                Section {
                    Button("Sign In") {
                        Task { await authStore.signIn(email: email, password: password) }
                    }
                    .disabled(authStore.isLoading || email.isEmpty || password.isEmpty)

                    Button("Forgot Password?") {
                        Task {
                            resetSent = await authStore.sendPasswordReset(email: email)
                        }
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .disabled(authStore.isLoading || email.isEmpty)
                }

                Section {
                    Button("Create Account") { showSignUp = true }
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Horizon")
            .overlay { if authStore.isLoading { ProgressView() } }
        }
        .sheet(isPresented: $showSignUp) {
            SignUpView()
        }
    }
}
