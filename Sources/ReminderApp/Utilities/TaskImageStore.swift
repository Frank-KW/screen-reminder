import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum TaskImageStoreError: LocalizedError {
    case invalidImage
    case couldNotCreateImage

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "The selected file is not a readable image."
        case .couldNotCreateImage:
            return "The selected image could not be prepared for the reminder."
        }
    }
}

final class TaskImageStore {
    static let shared = TaskImageStore()

    private let fileManager: FileManager
    private let directoryURL: URL
    private let cache = NSCache<NSString, NSImage>()
    private let maximumPixelSize = 3_840

    init(fileManager: FileManager = .default, directoryURL: URL? = nil) {
        self.fileManager = fileManager
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let applicationSupport = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? fileManager.temporaryDirectory
            self.directoryURL = applicationSupport
                .appendingPathComponent("Reminder", isDirectory: true)
                .appendingPathComponent("TaskImages", isDirectory: true)
        }
        cache.countLimit = 8
    }

    func importImage(from sourceURL: URL) throws -> String {
        let hasSecurityScope = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
            throw TaskImageStoreError.invalidImage
        }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            thumbnailOptions as CFDictionary
        ) else {
            throw TaskImageStoreError.invalidImage
        }

        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let filename = "\(UUID().uuidString).jpg"
        guard let destinationURL = fileURL(named: filename),
              let destination = CGImageDestinationCreateWithURL(
                destinationURL as CFURL,
                UTType.jpeg.identifier as CFString,
                1,
                nil
              ) else {
            throw TaskImageStoreError.couldNotCreateImage
        }

        let properties = [
            kCGImageDestinationLossyCompressionQuality: 0.86
        ] as CFDictionary
        CGImageDestinationAddImage(destination, cgImage, properties)
        guard CGImageDestinationFinalize(destination) else {
            try? fileManager.removeItem(at: destinationURL)
            throw TaskImageStoreError.couldNotCreateImage
        }

        let image = NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
        cache.setObject(image, forKey: filename as NSString)
        return filename
    }

    /// Raw bytes of a saved photo, for backups.
    func imageData(named filename: String) -> Data? {
        guard let url = fileURL(named: filename) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Puts a photo from a backup back on disk. Refuses names that point outside the folder
    /// and bytes that are not an image.
    func restoreImage(_ data: Data, named filename: String) throws {
        guard let url = fileURL(named: filename),
              CGImageSourceCreateWithData(data as CFData, nil).flatMap({ CGImageSourceGetCount($0) > 0 ? $0 : nil }) != nil else {
            throw TaskImageStoreError.invalidImage
        }
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        cache.removeObject(forKey: filename as NSString)
    }

    func image(named filename: String) -> NSImage? {
        if let cached = cache.object(forKey: filename as NSString) {
            return cached
        }
        guard let url = fileURL(named: filename),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        cache.setObject(image, forKey: filename as NSString)
        return image
    }

    func removeImage(named filename: String) throws {
        guard let url = fileURL(named: filename) else { return }
        cache.removeObject(forKey: filename as NSString)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    func fileURL(named filename: String) -> URL? {
        guard !filename.isEmpty,
              URL(fileURLWithPath: filename).lastPathComponent == filename else {
            return nil
        }
        return directoryURL.appendingPathComponent(filename, isDirectory: false)
    }
}
