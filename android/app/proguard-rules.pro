# OkHttp optional TLS providers - not used at runtime
-dontwarn org.bouncycastle.jsse.**
-dontwarn org.conscrypt.**
-dontwarn org.openjsse.**

# MediaPipe GenAI / AutoValue - optional codegen classes
-dontwarn com.google.auto.value.**
-dontwarn com.google.mediapipe.framework.image.**
-dontwarn com.google.mediapipe.tasks.genai.**

# Protobuf internal annotations
-dontwarn com.google.protobuf.**