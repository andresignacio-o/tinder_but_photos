//
//  PhotoCard.swift
//  tinder_but_photos
//

import AVKit
import Combine
import Photos
import SwiftUI

struct PhotoCard: View {
    let asset: PHAsset
    let audioEnabled: Bool
    let onPreview: () -> Void
    let onRemove: (ReviewAction) -> Void

    @State private var offset: CGSize = .zero
    @StateObject private var videoPreview = VideoPreviewController()

    private let cardAspectRatio: CGFloat = 320 / 520

    var body: some View {
        GeometryReader { geometry in
            let cardSize = resolvedCardSize(in: geometry.size)

            ZStack {
                AssetImageView(asset: asset, renderSize: cardSize)

                if asset.mediaType == .video {
                    if let player = videoPreview.player, videoPreview.isPreviewing {
                        VideoPlayer(player: player)
                            .allowsHitTesting(false)
                    }
                }
            }
            .frame(width: cardSize.width, height: cardSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(alignment: .top) {
                swipeHint
            }
            .overlay(alignment: .bottomLeading) {
                if asset.mediaType == .video {
                    videoBadge
                }
            }
            .shadow(color: .black.opacity(0.18), radius: 16, y: 10)
            .offset(x: offset.width, y: offset.height * 0.25)
            .rotationEffect(.degrees(Double(offset.width / 18)))
            .gesture(
                DragGesture()
                    .onChanged { gesture in
                        offset = gesture.translation
                    }
                    .onEnded { _ in
                        let threshold: CGFloat = 120

                        if offset.width > threshold {
                            offset = CGSize(width: 500, height: offset.height)
                            onRemove(.keep)
                        } else if offset.width < -threshold {
                            offset = CGSize(width: -500, height: offset.height)
                            onRemove(.delete)
                        } else if offset.height < -threshold {
                            offset = CGSize(width: offset.width, height: -700)
                            onRemove(.saveToPawZone)
                        } else {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                offset = .zero
                            }
                        }
                    }
            )
            .onLongPressGesture(minimumDuration: 0.18, maximumDistance: 24, pressing: handleVideoPress) {
            }
            .onTapGesture {
                onPreview()
            }
            .onDisappear {
                videoPreview.stopPreview()
            }
            .onChange(of: audioEnabled) { _, newValue in
                videoPreview.setAudioEnabled(newValue)
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: offset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private func resolvedCardSize(in availableSize: CGSize) -> CGSize {
        let maxWidth = min(availableSize.width, 420)
        let maxHeight = min(availableSize.height, 680)

        guard maxWidth > 0, maxHeight > 0 else {
            return CGSize(width: 320, height: 520)
        }

        let widthFromHeight = maxHeight * cardAspectRatio
        let width = min(maxWidth, widthFromHeight)
        let height = width / cardAspectRatio

        return CGSize(width: width, height: height)
    }

    private var swipeHint: some View {
        VStack {
            label(text: "PAWZONE", color: .blue)
                .opacity(Double(max(-offset.height, 0) / 100))

            HStack {
                label(text: "BORRAR", color: .red)
                    .opacity(Double(max(-offset.width, 0) / 100))

                Spacer()

                label(text: "KEEP", color: .green)
                    .opacity(Double(max(offset.width, 0) / 100))
            }
        }
        .padding()
    }

    private var videoBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "video.fill")
            Text(videoPreview.isPreviewing ? "VIDEO 2X" : "VIDEO")
        }
        .font(.caption.bold())
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .padding()
    }

    private func label(text: String, color: Color) -> some View {
        Text(text)
            .font(.headline.bold())
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .foregroundStyle(color)
    }

    private func handleVideoPress(_ isPressing: Bool) {
        guard asset.mediaType == .video else { return }

        if isPressing {
            videoPreview.setAudioEnabled(audioEnabled)
            videoPreview.startPreview(for: asset)
        } else {
            videoPreview.stopPreview()
        }
    }
}

struct AssetImageView: View {
    let asset: PHAsset
    let renderSize: CGSize

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID?

    private let imageManager = PHCachingImageManager()

    var body: some View {
        Group {
            if let image {
                ZStack {
                    Color.black

                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                }
            } else {
                ZStack {
                    LinearGradient(
                        colors: [.gray.opacity(0.25), .gray.opacity(0.12)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    ProgressView()
                }
            }
        }
        .clipped()
        .task(id: requestKey) {
            loadImage()
        }
        .onDisappear {
            cancelRequest()
        }
    }

    private var requestKey: String {
        "\(asset.localIdentifier)-\(Int(renderSize.width))x\(Int(renderSize.height))"
    }

    private func loadImage() {
        cancelRequest()

        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true

        let targetSize = CGSize(
            width: max(renderSize.width * displayScale, 1),
            height: max(renderSize.height * displayScale, 1)
        )
        requestID = imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFit,
            options: options
        ) { result, _ in
            image = result
        }
    }

    private func cancelRequest() {
        guard let requestID else { return }
        imageManager.cancelImageRequest(requestID)
        self.requestID = nil
    }
}

@MainActor
final class VideoPreviewController: ObservableObject {
    @Published private(set) var isPreviewing = false
    @Published private(set) var player: AVPlayer?

    private let imageManager = PHCachingImageManager()
    private var requestID: PHImageRequestID?
    private var currentAssetID: String?
    private var audioEnabled = false

    func startPreview(for asset: PHAsset) {
        guard asset.mediaType == .video else { return }

        isPreviewing = true

        if currentAssetID == asset.localIdentifier, let player {
            player.isMuted = !audioEnabled
            player.seek(to: .zero)
            player.playImmediately(atRate: 2.0)
            return
        }

        cancelRequest()

        let options = PHVideoRequestOptions()
        options.deliveryMode = .automatic
        options.isNetworkAccessAllowed = true

        requestID = imageManager.requestPlayerItem(forVideo: asset, options: options) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                guard self.isPreviewing else { return }
                guard let item else { return }

                let player = AVPlayer(playerItem: item)
                player.isMuted = !self.audioEnabled
                player.actionAtItemEnd = .pause

                self.requestID = nil
                self.player = player
                self.currentAssetID = asset.localIdentifier
                player.playImmediately(atRate: 2.0)
            }
        }
    }

    func setAudioEnabled(_ enabled: Bool) {
        audioEnabled = enabled
        player?.isMuted = !enabled
    }

    func stopPreview() {
        isPreviewing = false
        player?.pause()
        player?.seek(to: .zero)
    }

    private func cancelRequest() {
        guard let requestID else { return }
        imageManager.cancelImageRequest(requestID)
        self.requestID = nil
    }
}
