// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import UIKit
import Common
import Shared

/// Custom UIBarButtonItem with an autofill accessory view.
///
/// This class provides a reusable and configurable autofill accessory view for use in navigation bars.
///
/// # Attributes
/// - `accessoryImageViewSize`: Size of the accessory image view.
/// - `accessoryButtonStackViewSpacing`: Spacing between the accessory image view and text label in the stack view.
/// - `cornerRadius`: Corner radius for the accessory view.
///
/// # Properties
/// - `accessoryImageViewTintColor`: Tint color for the accessory image view.
/// - `backgroundColor`: Background color for the accessory view.
///
/// # Methods
/// - `init(image:labelText:tappedAction:)`: Initializes the accessory view with an image, label, and optional tap action.
/// - `tappedAccessoryButton()`: Handles the tap action on the accessory view.
class AutofillAccessoryView: UIBarButtonItem {
    // MARK: - Constants
    private struct UX {
        static let accessoryImageViewSize: CGFloat = 24
        static let accessoryButtonStackViewSpacing: CGFloat = 2
        static let cornerRadius: CGFloat = 4
        static let fontSize: CGFloat = 16
    }

    // MARK: - Properties
    private let accessoryImageView: UIImageView
    private let useAccessoryTextLabel: UILabel
    private let tappedAccessoryButtonAction: (() -> Void)?

    /// Tint color for the accessory image view.
    var accessoryImageViewTintColor: UIColor? {
        get {
            return accessoryImageView.tintColor
        }
        set {
            accessoryImageView.tintColor = newValue
        }
    }

    /// Background color for the accessory view.
    var backgroundColor: UIColor? {
        didSet {
            updateBackgroundColor()
        }
    }

    // MARK: - Initialization
    /// Initializes the accessory view with an image, label, and optional tap action.
    /// - Parameters:
    ///   - image: The image for the accessory image view.
    ///   - labelText: The text for the accessory view label.
    ///   - tappedAction: The closure to be executed when the accessory view is tapped.
    init(image: UIImage?, labelText: String, tappedAction: (() -> Void)? = nil) {
        self.accessoryImageView = .build { imageView in
            imageView.image = image?.withRenderingMode(.alwaysTemplate)
            imageView.contentMode = .scaleAspectFit
            imageView.accessibilityElementsHidden = true

            NSLayoutConstraint.activate([
                imageView.widthAnchor.constraint(equalToConstant: UX.accessoryImageViewSize),
                imageView.heightAnchor.constraint(equalToConstant: UX.accessoryImageViewSize)
            ])
        }

        self.useAccessoryTextLabel = .build { label in
            label.font = DefaultDynamicFontHelper.preferredFont(withTextStyle: .title3, size: UX.fontSize, weight: .medium)
            label.text = labelText
            label.numberOfLines = 0
            label.accessibilityTraits = .button
        }

        self.tappedAccessoryButtonAction = tappedAction
        super.init()
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup
    private func setup() {
        let stackViewTapped = UITapGestureRecognizer(target: self, action: #selector(tappedAccessoryButton))
        let accessoryView = UIStackView(arrangedSubviews: [accessoryImageView, useAccessoryTextLabel])
        accessoryView.spacing = UX.accessoryButtonStackViewSpacing
        accessoryView.distribution = .equalCentering
        accessoryView.layer.cornerRadius = UX.cornerRadius
        accessoryView.addGestureRecognizer(stackViewTapped)
        self.customView = accessoryView
    }

    private func updateBackgroundColor() {
        if let backgroundColor = backgroundColor {
            customView?.backgroundColor = backgroundColor
        }
    }

    // MARK: - Actions
    @objc
    private func tappedAccessoryButton() {
        tappedAccessoryButtonAction?()
    }
}
