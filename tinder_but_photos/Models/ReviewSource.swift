//
//  ReviewSource.swift
//  tinder_but_photos
//

import Foundation

struct ReviewSource: Identifiable, Hashable {
    enum Kind: Hashable {
        case allPhotos
        case screenshots
        case videos
        case album(localIdentifier: String)
    }

    let kind: Kind
    let title: String

    var id: String {
        switch kind {
        case .allPhotos:
            return "allPhotos"
        case .screenshots:
            return "screenshots"
        case .videos:
            return "videos"
        case let .album(localIdentifier):
            return localIdentifier
        }
    }

    static let allPhotos = ReviewSource(kind: .allPhotos, title: "Toda la galeria")
    static let screenshots = ReviewSource(kind: .screenshots, title: "Screenshots")
    static let videos = ReviewSource(kind: .videos, title: "Videos")
}
