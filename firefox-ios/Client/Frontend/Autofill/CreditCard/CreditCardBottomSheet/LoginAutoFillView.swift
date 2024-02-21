// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import SwiftUI
import Shared

struct LoginAutoFillView: View {
    @Environment(\.themeType)
    var themeVal

    @ObservedObject var viewModel: LoginListViewModel

    var body: some View {
        VStack {
            AutoFillHeaderView(
                title: String.PasswordAutofill.UseSavedPasswordFromHeader,
                subtitle: String(format: String.PasswordAutofill.SignInWithSavedPassword, "cnn.com")
            )
            LoginListView(viewModel: viewModel)
            AutoFillFooterView(
                title: String.PasswordAutofill.ManagePasswordsButton,
                primaryAction: viewModel.manageLoginInfoAction
            )
        }
        .padding()
        .background(Color(themeVal.theme.colors.layer1))
    }
}

#Preview {
    LoginAutoFillView(
        viewModel: LoginListViewModel(
            loginStorage: MockLoginStorage(),
            logger: MockLogger(),
            onLoginCellTap: { _ in },
            manageLoginInfoAction: { }
        )
    )
}
