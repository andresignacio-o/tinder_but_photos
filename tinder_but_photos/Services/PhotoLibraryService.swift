//
//  PhotoLibraryService.swift
//  tinder_but_photos
//

import Foundation
import Photos

final class PhotoLibraryService {
    private let pawZoneAlbumName = "PawZone"

    func authorizationStatus() -> PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func requestAuthorization(_ completion: @escaping (PHAuthorizationStatus) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            DispatchQueue.main.async {
                completion(status)
            }
        }
    }

    func fetchAvailableSources() -> [ReviewSource] {
        var sources: [ReviewSource] = [.allPhotos, .screenshots, .videos]
        let result = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)

        result.enumerateObjects { collection, _, _ in
            let title = collection.localizedTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let title, !title.isEmpty else { return }
            sources.append(
                ReviewSource(
                    kind: .album(localIdentifier: collection.localIdentifier),
                    title: title
                )
            )
        }

        return sources
    }

    func fetchAssets(for source: ReviewSource) -> PHFetchResult<PHAsset>? {
        let result: PHFetchResult<PHAsset>

        switch source.kind {
        case .allPhotos:
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            result = PHAsset.fetchAssets(with: fetchOptions)
        case .screenshots:
            let fetchOptions = PHFetchOptions()
            fetchOptions.predicate = NSPredicate(
                format: "(mediaSubtype & %d) != 0",
                PHAssetMediaSubtype.photoScreenshot.rawValue
            )
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            result = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        case .videos:
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            result = PHAsset.fetchAssets(with: .video, options: fetchOptions)
        case let .album(localIdentifier):
            guard let collection = fetchAssetCollection(with: localIdentifier) else {
                return nil
            }

            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            result = PHAsset.fetchAssets(in: collection, options: fetchOptions)
        }

        return result
    }

    private func fetchAssetCollection(with localIdentifier: String) -> PHAssetCollection? {
        let result = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [localIdentifier], options: nil)
        return result.firstObject
    }

    func delete(_ assets: [PHAsset], completion: @escaping (Bool) -> Void) {
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.deleteAssets(assets as NSArray)
        }) { success, _ in
            Task { @MainActor in
                completion(success)
            }
        }
    }

    func addToPawZoneAlbum(_ asset: PHAsset, completion: @escaping (Bool) -> Void) {
        guard let album = fetchAlbum(named: pawZoneAlbumName) else {
            completion(false)
            return
        }

        PHPhotoLibrary.shared().performChanges({
            guard let changeRequest = PHAssetCollectionChangeRequest(for: album) else { return }
            changeRequest.addAssets([asset] as NSArray)
        }) { success, _ in
            Task { @MainActor in
                completion(success)
            }
        }
    }

    private func fetchAlbum(named name: String) -> PHAssetCollection? {
        let result = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        var match: PHAssetCollection?

        result.enumerateObjects { collection, _, stop in
            guard collection.localizedTitle == name else { return }
            match = collection
            stop.pointee = true
        }

        return match
    }
}
