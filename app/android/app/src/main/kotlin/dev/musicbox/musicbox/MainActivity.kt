package dev.musicbox.musicbox

import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    companion object {
        init {
            // Load via System.loadLibrary so the JVM calls JNI_OnLoad,
            // which initialises the Android context for cpal's oboe backend.
            // Dart's DynamicLibrary.open() uses dlopen and does NOT trigger
            // JNI_OnLoad — this companion init block runs first.
            System.loadLibrary("musicbox_engine")
        }
    }
}
