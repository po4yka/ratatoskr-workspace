import AgentCore
import Foundation

private enum HostError: Error {
  case invalidEnvironment(String)
  case invalidResponse
}

private struct Environment {
  let origin: URL
  let inbox: URL
  let support: URL
  let keychainService: String
  let ownerCredential: String

  init() throws {
    let values = ProcessInfo.processInfo.environment
    guard let rawOrigin = values["RATATOSKR_XPA020_PLATFORM_ORIGIN"],
          let origin = URL(string: rawOrigin), origin.scheme == "https" else {
      throw HostError.invalidEnvironment("RATATOSKR_XPA020_PLATFORM_ORIGIN")
    }
    guard let inboxPath = values["RATATOSKR_XPA020_INBOX_DIR"] else {
      throw HostError.invalidEnvironment("RATATOSKR_XPA020_INBOX_DIR")
    }
    guard let supportPath = values["RATATOSKR_XPA020_SUPPORT_DIR"] else {
      throw HostError.invalidEnvironment("RATATOSKR_XPA020_SUPPORT_DIR")
    }
    guard let service = values["RATATOSKR_XPA020_KEYCHAIN_SERVICE"], !service.isEmpty else {
      throw HostError.invalidEnvironment("RATATOSKR_XPA020_KEYCHAIN_SERVICE")
    }
    guard let credential = values["RATATOSKR_XPA020_OWNER_CREDENTIAL"], !credential.isEmpty else {
      throw HostError.invalidEnvironment("RATATOSKR_XPA020_OWNER_CREDENTIAL")
    }
    self.origin = origin
    inbox = URL(filePath: inboxPath, directoryHint: .isDirectory)
    support = URL(filePath: supportPath, directoryHint: .isDirectory)
    keychainService = service
    ownerCredential = credential
  }
}

private struct PairingCodeBody: Decodable { let code: String }

private func mintPairingCode(_ environment: Environment) async throws -> String {
  let endpoint = environment.origin.appending(path: "v1/devices/pairing-codes")
  var request = URLRequest(url: endpoint)
  request.httpMethod = "POST"
  request.setValue("application/json", forHTTPHeaderField: "Content-Type")
  request.setValue("Bearer \(environment.ownerCredential)", forHTTPHeaderField: "Authorization")
  request.httpBody = Data(#"{"expected_kind":"export_agent","label":"XPA-020 system host"}"#.utf8)
  let (data, response) = try await URLSession.shared.data(for: request)
  guard let http = response as? HTTPURLResponse, http.statusCode == 201 else {
    throw HostError.invalidResponse
  }
  return try JSONDecoder().decode(PairingCodeBody.self, from: data).code
}

private func stableCandidate(_ url: URL, folderID: UUID) throws -> StableArchiveCandidate {
  let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
  let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
  let snapshot = FileSnapshot(byteSize: size, modifiedAt: Date(timeIntervalSince1970: 0))
  return StableArchiveCandidate(
    folderID: folderID,
    url: url,
    snapshot: snapshot,
    evidence: StabilityEvidence(quietDuration: 30, snapshot: snapshot)
  )
}

@main
private enum ExportAgentProductSystemHost {
  static func main() async throws {
    let environment = try Environment()
    try FileManager.default.createDirectory(at: environment.support, withIntermediateDirectories: true)
    let identityStore = FileDeviceIdentityStore(
      fileURL: environment.support.appending(path: "paired-device.json")
    )
    let credentials = KeychainDeviceCredentialStore(service: environment.keychainService)
    let session = DeviceSessionCoordinator(
      transport: URLSessionPlatformDeviceTransport(),
      credentialStore: credentials,
      identityStore: identityStore
    )
    try await session.restore()
    if case .unpaired = await session.status {
      let code = try await mintPairingCode(environment)
      try await session.pair(origin: environment.origin, code: code, displayName: "XPA-020")
    }

    let journal = try LocalArchiveJournal.open(
      at: environment.support.appending(path: "journal.jsonl")
    )
    let folderID = UUID(uuidString: "01980000-0000-7000-8000-000000000020")!
    let processor = ArchiveCandidateProcessor(
      store: LocalArchiveStore(
        root: environment.support.appending(path: "archives", directoryHint: .isDirectory),
        maxStoreBytes: 16 * 1_048_576
      ),
      journal: journal,
      policies: [folderID: .archiveAfterUpload]
    )
    for name in ["chatgpt-synthetic.zip", "claude-synthetic.zip"] {
      _ = try await processor.process(
        stableCandidate(environment.inbox.appending(path: name), folderID: folderID)
      )
    }

    let queue = UploadQueue(
      journal: journal,
      operationTransport: SessionBoundArchiveOperationTransport(session: session),
      configuration: AgentConfiguration(
        backendBaseURL: environment.origin,
        maxArchiveBytes: 16 * 1_048_576,
        maxConcurrentUploads: 1,
        uploadChunkBytes: 65_536,
        maxUploadBytesPerSecond: 16 * 1_048_576,
        maxArchiveStoreBytes: 16 * 1_048_576
      )
    )
    let runtime = OperationalAgentRuntime(components: [UploadRuntimeComponent(queue: queue)])
    await runtime.start()
    await runtime.reconcile()
    await runtime.stop()

    let status = await queue.status()
    let entries = journal.entries
    let output: [String: Any] = [
      "schema": "xpa020-system-host-1",
      "entries": entries.count,
      "active": status.activeCount,
      "queued": status.queuedCount,
      "confirmed": entries.filter { $0.state == .confirmed }.count,
    ]
    let data = try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
  }
}
