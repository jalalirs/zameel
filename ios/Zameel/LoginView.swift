import SwiftUI

struct LoginView: View {
    @EnvironmentObject var session: Session
    @State private var email = ""
    @State private var name = ""
    @State private var password = ""
    @State private var registering = false
    @State private var error: String?
    @State private var busy = false
    @AppStorage("baseURL") private var baseURL = "https://jalalirs.tailedf721.ts.net/zameel"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 4) {
                        Image(systemName: "airplane.circle.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.tint)
                        Text("Zameel")
                            .font(.largeTitle.bold())
                        Text("Plan, budget, and track your trips")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
                Section(registering ? "Create account" : "Sign in") {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if registering {
                        TextField("Your name", text: $name)
                    }
                    SecureField("Password", text: $password)
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
                Section {
                    Button(registering ? "Create account" : "Sign in") { submit() }
                        .frame(maxWidth: .infinity)
                        .disabled(busy || email.isEmpty || password.isEmpty)
                    Button(registering ? "I already have an account" : "New here? Create an account") {
                        registering.toggle()
                        error = nil
                    }
                    .frame(maxWidth: .infinity)
                    .font(.footnote)
                }
                Section("Server") {
                    TextField("Base URL", text: $baseURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.footnote.monospaced())
                }
            }
        }
    }

    private func submit() {
        busy = true
        error = nil
        Task {
            do {
                if registering {
                    try await APIClient.shared.register(email: email, name: name, password: password)
                } else {
                    try await APIClient.shared.login(email: email, password: password)
                }
                session.loggedIn = true
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }
}
