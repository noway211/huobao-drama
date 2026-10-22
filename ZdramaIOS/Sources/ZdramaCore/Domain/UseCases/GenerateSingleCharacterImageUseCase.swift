import Foundation

public struct GenerateSingleCharacterImageUseCase {
    private let repository: DramaRepository
    private let imageRepository: AgnesImageRepository
    private let downloadRepository: MediaDownloadRepository

    public init(
        repository: DramaRepository,
        imageRepository: AgnesImageRepository,
        downloadRepository: MediaDownloadRepository
    ) {
        self.repository = repository
        self.imageRepository = imageRepository
        self.downloadRepository = downloadRepository
    }

    public func execute(
        projectId: Int64,
        characterId: Int64,
        settings: AgnesSettings,
        forceRegenerate: Bool = true
    ) async throws -> String {
        guard let character = try repository.getCharacters(projectId: projectId).first(where: { $0.id == characterId }) else {
            throw LocalizedMessageError("角色不存在")
        }
        if !forceRegenerate && character.imageStatus == .completed && isExistingLocalFile(repository.resolveMediaPath(character.imageLocalPath)) {
            return character.imageLocalPath ?? ""
        }
        try repository.updateCharacterImage(
            characterId: character.id,
            status: .processing,
            url: character.imageUrl,
            localPath: character.imageLocalPath,
            errorMessage: nil
        )
        do {
            let imageUrl = try await imageRepository.generateImage(
                settings: settings,
                prompt: characterPortraitPrompt(character),
                size: characterTurnaroundSize
            )
            let localPath = try await downloadRepository.downloadCharacterImage(
                projectId: projectId,
                characterId: character.id,
                url: imageUrl
            )
            try repository.updateCharacterImage(
                characterId: character.id,
                status: .completed,
                url: imageUrl,
                localPath: localPath,
                errorMessage: nil
            )
            return localPath
        } catch is CancellationError {
            try repository.updateCharacterImage(
                characterId: character.id,
                status: character.imageStatus,
                url: character.imageUrl,
                localPath: character.imageLocalPath,
                errorMessage: character.imageErrorMessage
            )
            throw CancellationError()
        } catch {
            try repository.updateCharacterImage(
                characterId: character.id,
                status: .failed,
                url: character.imageUrl,
                localPath: character.imageLocalPath,
                errorMessage: error.localizedDescription
            )
            throw error
        }
    }

    private func isExistingLocalFile(_ path: String?) -> Bool {
        guard let path, !isBlank(path) else { return false }
        return FileManager.default.fileExists(atPath: path)
    }
}

func characterPortraitPrompt(_ character: Character) -> String {
    let appearance = character.appearance.trimmingCharacters(in: .whitespacesAndNewlines)
    let description = character.description.trimmingCharacters(in: .whitespacesAndNewlines)
    let detail = appearance.isEmpty ? (description.isEmpty ? "character portrait" : description) : appearance
    return "\(character.name), \(detail), character turnaround sheet, front view, side view, and back view side by side, full body, high quality"
}

let characterTurnaroundSize = "1536x1024"
