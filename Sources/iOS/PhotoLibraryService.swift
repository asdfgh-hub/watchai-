import Foundation
import Photos
import UIKit

struct PhotoLibraryService: Sendable {
    enum PhotoError: LocalizedError {
        case permission(String)
        case noPhotos
        case imageUnavailable
        var errorDescription: String? {
            switch self {
            case .permission(let reason): return reason
            case .noPhotos: return "В медиатеке нет фотографий"
            case .imageUnavailable: return "Не удалось получить одно из изображений"
            }
        }
    }

    func latestJPEGs(count: Int) async throws -> [Data] {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            throw PhotoError.permission("Открой WristAI на iPhone и разреши доступ к фотографиям")
        }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = max(1, min(count, 10))
        let assets = PHAsset.fetchAssets(with: .image, options: options)
        guard assets.count > 0 else { throw PhotoError.noPhotos }

        return try await withThrowingTaskGroup(of: (Int, Data).self) { group in
            for index in 0..<assets.count {
                let asset = assets.object(at: index)
                group.addTask {
                    let data = try await self.imageData(for: asset)
                    return (index, data)
                }
            }
            var indexed: [(Int, Data)] = []
            for try await item in group { indexed.append(item) }
            return indexed.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private func imageData(for asset: PHAsset) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isSynchronous = false
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, info in
                if let error = info?[PHImageErrorKey] as? Error { continuation.resume(throwing: error); return }
                guard let data, let image = UIImage(data: data),
                      let jpeg = image.jpegData(compressionQuality: 0.82) else {
                    continuation.resume(throwing: PhotoError.imageUnavailable)
                    return
                }
                continuation.resume(returning: jpeg)
            }
        }
    }
}
