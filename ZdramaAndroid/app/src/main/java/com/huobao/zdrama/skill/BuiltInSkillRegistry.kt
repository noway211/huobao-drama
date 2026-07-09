package com.huobao.zdrama.skill

data class BuiltInSkill(
    val id: String,
    val name: String,
    val version: String,
    val required: Boolean,
    val enabledByDefault: Boolean,
    val outputMode: String
)

class BuiltInSkillRegistry {
    fun getSkills(): List<BuiltInSkill> {
        return listOf(
            BuiltInSkill("idea_expander", "Idea Expander", "1.0.0", true, true, "json_object"),
            BuiltInSkill("drama_structure_generator", "Drama Structure Generator", "1.0.0", true, true, "json_object"),
            BuiltInSkill("character_designer", "Character Designer", "1.0.0", true, true, "json_array"),
            BuiltInSkill("scene_designer", "Scene Designer", "1.0.0", true, true, "json_array"),
            BuiltInSkill("storyboard_breaker", "Storyboard Breaker", "1.0.0", true, true, "json_array")
        )
    }
}
