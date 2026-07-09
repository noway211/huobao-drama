package com.huobao.zdrama.skill

class SkillInputValidator {
    fun validate(inputJson: String) {
        require(inputJson.isNotBlank()) { "Skill input must not be blank" }
    }
}
