// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0

import Foundation

// MARK: - Data
struct ParserData {
    func getDictData(from dict: DictData) -> [String: Any] {
        return try! JSONSerialization.jsonObject(with: dict.getData(),
                                                 options: []) as! [String: Any]
    }

    func getListData(from list: ListData) -> [String] {
        return try! JSONSerialization.jsonObject(with: list.getData(),
                                                 options: []) as! [String]
    }
}

// MARK: - DictData
enum DictData: String {
    case entity
    case emptyEntity

    func getData() -> Data {
        let stringData: String
        switch self {
        case .entity:
            stringData = DictData.entitylist
        case .emptyEntity:
            stringData = DictData.emptyEntitylist
        }
        return stringData.data(using: .utf8)!
    }

    static let entitylist = """
{
"license": "Copyright 2010-2020 Disconnect, Inc.",
"entities":
    {
        "2leep.com": { "properties": [ "2leep.com" ], "resources": [ "2leep.com" ] },
        "adnologies": { "properties": [ "adnologies.com", "heias.com" ], "resources": [ "adnologies.com", "heias.com" ] },
        "365Media": { "properties": [ "aggregateintelligence.com" ], "resources": [ "365media.com", "aggregateintelligence.com" ] },
        "Yandex": { "properties": [ "kinopoisk.ru", "moikrug.ru", "yadi.sk", "yandex.by", "yandex.com", "yandex.com.tr", "yandex.ru", "yandex.st", "yandex.ua" ], "resources": [ "api-maps.yandex.ru", "moikrug.ru", "web-visor.com", "webvisor.org", "yandex.by", "yandex.com", "yandex.com.tr", "yandex.ru", "yandex.st", "yandex.ua" ] }
    }
}
"""

    static let emptyEntitylist = """
{
"license": "Copyright 2010-2020 Disconnect, Inc.",
"entities":
    {
    }
}
"""
}

// MARK: - ListData
enum ListData: String {
    case ads

    func getData() -> Data {
        let stringData: String
        switch self {
        case .ads:
            stringData = ListData.adsTrackDigest256
        }
        return stringData.data(using: .utf8)!
    }

    static let adsTrackDigest256 = """
[
  "2leep.com",
  "adnologies.com",
  "heias.com",
  "365media.com",
  "adfox.yandex.ru"
]
"""
}
