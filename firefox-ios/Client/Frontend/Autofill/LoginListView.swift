// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import SwiftUI
import Common

// MARK: - LoginListView

/// A view displaying a list of login information.
struct LoginListView: View {
    // MARK: - Properties

    let windowUUID: WindowUUID
    @Environment(\.themeManager) var themeManager
    @ObservedObject var viewModel: LoginListViewModel
    @State private var customLightGray: Color = .clear

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                ForEach(viewModel.logins, id: \.self) { login in
                    LoginCellView(
                        login: login,
                        onTap: { viewModel.onLoginCellTap(login) }
                    )
                }
                .font(.caption)
                .foregroundColor(customLightGray)
            }
        }
        .task {
            await viewModel.fetchLogins()
            applyTheme(theme: themeManager.currentTheme(for: windowUUID))
        }
        .onReceive(NotificationCenter.default.publisher(for: .ThemeDidChange)) { notification in
            guard let uuid = notification.object as? UUID, uuid == windowUUID else { return }
            applyTheme(theme: themeManager.currentTheme(for: windowUUID))
        }
    }

    func applyTheme(theme: Theme) {
        let color = theme.colors
        customLightGray = Color(color.textSecondary)
    }
}

struct LoginListView_Previews: PreviewProvider {
    static var previews: some View {
        LoginListView(
            viewModel: LoginListViewModel(
                tabURL: URL(string: "http://www.example.com", invalidCharacters: false)!,
                loginStorage: MockLoginStorage(),
                logger: MockLogger(),
                onLoginCellTap: { _ in },
                manageLoginInfoAction: { }
            )
        )
    }
}
