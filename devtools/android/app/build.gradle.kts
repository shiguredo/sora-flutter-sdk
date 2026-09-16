plugins {
    id("com.android.application")
    // Flutter Gradle Plugin は Android と Kotlin の Gradle plugin より後に適用する。
    id("dev.flutter.flutter-gradle-plugin")
}

val soraHwasanEnabled = providers.gradleProperty("sora.hwasan").orNull == "true"

// HWASan は wrap.sh を利用できる debug APK でのみ実行する。
if (soraHwasanEnabled) {
    val hwasanUnsupportedTask =
        gradle.startParameter.taskNames.any { taskName ->
            val task = taskName.substringAfterLast(":")
            task == "assemble" ||
                task == "build" ||
                task.contains("release", ignoreCase = true) ||
                task.contains("profile", ignoreCase = true)
        }
    check(!hwasanUnsupportedTask) {
        "sora.hwasan=true は debug ビルドでのみ指定してください。"
    }
}

android {
    namespace = "com.example.devtools"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: 固有の Application ID を指定する (https://developer.android.com/studio/build/application-id.html) 。
        applicationId = "com.example.devtools"
        // 以下の値はアプリケーションの要件に合わせて変更する。
        // 詳細は https://flutter.dev/to/review-gradle-config を参照する。
        minSdk = 29
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: release ビルド用の署名設定を追加する。
            // `flutter run --release` を利用できるよう、現在は debug 用の鍵で署名する。
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    // HWASan の wrap.sh を読み込めるように、検証ビルドだけ従来形式で native library を配置する。
    packaging {
        jniLibs {
            useLegacyPackaging = soraHwasanEnabled
        }
    }

    if (soraHwasanEnabled) {
        sourceSets.getByName("debug").resources.srcDir("src/hwasan/resources")
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
