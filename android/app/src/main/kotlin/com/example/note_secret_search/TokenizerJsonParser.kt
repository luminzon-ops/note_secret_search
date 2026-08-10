package com.example.note_secret_search

import org.json.JSONArray
import org.json.JSONObject

data class BertNormalizerDefinition(
    val cleanText: Boolean,
    val handleChineseChars: Boolean,
    val stripAccents: Boolean?,
    val lowercase: Boolean,
)

data class AddedTokenDefinition(
    val id: Int,
    val content: String,
    val singleWord: Boolean,
    val lstrip: Boolean,
    val rstrip: Boolean,
    val normalized: Boolean,
    val special: Boolean,
)

sealed interface TokenizerTemplatePart {
    data class SpecialToken(
        val ids: LongArray,
        val typeId: Long,
    ) : TokenizerTemplatePart

    data class Sequence(
        val typeId: Long,
    ) : TokenizerTemplatePart
}

data class TokenizerDefinition(
    val version: String,
    val vocab: Map<String, Int>,
    val normalizer: BertNormalizerDefinition,
    val addedTokens: List<AddedTokenDefinition>,
    val singleTemplate: List<TokenizerTemplatePart>,
    val unknownToken: String,
    val continuingSubwordPrefix: String,
    val maxInputCharsPerWord: Int,
    val padTokenId: Int,
    val unknownTokenId: Int,
    val clsTokenId: Int,
    val sepTokenId: Int,
) {
    companion object {
        fun legacy(
            vocab: Map<String, Int>,
            lowercase: Boolean,
        ): TokenizerDefinition {
            val padId = requireNotNull(vocab["[PAD]"]) { "[PAD] is required" }
            val unkId = requireNotNull(vocab["[UNK]"]) { "[UNK] is required" }
            val clsId = requireNotNull(vocab["[CLS]"]) { "[CLS] is required" }
            val sepId = requireNotNull(vocab["[SEP]"]) { "[SEP] is required" }
            return TokenizerDefinition(
                version = "legacy",
                vocab = vocab.toMap(),
                normalizer = BertNormalizerDefinition(
                    cleanText = true,
                    handleChineseChars = false,
                    stripAccents = null,
                    lowercase = lowercase,
                ),
                addedTokens = listOf(
                    AddedTokenDefinition(padId, "[PAD]", false, false, false, false, true),
                    AddedTokenDefinition(unkId, "[UNK]", false, false, false, false, true),
                    AddedTokenDefinition(clsId, "[CLS]", false, false, false, false, true),
                    AddedTokenDefinition(sepId, "[SEP]", false, false, false, false, true),
                ),
                singleTemplate = listOf(
                    TokenizerTemplatePart.SpecialToken(longArrayOf(clsId.toLong()), 0L),
                    TokenizerTemplatePart.Sequence(0L),
                    TokenizerTemplatePart.SpecialToken(longArrayOf(sepId.toLong()), 0L),
                ),
                unknownToken = "[UNK]",
                continuingSubwordPrefix = "##",
                maxInputCharsPerWord = 100,
                padTokenId = padId,
                unknownTokenId = unkId,
                clsTokenId = clsId,
                sepTokenId = sepId,
            )
        }
    }
}

object TokenizerJsonParser {
    fun parse(
        rawJson: String,
        expectedLowercase: Boolean,
    ): TokenizerDefinition {
        val root = JSONObject(rawJson)
        val version = root.requiredString("version")
        require(version == "1.0") {
            "TOKENIZER_SCHEMA_UNSUPPORTED: unsupported tokenizer version"
        }

        val normalizerObject = root.requiredObject("normalizer")
        require(normalizerObject.requiredString("type") == "BertNormalizer") {
            "TOKENIZER_SCHEMA_UNSUPPORTED: expected BertNormalizer"
        }
        val normalizer = BertNormalizerDefinition(
            cleanText = normalizerObject.requiredBoolean("clean_text"),
            handleChineseChars = normalizerObject.requiredBoolean("handle_chinese_chars"),
            stripAccents = normalizerObject.optionalBoolean("strip_accents"),
            lowercase = normalizerObject.requiredBoolean("lowercase"),
        )
        require(normalizer.lowercase == expectedLowercase) {
            "TOKENIZER_SCHEMA_UNSUPPORTED: catalog lowercase disagrees with tokenizer"
        }

        val preTokenizer = root.requiredObject("pre_tokenizer")
        require(preTokenizer.requiredString("type") == "BertPreTokenizer") {
            "TOKENIZER_SCHEMA_UNSUPPORTED: expected BertPreTokenizer"
        }

        val model = root.requiredObject("model")
        require(model.requiredString("type") == "WordPiece") {
            "TOKENIZER_SCHEMA_UNSUPPORTED: expected WordPiece model"
        }
        val vocab = parseVocabulary(model.requiredObject("vocab"))
        val unknownToken = model.requiredString("unk_token")
        val continuation = model.requiredString("continuing_subword_prefix")
        val maxInputChars = model.requiredInt("max_input_chars_per_word")
        require(maxInputChars > 0) {
            "TOKENIZER_SCHEMA_UNSUPPORTED: invalid WordPiece max input length"
        }

        val addedTokens = parseAddedTokens(root.requiredArray("added_tokens"))
        val postProcessor = root.requiredObject("post_processor")
        require(postProcessor.requiredString("type") == "TemplateProcessing") {
            "TOKENIZER_SCHEMA_UNSUPPORTED: expected TemplateProcessing"
        }
        val singleTemplate = parseSingleTemplate(postProcessor)
        require(singleTemplate.count { it is TokenizerTemplatePart.Sequence } == 1) {
            "TOKENIZER_SCHEMA_UNSUPPORTED: single template must contain one sequence"
        }

        fun requiredSpecialId(content: String): Int {
            val added = addedTokens.firstOrNull { it.content == content && it.special }
                ?: throw IllegalArgumentException(
                    "TOKENIZER_SCHEMA_UNSUPPORTED: missing special token",
                )
            require(vocab[content] == added.id) {
                "TOKENIZER_SCHEMA_UNSUPPORTED: special token id disagrees with vocab"
            }
            return added.id
        }

        val unknownId = requiredSpecialId(unknownToken)
        return TokenizerDefinition(
            version = version,
            vocab = vocab,
            normalizer = normalizer,
            addedTokens = addedTokens,
            singleTemplate = singleTemplate,
            unknownToken = unknownToken,
            continuingSubwordPrefix = continuation,
            maxInputCharsPerWord = maxInputChars,
            padTokenId = requiredSpecialId("[PAD]"),
            unknownTokenId = unknownId,
            clsTokenId = requiredSpecialId("[CLS]"),
            sepTokenId = requiredSpecialId("[SEP]"),
        )
    }

    private fun parseVocabulary(vocabObject: JSONObject): Map<String, Int> {
        val vocab = LinkedHashMap<String, Int>(vocabObject.length())
        val keys = vocabObject.keys()
        while (keys.hasNext()) {
            val token = keys.next()
            vocab[token] = vocabObject.getInt(token)
        }
        require(vocab.isNotEmpty()) {
            "TOKENIZER_SCHEMA_UNSUPPORTED: vocab is empty"
        }
        return vocab
    }

    private fun parseAddedTokens(array: JSONArray): List<AddedTokenDefinition> {
        return List(array.length()) { index ->
            val value = array.getJSONObject(index)
            AddedTokenDefinition(
                id = value.requiredInt("id"),
                content = value.requiredString("content"),
                singleWord = value.requiredBoolean("single_word"),
                lstrip = value.requiredBoolean("lstrip"),
                rstrip = value.requiredBoolean("rstrip"),
                normalized = value.requiredBoolean("normalized"),
                special = value.requiredBoolean("special"),
            )
        }
    }

    private fun parseSingleTemplate(postProcessor: JSONObject): List<TokenizerTemplatePart> {
        val specialTokens = postProcessor.requiredObject("special_tokens")
        val single = postProcessor.requiredArray("single")
        return List(single.length()) { index ->
            val part = single.getJSONObject(index)
            when {
                part.has("SpecialToken") -> {
                    val special = part.getJSONObject("SpecialToken")
                    val id = special.requiredString("id")
                    val metadata = specialTokens.optJSONObject(id)
                        ?: throw IllegalArgumentException(
                            "TOKENIZER_SCHEMA_UNSUPPORTED: template special token is missing",
                        )
                    val idsJson = metadata.requiredArray("ids")
                    require(idsJson.length() > 0) {
                        "TOKENIZER_SCHEMA_UNSUPPORTED: template special token has no ids"
                    }
                    TokenizerTemplatePart.SpecialToken(
                        ids = LongArray(idsJson.length()) { offset ->
                            idsJson.getLong(offset)
                        },
                        typeId = special.requiredInt("type_id").toLong(),
                    )
                }

                part.has("Sequence") -> {
                    val sequence = part.getJSONObject("Sequence")
                    require(sequence.requiredString("id") == "A") {
                        "TOKENIZER_SCHEMA_UNSUPPORTED: single template must use sequence A"
                    }
                    TokenizerTemplatePart.Sequence(
                        typeId = sequence.requiredInt("type_id").toLong(),
                    )
                }

                else -> throw IllegalArgumentException(
                    "TOKENIZER_SCHEMA_UNSUPPORTED: unknown template part",
                )
            }
        }
    }
}

private fun JSONObject.requiredObject(name: String): JSONObject {
    return optJSONObject(name)
        ?: throw IllegalArgumentException("TOKENIZER_SCHEMA_UNSUPPORTED: missing $name object")
}

private fun JSONObject.requiredArray(name: String): JSONArray {
    return optJSONArray(name)
        ?: throw IllegalArgumentException("TOKENIZER_SCHEMA_UNSUPPORTED: missing $name array")
}

private fun JSONObject.requiredString(name: String): String {
    val value = optString(name, "")
    require(value.isNotEmpty()) {
        "TOKENIZER_SCHEMA_UNSUPPORTED: missing $name"
    }
    return value
}

private fun JSONObject.requiredBoolean(name: String): Boolean {
    require(has(name) && !isNull(name)) {
        "TOKENIZER_SCHEMA_UNSUPPORTED: missing $name"
    }
    return getBoolean(name)
}

private fun JSONObject.optionalBoolean(name: String): Boolean? {
    return if (!has(name) || isNull(name)) null else getBoolean(name)
}

private fun JSONObject.requiredInt(name: String): Int {
    require(has(name) && !isNull(name)) {
        "TOKENIZER_SCHEMA_UNSUPPORTED: missing $name"
    }
    return getInt(name)
}
