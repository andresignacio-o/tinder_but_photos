//
//  ContentView.swift
//  tinder_but_photos
//
//  Created by Andrés Oñate Escobedo on 11-04-26.
//

import Photos
import SwiftUI

enum ReviewAction {
    case keep
    case delete
    case saveToPawZone
}

struct ContentView: View {
    @StateObject private var session = ReviewSession()
    @State private var videoPreviewAudioEnabled = false
    @State private var isShowingDeletionReview = false
    @State private var undoBannerOffset: CGSize = .zero
    @State private var previewAsset: PHAsset?

    private var displayedPhotos: [PHAsset] {
        Array(session.visibleAssets.prefix(3))
    }

    private var showsVideoAudioToggle: Bool {
        switch session.selectedSource.kind {
        case .videos:
            return true
        case .allPhotos, .screenshots, .album:
            return displayedPhotos.contains(where: { $0.mediaType == .video })
        }
    }

    private var reviewDeletionButtonLabel: String {
        let unit: String

        switch session.selectedSource.kind {
        case .allPhotos:
            unit = "elementos"
        case .videos:
            unit = "videos"
        case .screenshots:
            unit = "screenshots"
        case .album:
            unit = "elementos"
        }

        return "Revisar \(session.pendingDeletionCount) \(unit) marcados"
    }

    var body: some View {
        VStack(spacing: 20) {
            header

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if session.pendingDeletionCount > 0 {
                Button {
                    isShowingDeletionReview = true
                } label: {
                    Text(reviewDeletionButtonLabel)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(session.isDeleting || session.assetsMarkedForDeletion.isEmpty)
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .overlay(alignment: .bottom) {
            if let undoCandidate = session.undoCandidate {
                undoBanner(for: undoCandidate)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .offset(x: undoBannerOffset.width, y: undoBannerOffset.height)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.86), value: session.undoCandidate?.localIdentifier)
        .animation(.spring(response: 0.24, dampingFraction: 0.84), value: undoBannerOffset)
        .task {
            session.requestAccessAndLoadIfNeeded()
        }
        .sheet(isPresented: $isShowingDeletionReview) {
            deletionReviewSheet
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: isShowingPreview) {
            if let previewAsset {
                AssetDetailViewer(
                    asset: previewAsset,
                    audioEnabled: videoPreviewAudioEnabled
                )
            }
        }
        .onChange(of: session.pendingDeletionCount) { _, newValue in
            if newValue == 0 {
                isShowingDeletionReview = false
            }
        }
        .onChange(of: session.undoCandidate?.localIdentifier) { _, _ in
            undoBannerOffset = .zero
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("Limpiador de Fotos")
                .font(.title2.bold())

            headerButton {
                Picker("Fuente", selection: sourceSelection) {
                    ForEach(session.availableSources) { source in
                        Text(source.title)
                            .tag(source)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(.primary)
            }

            if showsVideoAudioToggle {
                headerActionButton {
                    videoPreviewAudioEnabled.toggle()
                } label: {
                    Label(
                        videoPreviewAudioEnabled ? "Audio preview activado" : "Audio preview desactivado",
                        systemImage: videoPreviewAudioEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                }
            }

            headerActionButton {
                session.toggleAssetPresentationOrder()
            } label: {
                Label(
                    session.assetPresentationOrder == .random ? "Modo random activado" : "Orden por fecha",
                    systemImage: session.assetPresentationOrder == .random ? "shuffle" : "clock.arrow.trianglehead.counterclockwise.rotate.90"
                )
                .font(.subheadline.weight(.semibold))
            }

            Text("Desliza a la derecha para conservar, a la izquierda para marcar para borrar.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        switch session.authorizationStatus {
        case .authorized, .limited:
            if session.isLoadingAssets {
                ProgressView("Cargando \(session.selectedSource.title)...")
            } else if displayedPhotos.isEmpty {
                emptyState(
                    title: "No hay elementos pendientes en \(session.selectedSource.title)",
                    subtitle: "Si borraste todo, ya conservaste lo importante o esa fuente no tiene contenido pendiente, aquí debería quedar vacío."
                )
            } else {
                ZStack {
                    ForEach(Array(displayedPhotos.enumerated()), id: \.element.localIdentifier) { index, asset in
                        PhotoCard(
                            asset: asset,
                            audioEnabled: videoPreviewAudioEnabled,
                            onPreview: {
                                previewAsset = asset
                            }
                        ) { action in
                            handleSwipe(for: asset, action: action)
                        }
                        .scaleEffect(1 - CGFloat(index) * 0.04)
                        .offset(y: CGFloat(index) * 10)
                        .zIndex(Double(displayedPhotos.count - index))
                    }
                }
            }
        case .denied, .restricted:
            emptyState(
                title: "Sin acceso a Fotos",
                subtitle: "Activa permisos de lectura y escritura en Configuracion > Privacidad > Fotos."
            )
        case .notDetermined:
            ProgressView("Pidiendo acceso a Fotos...")
        @unknown default:
            emptyState(
                title: "Estado desconocido",
                subtitle: "Cierra y vuelve a abrir la app para reintentar."
            )
        }
    }

    private func handleSwipe(for asset: PHAsset, action: ReviewAction) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            switch action {
            case .keep:
                session.keep(asset)
            case .delete:
                session.markForDeletion(asset)
            case .saveToPawZone:
                session.saveToPawZone(asset)
            }
        }
    }

    private func emptyState(title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func undoBanner(for asset: PHAsset) -> some View {
        HStack(spacing: 12) {
            Text(asset.mediaType == .video ? "Video marcado para borrar" : "Foto marcada para borrar")
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button("Deshacer") {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    session.undoLatestDeletionMark()
                }
            }
            .font(.subheadline.bold())
            .buttonStyle(.borderedProminent)
            .tint(.white.opacity(0.18))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.red.opacity(0.24), lineWidth: 1)
        )
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { gesture in
                    let verticalDrag = max(gesture.translation.height, 0)
                    undoBannerOffset = CGSize(
                        width: gesture.translation.width * 0.35,
                        height: verticalDrag
                    )
                }
                .onEnded { gesture in
                    let verticalDismiss = gesture.translation.height > 44
                    let horizontalDismiss = abs(gesture.translation.width) > 120

                    if verticalDismiss || horizontalDismiss {
                        session.dismissUndoCandidate()
                    }

                    undoBannerOffset = .zero
                }
        )
    }

    private var deletionReviewSheet: some View {
        NavigationStack {
            VStack(spacing: 18) {
                VStack(spacing: 6) {
                    Text("Revisa antes de borrar")
                        .font(.title3.bold())

                    Text("Toca cualquier elemento para sacarlo de esta tanda antes de confirmar.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 104), spacing: 12)],
                        spacing: 12
                    ) {
                        ForEach(session.assetsMarkedForDeletion, id: \.localIdentifier) { asset in
                            Button {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                    session.unmarkForDeletion(asset)
                                }
                            } label: {
                                ZStack(alignment: .topTrailing) {
                                    AssetImageView(
                                        asset: asset,
                                        renderSize: CGSize(width: 120, height: 160)
                                    )
                                    .frame(height: 160)
                                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                                    Image(systemName: "minus.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(.white, .red)
                                        .padding(8)
                                }
                                .overlay(alignment: .bottomLeading) {
                                    if asset.mediaType == .video {
                                        Label("Video", systemImage: "video.fill")
                                            .font(.caption.bold())
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(.ultraThinMaterial, in: Capsule())
                                            .padding(8)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Button {
                    session.deleteMarkedAssets()
                } label: {
                    if session.isDeleting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Borrar \(session.pendingDeletionCount) seleccionados")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(session.isDeleting || session.assetsMarkedForDeletion.isEmpty)
            }
            .padding()
            .navigationTitle("Borrado")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cerrar") {
                        isShowingDeletionReview = false
                    }
                }
            }
        }
    }

    private func headerButton<Label: View>(
        @ViewBuilder label: () -> Label
    ) -> some View {
        label()
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(.separator).opacity(0.35), lineWidth: 1)
            )
            .contentShape(Rectangle())
    }

    private func headerActionButton<Label: View>(
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) -> some View {
        Button(action: action) {
            headerButton(label: label)
        }
        .buttonStyle(.plain)
    }

    private var sourceSelection: Binding<ReviewSource> {
        Binding(
            get: { session.selectedSource },
            set: { session.selectSource($0) }
        )
    }

    private var isShowingPreview: Binding<Bool> {
        Binding(
            get: { previewAsset != nil },
            set: { isPresented in
                if !isPresented {
                    previewAsset = nil
                }
            }
        )
    }
}
