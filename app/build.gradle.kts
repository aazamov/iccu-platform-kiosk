plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "uz.neovex.iccu.kiosk"
    compileSdk = 36

    defaultConfig {
        applicationId = "uz.neovex.iccu.kiosk"
        minSdk = 23
        targetSdk = 28
        versionCode = 1
        versionName = "1.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    kotlin {
        jvmToolchain(17)
    }
}

dependencies {
    testImplementation("junit:junit:4.13.2")
}
