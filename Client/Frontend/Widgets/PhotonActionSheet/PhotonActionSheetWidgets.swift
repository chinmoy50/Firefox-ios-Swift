// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0

import Foundation
import Storage
import SnapKit
import Shared
import UIKit
import MapKit

// UX definitions and misc table components used for the PhotonActionSheet table view.

struct PhotonActionSheetUX {
    static let MaxWidth: CGFloat = 414
    static let Padding: CGFloat = 6
    static let HeaderFooterHeight: CGFloat = 20
    static let RowHeight: CGFloat = 44
    static let BorderWidth: CGFloat = 0.5
    static let BorderColor = UIColor.Photon.Grey30
    static let CornerRadius: CGFloat = 10
    static let SiteImageViewSize = 52
    static let IconSize = CGSize(width: 24, height: 24)
    static let SiteHeaderName  = "PhotonActionSheetSiteHeaderView"
    static let TitleHeaderName = "PhotonActionSheetTitleHeaderView"
    static let CellName = "PhotonActionSheetCell"
    static let CloseButtonHeight: CGFloat  = 56
    static let TablePadding: CGFloat = 6
    static let SeparatorRowHeight: CGFloat = 8
    static let TitleHeaderSectionHeight: CGFloat = 40
    static let TitleHeaderSectionHeightWithSite: CGFloat = 70
    static let BottomPopOverSheetSpacing: CGFloat = 32
    static let iPadSpacing: CGFloat = 16
}

public enum PresentationStyle {
    case centered // used in the home panels
    case bottom // used to display the menu on phone sized devices
    case popover // when displayed on the iPad
}

extension UIModalPresentationStyle {
    func getPhotonPresentationStyle() -> PresentationStyle {
        switch self {
        case .popover:
            return .popover
        case .overFullScreen:
            return .centered
        default:
            return .bottom
        }
    }
}

public enum PhotonActionSheetCellAccessoryType {
    case Disclosure
    case Switch
    case Text
    case None
}

public enum PhotonActionSheetIconType {
    case Image
    case URL
    case TabsButton
    case None
}

// MARK: - PhotonActionSheetTitleHeaderView
class PhotonActionSheetTitleHeaderView: UITableViewHeaderFooterView {
    static let Padding: CGFloat = 18

    lazy var titleLabel: UILabel = {
        let titleLabel = UILabel()
        titleLabel.font = DynamicFontHelper.defaultHelper.SmallSizeRegularWeightAS
        titleLabel.numberOfLines = 1
        titleLabel.textColor = UIColor.theme.tableView.headerTextLight
        return titleLabel
    }()

    lazy var separatorView: UIView = {
        let separatorLine = UIView()
        separatorLine.backgroundColor = UIColor.Photon.Grey40
        return separatorLine
    }()

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)

        self.backgroundView = UIView()
        self.backgroundView?.backgroundColor = .clear
        contentView.addSubview(titleLabel)

        titleLabel.snp.makeConstraints { make in
            make.leading.equalTo(contentView).offset(PhotonActionSheetTitleHeaderView.Padding)
            make.trailing.equalTo(contentView)
            make.top.equalTo(contentView).offset(PhotonActionSheetUX.TablePadding)
        }

        contentView.addSubview(separatorView)

        separatorView.snp.makeConstraints { make in
            make.leading.trailing.equalTo(self)
            make.top.equalTo(titleLabel.snp.bottom).offset(PhotonActionSheetUX.TablePadding)
            make.bottom.equalTo(contentView).inset(PhotonActionSheetUX.TablePadding)
            make.height.equalTo(0.5)
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with title: String) {
        self.titleLabel.text = title
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        self.titleLabel.text = nil
    }
}

// MARK: - PhotonActionSheetSiteHeaderView
class PhotonActionSheetSiteHeaderView: UITableViewHeaderFooterView {
    static let Padding: CGFloat = 12
    static let VerticalPadding: CGFloat = 2

    lazy var titleLabel: UILabel = {
        let titleLabel = UILabel()
        titleLabel.font = DynamicFontHelper.defaultHelper.MediumSizeBoldFontAS
        titleLabel.textAlignment = .left
        titleLabel.numberOfLines = 2
        return titleLabel
    }()

    lazy var descriptionLabel: UILabel = {
        let titleLabel = UILabel()
        titleLabel.font = DynamicFontHelper.defaultHelper.MediumSizeRegularWeightAS
        titleLabel.textAlignment = .left
        titleLabel.numberOfLines = 1
        return titleLabel
    }()

    lazy var siteImageView: UIImageView = {
        let siteImageView = UIImageView()
        siteImageView.contentMode = .center
        siteImageView.clipsToBounds = true
        siteImageView.layer.cornerRadius = PhotonActionSheetUX.CornerRadius
        siteImageView.layer.borderColor = PhotonActionSheetUX.BorderColor.cgColor
        siteImageView.layer.borderWidth = PhotonActionSheetUX.BorderWidth
        return siteImageView
    }()

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)

        self.backgroundView = UIView()
        self.backgroundView?.backgroundColor = .clear
        contentView.addSubview(siteImageView)

        siteImageView.snp.remakeConstraints { make in
            make.top.equalTo(contentView).offset(PhotonActionSheetSiteHeaderView.Padding)
            make.centerY.equalTo(contentView)
            make.leading.equalTo(contentView).offset(PhotonActionSheetSiteHeaderView.Padding)
            make.size.equalTo(PhotonActionSheetUX.SiteImageViewSize)
        }

        let stackView = UIStackView(arrangedSubviews: [titleLabel, descriptionLabel])
        stackView.spacing = PhotonActionSheetSiteHeaderView.VerticalPadding
        stackView.alignment = .leading
        stackView.axis = .vertical

        contentView.addSubview(stackView)

        stackView.snp.makeConstraints { make in
            make.leading.equalTo(siteImageView.snp.trailing).offset(PhotonActionSheetSiteHeaderView.Padding)
            make.trailing.equalTo(contentView).inset(PhotonActionSheetSiteHeaderView.Padding)
            make.centerY.equalTo(siteImageView.snp.centerY)
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        self.siteImageView.image = nil
        self.siteImageView.backgroundColor = UIColor.clear
    }

    func configure(with site: Site) {
        if let _ = site.icon {
            self.siteImageView.setFavicon(forSite: site) { 
                self.siteImageView.image = self.siteImageView.image?.createScaled(PhotonActionSheetUX.IconSize)
            }
        } else if let appDelegate = UIApplication.shared.delegate as? AppDelegate, let profile = appDelegate.profile {
            profile.favicons.getFaviconImage(forSite: site).uponQueue(.main) { result in
                guard let image = result.successValue else {
                    return
                }

                self.siteImageView.backgroundColor = .clear
                self.siteImageView.image = image.createScaled(PhotonActionSheetUX.IconSize)
            }
        }
        self.titleLabel.text = site.title.isEmpty ? site.url : site.title
        self.descriptionLabel.text = site.tileURL.baseDomain
        self.titleLabel.textColor = LegacyThemeManager.instance.current.actionMenu.foreground
        self.descriptionLabel.textColor = LegacyThemeManager.instance.current.actionMenu.foreground
        
    }
}

// MARK: - PhotonActionSheetSeparator
class PhotonActionSheetSeparator: UITableViewHeaderFooterView {

    let separatorLineView = UIView()

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        self.backgroundView = UIView()
        self.backgroundView?.backgroundColor = .clear
        separatorLineView.backgroundColor = UIColor.Photon.Grey40
        self.contentView.addSubview(separatorLineView)
        separatorLineView.snp.makeConstraints { make in
            make.leading.trailing.equalTo(self)
            make.centerY.equalTo(self)
            make.height.equalTo(0.5)
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
