// Created by 이돈혁

import CoreNFC
import Foundation
import Observation

@MainActor
@Observable
final class NFCWriter: NSObject, @preconcurrency NFCNDEFReaderSessionDelegate {
    enum State {
        case idle
        case working(String)
        case succeeded(URL)
        case failed(String)
        case cancelled(String)
    }

    private(set) var state: State = .idle
    private(set) var isRunning = false
    var isAvailable: Bool { NFCNDEFReaderSession.readingAvailable }

    @ObservationIgnored private var session: NFCNDEFReaderSession?
    @ObservationIgnored private var sessionID = UUID()
    @ObservationIgnored private var connectedTag: (any NFCNDEFTag)?
    @ObservationIgnored private var message: NFCNDEFMessage?
    @ObservationIgnored private var requestedURL: URL?
    @ObservationIgnored private var isProcessingTag = false
    @ObservationIgnored private var didAttemptWrite = false
    @ObservationIgnored private var isFinishing = false

    func write(_ text: String) {
        guard session == nil else { return }
        do {
            let request = try NFCWriteRequest(text)
            guard isAvailable else {
                state = .failed("이 기기에서는 NFC 태그를 기록할 수 없어요. NFC를 지원하는 iPhone에서 이용해 주세요.")
                return
            }
            guard let payload = NFCNDEFPayload.wellKnownTypeURIPayload(url: request.url) else {
                state = .failed("이 링크를 NFC 기록 형식으로 변환할 수 없어요.")
                return
            }
            message = NFCNDEFMessage(records: [payload])
            requestedURL = request.url
            didAttemptWrite = false
            isProcessingTag = false
            isFinishing = false
            // Core NFC delivers delegate and tag completion callbacks on this queue.
            let reader = NFCNDEFReaderSession(delegate: self, queue: .main, invalidateAfterFirstRead: false)
            sessionID = UUID()
            session = reader
            isRunning = true
            state = .working("iPhone 윗부분을 기록할 NFC 태그 하나에 가까이 대세요.")
            reader.alertMessage = "App Clip 링크를 기록할 NFC 태그 하나에 iPhone 윗부분을 가까이 대세요."
            reader.begin()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func clearResult() {
        guard !isRunning else { return }
        state = .idle
    }

    func cancel() {
        guard let session, !isFinishing else { return }
        isFinishing = true
        state = .cancelled(cancellationMessage)
        session.invalidate()
    }

    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        // The tag delegate below enables read-write mode instead of message-only mode.
    }

    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        guard self.session === session else { return }
        if !isFinishing {
            let readerError = error as? NFCReaderError
            if readerError?.code == .readerSessionInvalidationErrorUserCanceled {
                state = .cancelled(cancellationMessage)
            } else {
                state = .failed(failureMessage("NFC 세션이 종료되었어요. NFC 권한과 태그 위치를 확인한 뒤 다시 시도해 주세요."))
            }
        }
        self.session = nil
        message = nil
        connectedTag = nil
        requestedURL = nil
        isProcessingTag = false
        isRunning = false
    }

    func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [any NFCNDEFTag]) {
        guard isCurrent(session), !isProcessingTag else { return }
        guard tags.count == 1, let tag = tags.first else {
            fail("여러 태그가 감지되었어요. 다른 태그를 치우고 하나만 가까이 대서 다시 시도해 주세요.", session: session)
            return
        }
        isProcessingTag = true
        connectedTag = tag
        let sessionID = self.sessionID
        state = .working("태그의 쓰기 가능 여부를 확인하고 있어요.")
        session.connect(to: tag) { [weak self] error in
            // All Core NFC callbacks use the session's .main queue. Keep non-Sendable
            // NFC objects in actor-owned storage; capture only the session identity.
            MainActor.assumeIsolated {
                guard let self, let session = self.activeSession(sessionID) else { return }
                guard error == nil else {
                    self.fail("태그에 연결하지 못했어요. 위치를 조정한 뒤 다시 시도해 주세요.", session: session)
                    return
                }
                self.checkStatus(sessionID)
            }
        }
    }

    private func checkStatus(_ sessionID: UUID) {
        guard let tag = connectedTag else { return }
        tag.queryNDEFStatus { [weak self] status, capacity, error in
            MainActor.assumeIsolated {
                guard let self, let session = self.activeSession(sessionID), let message = self.message else { return }
                guard error == nil else {
                    self.fail("태그 정보를 읽지 못했어요. 태그를 가까이 댄 상태로 다시 시도해 주세요.", session: session)
                    return
                }
                switch status {
                case .readOnly:
                    self.fail("읽기 전용 태그예요. 기록 가능한 다른 NFC 태그를 사용해 주세요.", session: session)
                    return
                case .notSupported:
                    self.fail("NDEF 기록을 지원하지 않는 태그예요. NDEF 형식의 태그를 사용해 주세요.", session: session)
                    return
                case .readWrite:
                    break
                @unknown default:
                    self.fail("이 태그의 기록 가능 여부를 확인할 수 없어요.", session: session)
                    return
                }
                guard message.length <= capacity else {
                    self.fail("태그 용량이 부족해요. 필요한 용량은 \(message.length)바이트이고 태그는 \(capacity)바이트예요.", session: session)
                    return
                }
                self.writeAndVerify(sessionID)
            }
        }
    }

    private func writeAndVerify(_ sessionID: UUID) {
        guard let session = activeSession(sessionID), let tag = connectedTag, let message else { return }
        didAttemptWrite = true
        state = .working("링크를 기록하고 있어요. 태그를 움직이지 마세요.")
        session.alertMessage = "링크를 기록하고 있어요. 완료될 때까지 태그를 움직이지 마세요."
        tag.writeNDEF(message) { [weak self] error in
            MainActor.assumeIsolated {
                guard let self, let session = self.activeSession(sessionID) else { return }
                guard error == nil else {
                    self.fail("링크 기록을 완료하지 못했어요.", session: session)
                    return
                }
                self.verify(sessionID)
            }
        }
    }

    private func verify(_ sessionID: UUID) {
        guard let tag = connectedTag else { return }
        state = .working("기록한 링크를 다시 읽어 확인하고 있어요.")
        tag.readNDEF { [weak self] actual, error in
            MainActor.assumeIsolated {
                guard let self, let session = self.activeSession(sessionID),
                      let expected = self.message, let url = self.requestedURL else { return }
                guard error == nil, let actual, self.matches(actual, expected: expected) else {
                    self.fail("기록 후 확인에 실패했어요.", session: session)
                    return
                }
                self.isFinishing = true
                self.state = .succeeded(url)
                session.alertMessage = "App Clip 링크를 기록하고 다시 읽어 확인했어요."
                session.invalidate()
            }
        }
    }

    private func activeSession(_ id: UUID) -> NFCNDEFReaderSession? {
        guard let session, sessionID == id, !isFinishing else { return nil }
        return session
    }

    private func matches(_ actual: NFCNDEFMessage, expected: NFCNDEFMessage) -> Bool {
        guard actual.records.count == expected.records.count else { return false }
        return zip(actual.records, expected.records).allSatisfy {
            $0.typeNameFormat == $1.typeNameFormat && $0.type == $1.type &&
            $0.identifier == $1.identifier && $0.payload == $1.payload
        }
    }

    private func isCurrent(_ session: NFCNDEFReaderSession) -> Bool {
        self.session === session && !isFinishing
    }

    private func fail(_ text: String, session: NFCNDEFReaderSession) {
        guard isCurrent(session) else { return }
        isFinishing = true
        let detail = failureMessage(text)
        state = .failed(detail)
        session.invalidate(errorMessage: detail)
    }

    private func failureMessage(_ text: String) -> String {
        didAttemptWrite ? text + " 태그 내용이 변경되었을 수 있어요. 같은 링크로 다시 기록하고 확인해 주세요." : text
    }

    private var cancellationMessage: String {
        didAttemptWrite
            ? "확인이 끝나기 전에 취소했어요. 태그 내용이 변경되었을 수 있으니 같은 링크로 다시 기록하고 확인해 주세요."
            : "NFC 기록을 취소했어요. 준비되면 다시 시도해 주세요."
    }
}
