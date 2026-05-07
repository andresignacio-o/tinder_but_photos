//
//  ReviewedAssetStore.swift
//  tinder_but_photos
//

import Foundation

final class ReviewedAssetStore {
    private enum Keys {
        static let keptAssetIDs = "keptAssetIDs"
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var keptAssetIDs: Set<String> {
        Set(userDefaults.stringArray(forKey: Keys.keptAssetIDs) ?? [])
    }

    func markKept(_ assetID: String) {
        var ids = keptAssetIDs
        ids.insert(assetID)
        userDefaults.set(Array(ids), forKey: Keys.keptAssetIDs)
    }
}
