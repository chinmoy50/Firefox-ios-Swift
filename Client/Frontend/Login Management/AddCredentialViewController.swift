// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0

import UIKit
import Shared
import Storage

enum AddCredentialField: Int {
    case websiteItem
    case usernameItem
    case passwordItem

    var indexPath: IndexPath {
        return IndexPath(row: rawValue, section: 0)
    }
}

class AddCredentialViewController: UIViewController, Themeable {

    var themeManager: ThemeManager
    var themeObserver: NSObjectProtocol?
    var notificationCenter: NotificationProtocol

    lazy var tableView: UITableView = .build { [weak self] tableView in
        guard let self = self else { return }
        tableView.accessibilityIdentifier = "Add Credential"
        tableView.delegate = self
        tableView.dataSource = self
        tableView.estimatedRowHeight = 44.0
        // Add empty footer view to prevent separators from being drawn past the last item.
        tableView.tableFooterView = UIView()
        tableView.separatorInset = .zero
    }
    fileprivate weak var websiteField: UITextField!
    fileprivate weak var usernameField: UITextField!
    fileprivate weak var passwordField: UITextField!

    fileprivate let didSaveAction: (LoginEntry) -> Void

    fileprivate lazy var cancelButton: UIBarButtonItem = {
        let button = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
        return button
    }()

    fileprivate lazy var saveButton: UIBarButtonItem = {
        let button = UIBarButtonItem(title: .SettingsAddCustomEngineSaveButtonText, style: .done, target: self, action: #selector(addCredential))
        button.isEnabled = false
        return button
    }()

    init(didSaveAction: @escaping (LoginEntry) -> Void,
         themeManager: ThemeManager = AppContainer.shared.resolve(),
         notificationCenter: NotificationCenter = NotificationCenter.default) {
        self.didSaveAction = didSaveAction
        self.themeManager = themeManager
        self.notificationCenter = notificationCenter
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.rightBarButtonItem = saveButton
        navigationItem.leftBarButtonItem = cancelButton

        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        applyTheme()
        listenForThemeChange()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // Normally UITableViewControllers handle responding to content inset changes from keyboard events when editing
        // but since we don't use the tableView's editing flag for editing we handle this ourselves.
        KeyboardHelper.defaultHelper.addDelegate(self)
    }

    @objc func addCredential() {
        guard let hostname = websiteField.text,
              let username = usernameField.text,
              let password = passwordField.text else {
            return
        }

        didSaveAction(
            LoginEntry(
                fromLoginEntryFlattened: LoginEntryFlattened(
                    id: "",
                    hostname: hostname,
                    password: password,
                    username: username,
                    httpRealm: nil,
                    formSubmitUrl: hostname,
                    usernameField: "",
                    passwordField: ""
                )
            )
        )
    }

    @objc func cancel() {
        dismiss(animated: true)
    }

    /// Normalize the website entered by adding `https://` URL scheme. This format is necessary in ordered to be saved on local passwords storage.
    /// - Parameter website: Website address provided by the user in a String format
    /// - Returns: Normalized website containing `https://` URL scheme if necessary
    private func normalize(website: String) -> String {
        guard !website.isEmpty else { return website }
        if website.hasPrefix("http://") || website.hasPrefix("https://") {
            return website
        } else {
            return "https://" + website
        }
    }
}

// MARK: - UITableViewDataSource
extension AddCredentialViewController: UITableViewDataSource {

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch AddCredentialField(rawValue: indexPath.row)! {

        case .usernameItem:
            let loginCell = cell(forIndexPath: indexPath)
            loginCell.highlightedLabelTitle = .LoginDetailUsername
            loginCell.descriptionLabel.keyboardType = .emailAddress
            loginCell.descriptionLabel.returnKeyType = .next
            loginCell.isEditingFieldData = true
            usernameField = loginCell.descriptionLabel
            usernameField?.accessibilityIdentifier = "usernameField"
            loginCell.applyTheme(theme: themeManager.currentTheme)
            return loginCell

        case .passwordItem:
            let loginCell = cell(forIndexPath: indexPath)
            loginCell.highlightedLabelTitle = .LoginDetailPassword
            loginCell.descriptionLabel.returnKeyType = .default
            loginCell.displayDescriptionAsPassword = true
            loginCell.isEditingFieldData = true
            passwordField = loginCell.descriptionLabel
            passwordField?.accessibilityIdentifier = "passwordField"
            loginCell.applyTheme(theme: themeManager.currentTheme)
            return loginCell

        case .websiteItem:
            let loginCell = cell(forIndexPath: indexPath)
            loginCell.highlightedLabelTitle = .LoginDetailWebsite
            websiteField = loginCell.descriptionLabel
            loginCell.placeholder = "https://www.example.com"
            websiteField?.accessibilityIdentifier = "websiteField"
            websiteField?.keyboardType = .URL
            loginCell.isEditingFieldData = true
            loginCell.applyTheme(theme: themeManager.currentTheme)
            return loginCell
        }
    }

    fileprivate func cell(forIndexPath indexPath: IndexPath) -> LoginDetailTableViewCell {
        let loginCell = LoginDetailTableViewCell()
        loginCell.selectionStyle = .none
        loginCell.delegate = self
        return loginCell
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 3
    }

    func applyTheme() {
        let theme = themeManager.currentTheme
        tableView.separatorColor = theme.colors.borderPrimary
        tableView.backgroundColor = theme.colors.layer1

        cancelButton.tintColor = theme.colors.actionPrimary
        saveButton.tintColor = theme.colors.actionPrimary

        updateThemeApplicableSubviews()
    }
}

// MARK: - UITableViewDelegate
extension AddCredentialViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return LoginDetailUX.InfoRowHeight
    }
}

// MARK: - KeyboardHelperDelegate
extension AddCredentialViewController: KeyboardHelperDelegate {

    func keyboardHelper(_ keyboardHelper: KeyboardHelper, keyboardWillShowWithState state: KeyboardState) {
        let coveredHeight = state.intersectionHeightForView(tableView)
        tableView.contentInset.bottom = coveredHeight
    }

    func keyboardHelper(_ keyboardHelper: KeyboardHelper, keyboardWillHideWithState state: KeyboardState) {
        tableView.contentInset.bottom = 0
    }
}

// MARK: - Cell Delegate
extension AddCredentialViewController: LoginDetailTableViewCellDelegate {
    func textFieldDidEndEditing(_ cell: LoginDetailTableViewCell) {
        guard cell.descriptionLabel == websiteField, let website = websiteField?.text else { return }
        websiteField.text = normalize(website: website)
    }

    func textFieldDidChange(_ cell: LoginDetailTableViewCell) {
        // TODO: Add validation if necessary
        let enableSave =
            !(websiteField.text?.isEmpty ?? true) &&
            !(usernameField.text?.isEmpty ?? true) &&
            !(passwordField.text?.isEmpty ?? true)

        saveButton.isEnabled = enableSave
    }

    func canPerform(action: Selector, for cell: LoginDetailTableViewCell) -> Bool {
        guard let item = infoItemForCell(cell) else {
            return false
        }

        // Menu actions for password
        if item == .passwordItem {
            let showRevealOption = cell.descriptionLabel.isSecureTextEntry ? (action == MenuHelper.SelectorReveal) : (action == MenuHelper.SelectorHide)
            return action == MenuHelper.SelectorCopy || showRevealOption
        }

        // Menu actions for Website
        if item == .websiteItem {
            return action == MenuHelper.SelectorCopy || action == MenuHelper.SelectorOpenAndFill
        }

        // Menu actions for Username
        if item == .usernameItem {
            return action == MenuHelper.SelectorCopy
        }

        return false
    }

    fileprivate func cellForItem(_ item: AddCredentialField) -> LoginDetailTableViewCell? {
        return tableView.cellForRow(at: item.indexPath) as? LoginDetailTableViewCell
    }

    func didSelectOpenAndFillForCell(_ cell: LoginDetailTableViewCell) { }

    func shouldReturnAfterEditingDescription(_ cell: LoginDetailTableViewCell) -> Bool {
        switch cell.descriptionLabel {
        case websiteField:
            usernameField.becomeFirstResponder()
        case usernameField:
            passwordField.becomeFirstResponder()
        case passwordField:
            return false
        default:
            return false
        }
        return false
    }

    func infoItemForCell(_ cell: LoginDetailTableViewCell) -> AddCredentialField? {
        if let index = tableView.indexPath(for: cell),
            let item = AddCredentialField(rawValue: index.row) {
            return item
        }
        return nil
    }
}
