package com.huobao.zdrama.data.remote

import com.google.gson.JsonArray
import com.google.gson.JsonElement
import com.google.gson.JsonObject

object ChatResponseTextExtractor {
    fun describe(response: JsonElement): String {
        if (!response.isJsonObject) return "response_type=non_object"
        val root = response.asJsonObject
        val choices = arrayValue(root, "choices")
        val firstChoice = firstObject(choices)
        val message = if (firstChoice != null) objectValue(firstChoice, "message") else null
        val content = message?.get("content")
        val reasoningContent = message?.get("reasoning_content")
        val contentType = if (content != null) contentType(content) else ""
        val contentLength = if (content != null) extractContentText(content).length else 0
        val reasoningContentType = if (reasoningContent != null) contentType(reasoningContent) else ""
        val reasoningContentLength = if (reasoningContent != null) extractContentText(reasoningContent).length else 0
        val choiceKeys = firstChoice?.keySet()?.joinToString().orEmpty()
        val finishReason = if (firstChoice != null) stringValue(firstChoice, "finish_reason").orEmpty() else ""
        val messageKeys = message?.keySet()?.joinToString().orEmpty()
        val outputTextLength = stringValue(root, "output_text")?.length ?: 0
        return listOf(
            "top_keys=${root.keySet().joinToString()}",
            "choices_count=${choices?.size() ?: 0}",
            "choice_keys=$choiceKeys",
            "finish_reason=$finishReason",
            "message_keys=$messageKeys",
            "content_type=$contentType",
            "content_length=$contentLength",
            "reasoning_content_type=$reasoningContentType",
            "reasoning_content_length=$reasoningContentLength",
            "output_text_length=$outputTextLength"
        ).joinToString(separator = "; ")
    }

    fun finishReason(response: JsonElement): String {
        if (!response.isJsonObject) return ""
        val choices = arrayValue(response.asJsonObject, "choices")
        val firstChoice = firstObject(choices) ?: return ""
        return stringValue(firstChoice, "finish_reason").orEmpty()
    }

    fun extractFinalContent(response: JsonElement): String {
        if (!response.isJsonObject) return ""
        val root = response.asJsonObject
        val candidates = mutableListOf<String>()

        val outputText = stringValue(root, "output_text")
        if (outputText != null) candidates.add(outputText)

        val choices = arrayValue(root, "choices")
        if (choices != null) {
            for (index in 0 until choices.size()) {
                val choice = choices[index]
                if (!choice.isJsonObject) continue
                val choiceObject = choice.asJsonObject

                val choiceText = stringValue(choiceObject, "text")
                if (choiceText != null) candidates.add(choiceText)

                val message = objectValue(choiceObject, "message")
                if (message != null) {
                    val content = message.get("content")
                    if (content != null) candidates.add(extractContentText(content))
                    val messageText = stringValue(message, "text")
                    if (messageText != null) candidates.add(messageText)
                }

                val delta = objectValue(choiceObject, "delta")
                if (delta != null) {
                    val content = delta.get("content")
                    if (content != null) candidates.add(extractContentText(content))
                }
            }
        }

        val output = arrayValue(root, "output")
        if (output != null) {
            for (index in 0 until output.size()) {
                candidates.add(extractContentText(output[index]))
            }
        }

        return firstNonBlank(candidates)
    }

    fun extract(response: JsonElement): String {
        val finalContent = extractFinalContent(response)
        if (finalContent.isNotBlank()) return finalContent
        if (!response.isJsonObject) return ""

        val candidates = mutableListOf<String>()
        val choices = arrayValue(response.asJsonObject, "choices")
        if (choices != null) {
            for (index in 0 until choices.size()) {
                val choice = choices[index]
                if (!choice.isJsonObject) continue
                val message = objectValue(choice.asJsonObject, "message") ?: continue
                val reasoningContent = message.get("reasoning_content")
                if (reasoningContent != null) candidates.add(extractContentText(reasoningContent))
            }
        }
        return firstNonBlank(candidates)
    }

    private fun extractContentText(element: JsonElement): String {
        return when {
            element.isJsonNull -> ""
            element.isJsonPrimitive -> {
                val primitive = element.asJsonPrimitive
                if (primitive.isString) primitive.asString else ""
            }
            element.isJsonArray -> extractArrayText(element.asJsonArray)
            element.isJsonObject -> extractObjectText(element.asJsonObject)
            else -> ""
        }
    }

    private fun extractArrayText(array: JsonArray): String {
        val parts = mutableListOf<String>()
        for (index in 0 until array.size()) {
            val text = extractContentText(array[index])
            if (text.isNotBlank()) parts.add(text)
        }
        return parts.joinToString(separator = "\n")
    }

    private fun extractObjectText(obj: JsonObject): String {
        val text = stringValue(obj, "text")
        if (text != null) return text
        val outputText = stringValue(obj, "output_text")
        if (outputText != null) return outputText
        val contentText = stringValue(obj, "content")
        if (contentText != null) return contentText
        val content = obj.get("content")
        if (content != null && content.isJsonArray) return extractArrayText(content.asJsonArray)
        return ""
    }

    private fun contentType(element: JsonElement): String {
        return when {
            element.isJsonNull -> "null"
            element.isJsonPrimitive -> "primitive"
            element.isJsonArray -> "array"
            element.isJsonObject -> "object"
            else -> "unknown"
        }
    }

    private fun firstObject(array: JsonArray?): JsonObject? {
        if (array == null || array.size() == 0) return null
        val first = array[0]
        return if (first.isJsonObject) first.asJsonObject else null
    }

    private fun firstNonBlank(values: List<String>): String {
        for (value in values) {
            if (value.isNotBlank()) return value.trim()
        }
        return ""
    }

    private fun stringValue(obj: JsonObject, key: String): String? {
        val value = obj.get(key) ?: return null
        if (!value.isJsonPrimitive || !value.asJsonPrimitive.isString) return null
        return value.asString
    }

    private fun objectValue(obj: JsonObject, key: String): JsonObject? {
        val value = obj.get(key) ?: return null
        return if (value.isJsonObject) value.asJsonObject else null
    }

    private fun arrayValue(obj: JsonObject, key: String): JsonArray? {
        val value = obj.get(key) ?: return null
        return if (value.isJsonArray) value.asJsonArray else null
    }
}
