import SwiftUI
import AppShellKit

/// Horizon's sign-in — a thin themed wrapper over the shared
/// `AppShellKit.AppShellAuthView` (native fields → keyboard text-replacement +
/// password autofill preserved). Keeps the app's own `AuthStore` (email/password
/// + error + busy) and Horizon's extra affordances (Forgot Password, Create
/// Account) pinned below the shared card.
struct SignInView: View {
    @Environment(AuthStore.self) private var authStore
    @State private var email      = ""
    @State private var password   = ""
    @State private var showSignUp = false
    @State private var resetSent  = false

    private var config: AppShellAuthConfig {
        AppShellAuthConfig(
            appName: "Horizon",
            tagline: "Plan trips together.",
            symbol: "airplane.departure",
            accent: Theme.Colors.brand,
            background: Theme.Colors.background,
            ink: .primary,
            inkSecondary: .secondary,
            field: Theme.Colors.card
        )
    }

    var body: some View {
        AppShellAuthView(
            config: config,
            email: $email,
            password: $password,
            error: authStore.error,
            isBusy: authStore.isLoading,
            onSubmit: { Task { await authStore.signIn(email: email, password: password) } }
        )
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                if resetSent {
                    Label {
                        Text("Password reset email sent. Check your inbox.")
                    } icon: {
                        Image(systemName: "envelope.badge")
                            .foregroundStyle(Theme.Colors.brand)
                    }
                    .font(.callout)
                    .multilineTextAlignment(.center)
                }

                Button("Forgot Password?") {
                    Task { resetSent = await authStore.sendPasswordReset(email: email) }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .disabled(authStore.isLoading || email.isEmpty)

                Button("Create Account") { showSignUp = true }
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 20)
            .frame(maxWidth: 460)
        }
        .sheet(isPresented: $showSignUp) {
            SignUpView()
        }
    }
}
