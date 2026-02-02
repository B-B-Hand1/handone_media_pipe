# Consumer rules for apps that use handone_media_pipe with MediaPipe.
# MediaPipe requires original class/field names (e.g. platform_); do not obfuscate.
-dontobfuscate

-keep class dev.ohanyan.handone_media_pipe.** { *; }

-dontwarn com.google.mediapipe.proto.CalculatorProfileProto$CalculatorProfile
-dontwarn com.google.mediapipe.proto.GraphTemplateProto$CalculatorGraphTemplate

-keep class com.google.mediapipe.** { *; }

-keepclasseswithmembernames class * {
    native <methods>;
}
