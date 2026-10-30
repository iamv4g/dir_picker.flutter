import Foundation
import DartApiDl

/// Reports directory picker results to Dart via NativePort.
///
/// Message protocol:
/// - Success:    [0, directoryUri]
/// - Cancelled:  [1] (also: no result, done)
/// - Error:      [2, errorCode, errorMessage]
/// - Batch:      [3, jsonArray], any number before the closing message
final class DirPickerReporter {
    private let port: Int64
    private var isClosed = false

    init(port: Int64) {
        self.port = port
    }

    func sendUriSuccess(_ uri: String) {
        sendStringSuccess(uri)
    }

    func sendTokenSuccess(_ token: String) {
        sendStringSuccess(token)
    }

    private func sendStringSuccess(_ value: String) {
        guard !isClosed else { return }
        sendArray([createInt(0), createString(value)])
        isClosed = true
    }

    /// Sends a batch of entries. Unlike the other messages, it doesn't close
    /// the reporter.
    func sendBatch(_ entries: [[String: Any]]) throws {
        guard !isClosed else { return }
        let json = try JSONSerialization.data(withJSONObject: entries)
        sendArray([createInt(3), createString(String(decoding: json, as: UTF8.self))])
    }

    /// Ends a stream of batches.
    func sendDone() {
        sendCancelled()
    }

    func sendCancelled() {
        guard !isClosed else { return }
        sendArray([createInt(1)])
        isClosed = true
    }

    func sendError(code: String, message: String) {
        guard !isClosed else { return }
        sendArray([createInt(2), createString(code), createString(message)])
        isClosed = true
    }

    // MARK: - Private helpers

    private func sendArray(_ elements: [UnsafeMutablePointer<Dart_CObject>]) {
        let arrayPtr = UnsafeMutablePointer<UnsafeMutablePointer<Dart_CObject>?>.allocate(capacity: elements.count)
        defer { arrayPtr.deallocate() }

        for (index, element) in elements.enumerated() {
            arrayPtr[index] = element
        }

        var arrayObject = Dart_CObject()
        arrayObject.type = Dart_CObject_kArray
        arrayObject.value.as_array.length = elements.count
        arrayObject.value.as_array.values = arrayPtr

        _ = Dart_PostCObject_DL(port, &arrayObject)

        for element in elements {
            freeObject(element)
        }
    }

    private func createInt(_ value: Int64) -> UnsafeMutablePointer<Dart_CObject> {
        let obj = UnsafeMutablePointer<Dart_CObject>.allocate(capacity: 1)
        obj.pointee.type = Dart_CObject_kInt64
        obj.pointee.value.as_int64 = value
        return obj
    }

    private func createString(_ value: String) -> UnsafeMutablePointer<Dart_CObject> {
        let obj = UnsafeMutablePointer<Dart_CObject>.allocate(capacity: 1)
        obj.pointee.type = Dart_CObject_kString
        if let cString = strdup(value) {
            obj.pointee.value.as_string = UnsafePointer(cString)
        }
        return obj
    }

    private func freeObject(_ obj: UnsafeMutablePointer<Dart_CObject>) {
        if obj.pointee.type == Dart_CObject_kString, let str = obj.pointee.value.as_string {
            free(UnsafeMutablePointer(mutating: str))
        }
        obj.deallocate()
    }
}
