package com.huobao.zdrama.skill

data class SkillExecutionRequest(
    val skillId: String,
    val inputJson: String
)

data class SkillExecutionResult(
    val skillId: String,
    val output: String
)

class SkillEngine(
    private val registry: BuiltInSkillRegistry,
    private val inputValidator: SkillInputValidator,
    private val jsonParser: SkillJsonParser
) {
    fun execute(request: SkillExecutionRequest): SkillExecutionResult {
        val skill = registry.getSkills().firstOrNull { it.id == request.skillId }
            ?: throw IllegalArgumentException("Unknown skill: ${request.skillId}")
        inputValidator.validate(request.inputJson)
        return SkillExecutionResult(skillId = skill.id, output = jsonParser.normalize(request.inputJson))
    }
}
