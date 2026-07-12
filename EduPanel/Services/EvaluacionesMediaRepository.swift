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
            var handles: [StorageHandle] = []
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
