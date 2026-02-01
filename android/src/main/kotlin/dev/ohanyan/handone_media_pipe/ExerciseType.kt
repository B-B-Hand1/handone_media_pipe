package dev.ohanyan.handone_media_pipe

enum class ExerciseType(val rawValue: String) {
    OPENING_AND_CLOSING_THE_FIST("openingAndClosingTheFist"),
    WRIST_EXTENSION_AND_FLEXION("wristExtensionAndFlexion"),
    FOREARM_SUPINATION_AND_PRONATION("forearmSupinationAndPronation");

    companion object {
        fun fromString(value: String): ExerciseType? = entries.find { it.rawValue == value }
    }
}
