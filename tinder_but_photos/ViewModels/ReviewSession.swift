//
//  ReviewSession.swift
//  tinder_but_photos
//

import Combine
import Photos

enum AssetPresentationOrder {
    case newestFirst
    case random
}

private struct AssetTraversal {
    private let count: Int
    private let order: AssetPresentationOrder
    private let startIndex: Int
    private let step: Int
    private(set) var consumedCount = 0

    init(count: Int, order: AssetPresentationOrder) {
        self.count = count
        self.order = order

        guard count > 1, order == .random else {
            startIndex = 0
            step = 1
            return
        }

        startIndex = Int.random(in: 0 ..< count)
        step = Self.randomCoprimeStep(for: count)
    }

    mutating func nextIndex() -> Int? {
        guard consumedCount < count else { return nil }

        let index: Int
        switch order {
        case .newestFirst:
            index = consumedCount
        case .random:
            index = (startIndex + consumedCount * step) % count
        }

        consumedCount += 1
        return index
    }

    private static func randomCoprimeStep(for count: Int) -> Int {
        guard count > 2 else { return 1 }

        while true {
            let candidate = Int.random(in: 1 ..< count)
            if gcd(candidate, count) == 1 {
                return candidate
            }
        }
    }

    private static func gcd(_ lhs: Int, _ rhs: Int) -> Int {
        var a = lhs
        var b = rhs

        while b != 0 {
            let remainder = a % b
            a = b
            b = remainder
        }

        return a
    }
}

@MainActor
final class ReviewSession: ObservableObject {
    @Published private(set) var availableSources: [ReviewSource] = [.screenshots]
    @Published var selectedSource: ReviewSource = .screenshots
    @Published private(set) var visibleAssets: [PHAsset] = []
    @Published private(set) var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @Published private(set) var pendingDeletionCount = 0
    @Published private(set) var assetsMarkedForDeletion: [PHAsset] = [] {
        didSet {
            pendingDeletionCount = assetsMarkedForDeletion.count
        }
    }
    @Published private(set) var undoCandidate: PHAsset?
    @Published private(set) var isDeleting = false
    @Published private(set) var isLoadingAssets = false
    @Published private(set) var isSavingToPawZone = false
    @Published private(set) var assetPresentationOrder: AssetPresentationOrder = .newestFirst

    private var currentFetchResult: PHFetchResult<PHAsset>?
    private var currentTraversal = AssetTraversal(count: 0, order: .newestFirst)
    private var excludedAssetIDs: Set<String> = []
    private var undoDismissTask: Task<Void, Never>?

    private let visibleStackSize = 3
    private let refillThreshold = 2
    private let pageSize = 12

    private let photoLibraryService: PhotoLibraryService
    private let reviewedAssetStore: ReviewedAssetStore
    private var assetLoadTask: Task<Void, Never>?
    private var loadSequence = 0

    init() {
        self.photoLibraryService = PhotoLibraryService()
        self.reviewedAssetStore = ReviewedAssetStore()
    }

    init(
        photoLibraryService: PhotoLibraryService,
        reviewedAssetStore: ReviewedAssetStore
    ) {
        self.photoLibraryService = photoLibraryService
        self.reviewedAssetStore = reviewedAssetStore
    }

    func requestAccessAndLoadIfNeeded() {
        let currentStatus = photoLibraryService.authorizationStatus()

        switch currentStatus {
        case .authorized, .limited:
            authorizationStatus = currentStatus
            loadSourcesAndAssets()
        case .notDetermined:
            photoLibraryService.requestAuthorization { [weak self] status in
                guard let self else { return }
                authorizationStatus = status

                if status == .authorized || status == .limited {
                    loadSourcesAndAssets()
                }
            }
        default:
            authorizationStatus = currentStatus
        }
    }

    func keep(_ asset: PHAsset) {
        reviewedAssetStore.markKept(asset.localIdentifier)
        removeFromQueue(asset)
    }

    func markForDeletion(_ asset: PHAsset) {
        if !assetsMarkedForDeletion.contains(where: { $0.localIdentifier == asset.localIdentifier }) {
            assetsMarkedForDeletion.append(asset)
        }

        removeFromQueue(asset)
        presentUndo(for: asset)
    }

    func undoLatestDeletionMark() {
        guard let undoCandidate else { return }
        unmarkForDeletion(undoCandidate)
    }

    func dismissUndoCandidate() {
        clearUndoCandidate()
    }

    func unmarkForDeletion(_ asset: PHAsset) {
        guard let index = assetsMarkedForDeletion.firstIndex(where: { $0.localIdentifier == asset.localIdentifier }) else {
            return
        }

        let restoredAsset = assetsMarkedForDeletion.remove(at: index)
        if undoCandidate?.localIdentifier == restoredAsset.localIdentifier {
            clearUndoCandidate()
        }

        guard !visibleAssets.contains(where: { $0.localIdentifier == restoredAsset.localIdentifier }) else {
            return
        }

        visibleAssets.insert(restoredAsset, at: 0)
    }

    func saveToPawZone(_ asset: PHAsset) {
        guard !isSavingToPawZone else { return }

        isSavingToPawZone = true
        photoLibraryService.addToPawZoneAlbum(asset) { [weak self] success in
            guard let self else { return }

            isSavingToPawZone = false
            guard success else { return }

            reviewedAssetStore.markKept(asset.localIdentifier)
            removeFromQueue(asset)
        }
    }

    func toggleAssetPresentationOrder() {
        assetPresentationOrder = assetPresentationOrder == .newestFirst ? .random : .newestFirst
        loadAssets(for: selectedSource)
    }

    func deleteMarkedAssets() {
        guard !assetsMarkedForDeletion.isEmpty, !isDeleting else { return }

        let pendingDelete = assetsMarkedForDeletion
        isDeleting = true
        clearUndoCandidate()

        photoLibraryService.delete(pendingDelete) { [weak self] success in
            guard let self else { return }

            isDeleting = false
            guard success else { return }

            let deletedIDs = Set(pendingDelete.map(\.localIdentifier))
            assetsMarkedForDeletion.removeAll()
            visibleAssets.removeAll { deletedIDs.contains($0.localIdentifier) }
            appendNextPageIfNeeded()
        }
    }

    func selectSource(_ source: ReviewSource) {
        guard selectedSource != source else { return }
        selectedSource = source
        loadAssets(for: source)
    }

    private func loadSourcesAndAssets() {
        let sources = photoLibraryService.fetchAvailableSources()
        availableSources = sources

        if !sources.contains(selectedSource) {
            selectedSource = .screenshots
        }

        loadAssets(for: selectedSource)
    }

    private func loadAssets(for source: ReviewSource) {
        assetLoadTask?.cancel()
        loadSequence += 1

        let currentLoadSequence = loadSequence
        isLoadingAssets = true
        excludedAssetIDs = reviewedAssetStore.keptAssetIDs
        currentFetchResult = nil
        currentTraversal = AssetTraversal(count: 0, order: assetPresentationOrder)
        visibleAssets.removeAll()
        assetsMarkedForDeletion.removeAll()
        clearUndoCandidate()

        assetLoadTask = Task(priority: .userInitiated) { @MainActor [source] in
            let fetchResult = photoLibraryService.fetchAssets(for: source)

            guard !Task.isCancelled else { return }
            guard currentLoadSequence == self.loadSequence else { return }

            self.currentFetchResult = fetchResult
            self.currentTraversal = AssetTraversal(
                count: fetchResult?.count ?? 0,
                order: self.assetPresentationOrder
            )
            self.appendNextPageIfNeeded()
            self.isLoadingAssets = false
        }
    }

    private func removeFromQueue(_ asset: PHAsset) {
        visibleAssets.removeAll { $0.localIdentifier == asset.localIdentifier }

        if visibleAssets.count < refillThreshold {
            appendNextPageIfNeeded()
        }
    }

    private func appendNextPageIfNeeded() {
        let targetCount = max(visibleStackSize, visibleStackSize + refillThreshold)
        guard visibleAssets.count < targetCount else { return }

        let neededCount = targetCount - visibleAssets.count
        let batchCount = max(pageSize, neededCount)
        let nextAssets = nextBatch(limit: batchCount)
        guard !nextAssets.isEmpty else { return }

        visibleAssets.append(contentsOf: nextAssets)
    }

    private func presentUndo(for asset: PHAsset) {
        undoDismissTask?.cancel()
        undoCandidate = asset

        let localIdentifier = asset.localIdentifier
        undoDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)

            guard let self, !Task.isCancelled else { return }
            guard self.undoCandidate?.localIdentifier == localIdentifier else { return }

            self.undoCandidate = nil
        }
    }

    private func clearUndoCandidate() {
        undoDismissTask?.cancel()
        undoDismissTask = nil
        undoCandidate = nil
    }

    private func nextBatch(limit: Int) -> [PHAsset] {
        guard limit > 0, let fetchResult = currentFetchResult else { return [] }

        var assets: [PHAsset] = []
        assets.reserveCapacity(limit)

        while assets.count < limit, let index = currentTraversal.nextIndex() {
            let asset = fetchResult.object(at: index)
            guard !excludedAssetIDs.contains(asset.localIdentifier) else { continue }
            assets.append(asset)
        }

        return assets
    }
}
