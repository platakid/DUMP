import SwiftUI

struct RootView: View {

    @ObservedObject var model: AppModel

    var body: some View {

        ZStack {

            Color(
                uiColor: .systemGroupedBackground
            )
            .ignoresSafeArea()

            switch model.route {

            case .decoyLock:

                DecoyLock {
                    model.unlockDecoy($0)
                }

            case .notes:

                NotesView(
                    store: model.notes,
                    reveal: model.reveal
                )

            case .landing:

                VStack(spacing: 36) {

                    Text("DUMP")
                        .font(
                            .system(
                                size: 40,
                                weight: .semibold,
                                design: .rounded
                            )
                        )
                        .tracking(5)

                    Button("Enter") {
                        Task {
                            await model.enter()
                        }
                    }
                    .buttonStyle(
                        PrimaryButton()
                    )
                }
                .padding(40)
                .transition(
                    .asymmetric(
                        insertion:
                            .scale(scale: 0.94)
                            .combined(with: .opacity),
                        removal:
                            .opacity
                    )
                )

            case .gate1:

                VStack(spacing: 24) {

                    Text("DUMP")
                        .font(
                            .largeTitle
                                .weight(.semibold)
                        )

                    ProgressView()
                }

            case .setup, .gate2:

                PasscodeView(
                    model: model,
                    setup: model.route == .setup
                )

            case .vault:

                VaultView(
                    model: model
                )
            }
        }

        .tint(.primary)

        /*
         IMPORTANT:

         RootView no longer monitors scenePhase.

         PrivacyDelegate is the single authority responsible for
         lifecycle privacy/security behavior.

         This prevents multiple independent lock() calls during
         authentication.
         */

        .alert(
            "DUMP",
            isPresented: Binding(
                get: {
                    model.message != nil
                },
                set: {
                    if !$0 {
                        model.message = nil
                    }
                }
            )
        ) {

            Button("OK") {
                model.message = nil
            }

        } message: {

            Text(
                model.message ?? ""
            )
        }
    }
}

// MARK: - Primary Button

struct PrimaryButton: ButtonStyle {

    func makeBody(
        configuration: Configuration
    ) -> some View {

        configuration.label
            .font(.headline)

            .frame(
                maxWidth: .infinity
            )

            .padding(
                .vertical,
                17
            )

            .background(
                Color.primary,
                in: RoundedRectangle(
                    cornerRadius: 18
                )
            )

            .foregroundStyle(
                Color(
                    uiColor: .systemBackground
                )
            )

            .opacity(
                configuration.isPressed
                ? 0.7
                : 1
            )

            .scaleEffect(
                configuration.isPressed
                ? 0.98
                : 1
            )

            .animation(
                .spring(
                    response: 0.3,
                    dampingFraction: 0.8
                ),
                value:
                    configuration.isPressed
            )
    }
}

// MARK: - Decoy Lock

struct DecoyLock: View {

    let unlock: (String) -> Bool

    @State private var code = ""
    @State private var incorrect = false

    var body: some View {

        VStack(spacing: 28) {

            Spacer()

            Image(
                systemName: "note.text"
            )
            .font(
                .system(
                    size: 44,
                    weight: .light
                )
            )

            Text("Note Dump")
                .font(
                    .largeTitle
                        .weight(.semibold)
                )

            Text(
                "A place for your thoughts."
            )
            .foregroundStyle(
                .secondary
            )

            SecureField(
                "Code",
                text: $code
            )

            .keyboardType(
                .numberPad
            )

            .textContentType(
                .none
            )

            .multilineTextAlignment(
                .center
            )

            .font(
                .title2
            )

            .padding(18)

            .background(
                .regularMaterial,
                in: RoundedRectangle(
                    cornerRadius: 18
                )
            )

            .onChange(of: code) {
                _,
                new in

                if new.count > 4 {
                    code =
                        String(
                            new.prefix(4)
                        )
                }
            }

            if incorrect {

                Text(
                    "Incorrect code"
                )

                .font(
                    .footnote
                )

                .foregroundStyle(
                    .secondary
                )
            }

            Button("Unlock") {

                let value = code

                code = ""

                incorrect =
                    !unlock(value)

            }
            .buttonStyle(
                PrimaryButton()
            )

            Spacer()
            Spacer()
        }

        .padding(36)

        .frame(
            maxWidth: 480
        )
    }
}

// MARK: - Passcode

struct PasscodeView: View {

    @ObservedObject var model: AppModel

    let setup: Bool

    @State private var password = ""
    @State private var confirmation = ""

    var body: some View {

        VStack(
            alignment: .leading,
            spacing: 24
        ) {

            Spacer()

            Text(
                setup
                ? "Create your DUMP passcode"
                : "Enter your DUMP passcode"
            )
            .font(
                .largeTitle.bold()
            )

            if setup {

                Text(
                    "At least 8 characters, including a number or symbol."
                )

                .foregroundStyle(
                    .secondary
                )
            }

            SecureField(
                "Passcode",
                text: $password
            )

            .textContentType(
                .none
            )

            .textInputAutocapitalization(
                .never
            )

            .autocorrectionDisabled()

            .padding()

            .background(
                .regularMaterial,
                in: RoundedRectangle(
                    cornerRadius: 16
                )
            )

            if setup {

                SecureField(
                    "Confirm passcode",
                    text: $confirmation
                )

                .textContentType(
                    .none
                )

                .textInputAutocapitalization(
                    .never
                )

                .autocorrectionDisabled()

                .padding()

                .background(
                    .regularMaterial,
                    in: RoundedRectangle(
                        cornerRadius: 16
                    )
                )
            }

            Button {

                let p = password
                let c = confirmation

                password = ""
                confirmation = ""

                Task {
                    await model.submit(
                        password: p,
                        confirmation: c
                    )
                }

            } label: {

                if model.busy {

                    ProgressView()
                        .tint(
                            Color(
                                uiColor:
                                    .systemBackground
                            )
                        )

                } else {

                    Text(
                        setup
                        ? "Create passcode"
                        : "Unlock"
                    )
                }
            }

            .buttonStyle(
                PrimaryButton()
            )

            .disabled(
                model.busy ||
                password.isEmpty
            )

            Button("Cancel") {

                password = ""
                confirmation = ""

                model.lock()
            }

            .frame(
                maxWidth: .infinity
            )

            Spacer()
            Spacer()
        }

        .padding(32)

        .frame(
            maxWidth: 480
        )

        .onDisappear {
            password = ""
            confirmation = ""
        }
    }
}
