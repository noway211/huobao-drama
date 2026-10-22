import Foundation

public struct GenerateCharacterImagesUseCase {
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
        episodeId: Int64,
        settings: AgnesSettings,
        forceRegenerate: Bool
    ) async throws -> Int {
        _ = episodeId
        guard try repository.getProject(projectId) != nil else {
            throw LocalizedMessageError("Project not found")
        }
        let characters = try repository.getCharacters(projectId: projectId)
        if characters.isEmpty {
            throw LocalizedMessageError("请先提取角色")
        }

        var completed = 0
        var generated = 0
        var firstError: Error?
        for character in characters {
            if !forceRegenerate && character.imageStatus == .completed && isExistingLocalFile(character.imageLocalPath) {
                completed += 1
                continue
            }
            switch await generateOne(character: character, projectId: projectId, settings: settings) {
            case .generated:
                completed += 1
                generated += 1
            case .failed(let error):
                if error is CancellationError {
                    throw error
                }
                if firstError == nil {
                    firstError = error
                }
            }
        }

        if completed == characters.count || generated > 0 {
            return generated
        }
        throw firstError ?? LocalizedMessageError("角色图生成失败")
    }

    private func generateOne(
        character: Character,
        projectId: Int64,
        settings: AgnesSettings
    ) async -> CharacterImageOutcome {
        do {
            try repository.updateCharacterImage(
                characterId: character.id,
                status: .processing,
                url: character.imageUrl,
                localPath: character.imageLocalPath,
                errorMessage: nil
            )
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
            return .generated
        } catch is CancellationError {
            return .failed(CancellationError())
        } catch {
            try? repository.updateCharacterImage(
                characterId: character.id,
                status: .failed,
                url: character.imageUrl,
                localPath: character.imageLocalPath,
                errorMessage: error.localizedDescription
            )
            return .failed(error)
        }
    }

    private func isExistingLocalFile(_ path: String?) -> Bool {
        guard let path, !isBlank(path) else { return false }
        return FileManager.default.fileExists(atPath: path)
    }
}

private enum CharacterImageOutcome {
    case generated
    case failed(Error)
}

