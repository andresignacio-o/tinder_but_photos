import AVKit
import Combine
import Photos
import SwiftUI

struct AssetDetailViewer: View {
    let asset: PHAsset
    let audioEnabled: Bool

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black
                .ignoresSafeArea()

            Group {
                if asset.mediaType == .video {
                    AssetDetailVideoView(asset: asset, audioEnabled: audioEnabled)
                } else {
                    AssetDetailPhotoView(asset: asset)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white.opacity(0.95), .black.opacity(0.55))
                    .padding()
            }
        }
        .overlay(alignment: .bottom) {
            if asset.mediaType != .video {
                Text("Pellizca para zoom")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 24)
            }
        }
        .statusBarHidden()
    }
}

private struct AssetDetailPhotoView: View {
    let asset: PHAsset

    @State private var zoomScale: CGFloat = 1
    @State private var zoomOffset: CGSize = .zero
    @State private var gestureZoomScale: CGFloat = 1
    @State private var gestureOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            AssetImageView(asset: asset, renderSize: geometry.size)
                .scaleEffect(currentScale)
                .offset(x: currentOffset.width, y: currentOffset.height)
                .gesture(doubleTapGesture)
                .simultaneousGesture(magnificationGesture)
                .simultaneousGesture(dragGesture)
                .animation(.spring(response: 0.24, dampingFraction: 0.84), value: zoomScale)
                .animation(.spring(response: 0.24, dampingFraction: 0.84), value: zoomOffset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var currentScale: CGFloat {
        max(1, zoomScale * gestureZoomScale)
    }

    private var currentOffset: CGSize {
        CGSize(
            width: zoomOffset.width + gestureOffset.width,
            height: zoomOffset.height + gestureOffset.height
        )
    }

    private var magnificationGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                gestureZoomScale = value.magnification
            }
            .onEnded { value in
                zoomScale = min(max(zoomScale * value.magnification, 1), 4)
                gestureZoomScale = 1

                if zoomScale == 1 {
                    zoomOffset = .zero
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard currentScale > 1.01 else { return }
                gestureOffset = value.translation
            }
            .onEnded { value in
                guard currentScale > 1.01 else {
                    gestureOffset = .zero
                    return
                }

                zoomOffset.width += value.translation.width
                zoomOffset.height += value.translation.height
                gestureOffset = .zero
            }
    }

    private var doubleTapGesture: some Gesture {
        TapGesture(count: 2)
            .onEnded {
                if zoomScale > 1 {
                    zoomScale = 1
                    zoomOffset = .zero
                } else {
                    zoomScale = 2.5
                }
            }
    }
}

private struct AssetDetailVideoView: View {
    let asset: PHAsset
    let audioEnabled: Bool

    @StateObject private var controller = AssetDetailVideoController()

    var body: some View {
        Group {
            if let player = controller.player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .task(id: asset.localIdentifier) {
            controller.load(asset: asset, audioEnabled: audioEnabled)
        }
        .onChange(of: audioEnabled) { _, newValue in
            controller.setAudioEnabled(newValue)
        }
        .onDisappear {
            controller.stop()
        }
    }
}

@MainActor
private final class AssetDetailVideoController: ObservableObject {
    @Published private(set) var player: AVPlayer?

    private let imageManager = PHCachingImageManager()
    private var requestID: PHImageRequestID?
    private var currentAssetID: String?

    func load(asset: PHAsset, audioEnabled: Bool) {
        guard asset.mediaType == .video else { return }

        if currentAssetID == asset.localIdentifier, let player {
            player.isMuted = !audioEnabled
            player.play()
            return
        }

        stop()

        let options = PHVideoRequestOptions()
        options.deliveryMode = .automatic
        options.isNetworkAccessAllowed = true

        requestID = imageManager.requestPlayerItem(forVideo: asset, options: options) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                guard let item else { return }

                let player = AVPlayer(playerItem: item)
                player.isMuted = !audioEnabled

                self.requestID = nil
                self.currentAssetID = asset.localIdentifier
                self.player = player
                player.play()
            }
        }
    }

    func setAudioEnabled(_ enabled: Bool) {
        player?.isMuted = !enabled
    }

    func stop() {
        if let requestID {
            imageManager.cancelImageRequest(requestID)
            self.requestID = nil
        }

        player?.pause()
        player = nil
        currentAssetID = nil
    }
}
