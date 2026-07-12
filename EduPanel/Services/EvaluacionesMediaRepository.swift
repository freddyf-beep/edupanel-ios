import Foundation
import FirebaseAuth
import FirebaseStorage
import UIKit

struct EvaluacionImagenSubida {
    let url: String
    let storagePath: String
    let contentType: String
    let size: Int
}

enum EvaluacionMediaFolder: String {
    case guias
    case pruebas
}

struct EvaluacionesMediaRepository {
    private static let maxInputBytes = 20 * 1024 * 1024
    private static let maxUploadBytes = 8 * 1024 * 1024
    private let providedStorage: Storage?

    init(storage: Storage? = nil) {
        self.providedStorage = storage
    }

    private var storage: Storage { providedStorage ?? Storage.storage() }

    func subirImagenGuia(
        documentId: String,
        data: Data,
        onProgress: @escaping (Double) -> Void
    ) async throws -> EvaluacionImagenSubida {
        try await subirImagen(
            documentId: documentId,
            folder: .guias,
            data: data,
            onProgress: onProgress
        )
    }

    func subirImagenPrueba(
        documentId: String,
        data: Data,
        onProgress: @escaping (Double) -> Void
    ) async throws -> EvaluacionImagenSubida {
        try await subirImagen(
            documentId: documentId,
            folder: .pruebas,
            data: data,
            onProgress: onProgress
        )
    }

    func subirImagen(
        documentId: String,
        folder: EvaluacionMediaFolder,
        data: Data,
        onProgress: @escaping (Double) -> Void
    ) async throws -> EvaluacionImagenSubida {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw EvaluacionesMediaError.missingUser
        }
        let cleanDocumentId = documentId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanDocumentId.isEmpty, !cleanDocumentId.contains("/") else {
            throw EvaluacionesMediaError.invalidDocumentId
        }
        guard !data.isEmpty, data.count <= Self.maxInputBytes else {
            throw EvaluacionesMediaError.inputTooLarge
        }

        let prepared = try await prepareJPEG(data)
        guard prepared.count <= Self.maxUploadBytes else {
            throw EvaluacionesMediaError.outputTooLarge
        }

        let fileName = "\(UUID().uuidString.lowercased())_imagen.jpg"
        let path = "users/\(uid)/evaluaciones/\(folder.rawValue)/\(cleanDocumentId)/\(fileName)"
        let reference = storage.reference(withPath: path)
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        let downloadURL = try await upload(
            prepared,
            metadata: metadata,
            reference: reference,
            onProgress: onProgress
        )

        return EvaluacionImagenSubida(
            url: downloadURL.absoluteString,
            storagePath: path,
            contentType: "image/jpeg",
            size: prepared.count
        )
    }

    func eliminarMediosHuerfanos(
        documentId: String,
        folder: EvaluacionMediaFolder,
        previousPaths: Set<String>,
        currentPaths: Set<String>
    ) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let cleanDocumentId = documentId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanDocumentId.isEmpty, !cleanDocumentId.contains("/") else { return }
        let prefix = "users/\(uid)/evaluaciones/\(folder.rawValue)/\(cleanDocumentId)/"
        let orphans = previousPaths.subtracting(currentPaths).filter { path in
            path.hasPrefix(prefix) && path.count > prefix.count && !path.dropFirst(prefix.count).contains("/")
        }
        for path in orphans {
            try? await delete(storage.reference(withPath: path))
        }
    }

    private func prepareJPEG(_ data: Data) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            guard let image = UIImage(data: data) else {
                throw EvaluacionesMediaError.invalidImage
            }
            let maxDimension: CGFloat = 2400
            let largest = max(image.size.width, image.size.height)
            let scale = largest > maxDimension ? maxDimension / largest : 1
            let size = CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            let resized = UIGraphicsImageRenderer(size: size, format: format).image { context in
                context.cgContext.setFillColor(UIColor.white.cgColor)
                context.cgContext.fill(CGRect(origin: .zero, size: size))
                image.draw(in: CGRect(origin: .zero, size: size))
            }
            var quality: CGFloat = 0.88
            while quality >= 0.45 {
                if let output = resized.jpegData(compressionQuality: quality),
                   output.count <= Self.maxUploadBytes {
                    return output
                }
                quality -= 0.08
            }
            throw EvaluacionesMediaError.outputTooLarge
        }.value
    }

    private func upload(
        _ data: Data,
        metadata: StorageMetadata,
        reference: StorageReference,
        onProgress: @escaping (Double) -> Void
    ) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let task = reference.putData(data, metadata: metadata)
            var handles: [String] = []
            func removeObservers() { handles.forEach { task.removeObserver(withHandle: $0) } }

            handles.append(task.observe(.progress) { snapshot in
                let completed = snapshot.progress?.fractionCompleted ?? 0
                DispatchQueue.main.async { onProgress(completed) }
            })
            handles.append(task.observe(.failure) { snapshot in
                removeObservers()
                continuation.resume(throwing: snapshot.error ?? EvaluacionesMediaError.uploadFailed)
            })
            handles.append(task.observe(.success) { _ in
                removeObservers()
                reference.downloadURL { url, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let url {
                        continuation.resume(returning: url)
                    } else {
                        continuation.resume(throwing: EvaluacionesMediaError.missingDownloadURL)
                    }
                }
            })
        }
    }

    private func delete(_ reference: StorageReference) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            reference.delete { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: ()) }
            }
        }
    }

}

extension GuiaEditorDraft {
    var ownedMediaStoragePaths: Set<String> {
        var paths = Set<String>()
        func add(_ blocks: [GuiaBlockDraft]) {
            blocks.filter { !$0.isDeleted }.forEach {
                if !$0.storagePath.isEmpty { paths.insert($0.storagePath) }
            }
        }
        secciones.forEach { section in
            add(section.bloques)
            section.actividades.filter { !$0.isDeleted }.forEach { add($0.resources) }
        }
        add(cierre)
        return paths
    }
}

extension PruebaEditorDraft {
    var ownedMediaStoragePaths: Set<String> {
        var paths = Set<String>()
        func add(_ blocks: [GuiaBlockDraft]) {
            blocks.filter { !$0.isDeleted }.forEach {
                if !$0.storagePath.isEmpty { paths.insert($0.storagePath) }
            }
        }
        secciones.filter { !$0.isDeleted }.forEach { section in
            add(section.estimulo)
            section.items.filter { !$0.isDeleted }.forEach { item in
                add(item.resources)
                (item.entriesA + item.entriesB).filter { !$0.isDeleted }.forEach {
                    if !$0.imageStoragePath.isEmpty { paths.insert($0.imageStoragePath) }
                }
            }
        }
        return paths
    }
}

enum EvaluacionesMediaError: LocalizedError {
    case missingUser
    case invalidDocumentId
    case inputTooLarge
    case invalidImage
    case outputTooLarge
    case uploadFailed
    case missingDownloadURL

    var errorDescription: String? {
        switch self {
        case .missingUser: return "Debes iniciar sesión para subir imágenes."
        case .invalidDocumentId: return "Guarda el documento antes de subir una imagen."
        case .inputTooLarge: return "La imagen seleccionada es demasiado grande."
        case .invalidImage: return "El archivo seleccionado no es una imagen válida."
        case .outputTooLarge: return "No fue posible reducir la imagen bajo 8 MB."
        case .uploadFailed: return "Firebase Storage no pudo subir la imagen."
        case .missingDownloadURL: return "La imagen se subió, pero no se obtuvo su URL."
        }
    }
}
