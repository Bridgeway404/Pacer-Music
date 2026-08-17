import SwiftUI

/// Minimal email/password auth via Supabase. Demo Mode never requires this —
/// signing in simply moves run history to the cloud.
///
/// Sign in with Apple is the natural next step for an iOS app
/// (Supabase Auth supports it via `signInWithIdToken`); it needs the
/// Sign in with Apple capability + an Apple Developer account, so it is
/// documented in docs/INTEGRATIONS.md rather than half-enabled here.
struct AuthView: View {
    @Environment(SupabaseService.self) private var supabase
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var isSignUp = false
    @State private var isBusy = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()
                VStack(spacing: 16) {
                    if supabase.isSignedIn {
                        signedInBody
                    } else {
                        formBody
                    }
                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("Account")
        }
        .preferredColorScheme(.dark)
    }

    private var signedInBody: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 54))
                .foregroundStyle(Theme.accent)
            Text(supabase.userEmail ?? "Signed in")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            Text("Runs now sync to your Pacer account.")
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
            Button {
                Task {
                    try? await supabase.signOut()
                }
            } label: {
                Text("Sign Out")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Theme.surfaceRaised, in: Capsule())
                    .foregroundStyle(Theme.textPrimary)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .padding(.top, 40)
    }

    private var formBody: some View {
        VStack(spacing: 12) {
            Text(isSignUp ? "Create your account" : "Welcome back")
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 24)
            Text("Optional — Demo Mode works without an account. Sign in to keep run history in the cloud.")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)

            if isSignUp {
                field("Display name", text: $displayName, contentType: .name)
            }
            field("Email", text: $email, contentType: .emailAddress, keyboard: .emailAddress)
            secureField("Password", text: $password)

            if let message {
                Text(message)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Theme.warn)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await submit() }
            } label: {
                Group {
                    if isBusy {
                        ProgressView()
                    } else {
                        Text(isSignUp ? "Sign Up" : "Sign In")
                    }
                }
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Theme.accent, in: Capsule())
                .foregroundStyle(.black)
            }
            .buttonStyle(.plain)
            .disabled(isBusy || email.isEmpty || password.isEmpty)

            Button {
                isSignUp.toggle()
                message = nil
            } label: {
                Text(isSignUp ? "Have an account? Sign in" : "New here? Create an account")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.accentAlt)
            }
            .buttonStyle(.plain)
        }
    }

    private func field(
        _ placeholder: String,
        text: Binding<String>,
        contentType: UITextContentType? = nil,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        TextField(placeholder, text: text)
            .textContentType(contentType)
            .keyboardType(keyboard)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .foregroundStyle(Theme.textPrimary)
    }

    private func secureField(_ placeholder: String, text: Binding<String>) -> some View {
        SecureField(placeholder, text: text)
            .textContentType(.password)
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .foregroundStyle(Theme.textPrimary)
    }

    private func submit() async {
        isBusy = true
        message = nil
        do {
            if isSignUp {
                try await supabase.signUp(
                    email: email,
                    password: password,
                    displayName: displayName.isEmpty ? String(email.split(separator: "@")[0]) : displayName
                )
                message = "Account created. Check your inbox if email confirmation is required."
            } else {
                try await supabase.signIn(email: email, password: password)
            }
        } catch {
            message = error.localizedDescription
        }
        isBusy = false
    }
}
