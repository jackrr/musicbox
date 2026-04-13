fn main() {
    // cpal's oboe backend (used on Android) is a C++ library that requires
    // libc++_shared.so at runtime. Declaring this link here causes cargo-ndk
    // to automatically copy libc++_shared.so into the APK's jniLibs directory.
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("android") {
        println!("cargo:rustc-link-lib=c++_shared");
    }
}
