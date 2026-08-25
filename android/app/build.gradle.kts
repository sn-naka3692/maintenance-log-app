// ✅ CRITICAL: Required imports for signing configuration
import java.util.Properties
import java.io.FileInputStream

// リリース署名情報の読み込み(android/key.properties)。
// このファイルは秘密情報を含むため.gitignoreでgit管理外になっている。
// ファイルが存在しない場合(CI環境等)はnullのままとし、debug署名に
// フォールバックする(ローカル開発時に build.gradle.kts がエラーにならないため)。
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasReleaseSigningConfig = keystorePropertiesFile.exists()
if (hasReleaseSigningConfig) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.maintenancelog.log"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.maintenancelog.log"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Galaxy A53以降の現場端末はすべてarm64-v8a(64bit ARM)のため、
        // 配布用APKはarm64-v8aのみに絞り、ダウンロードサイズを削減する。
        // (x86_64はエミュレータ用、armeabi-v7aは旧32bit機種用で現場では不要)
        //
        // ⚠️【重要】この設定はアプリ自身のネイティブコード用の絞り込みであり、
        // Flutterエンジン本体(libflutter.so)を何アーキテクチャ分同梱するかは
        // 別途 `flutter build apk` 実行時の --target-platform フラグで決まる。
        // 配布用ビルドは必ず scripts/build_release_apk.sh を使うこと
        // (直接 `flutter build apk --release` を実行すると、フラグ忘れにより
        // 3アーキテクチャ分(約58MB)の巨大APKが生成されてしまう)。
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
    }

    signingConfigs {
        if (hasReleaseSigningConfig) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // 【2026-08 正式切替】android/key.properties + release-key.jks が
            // 存在する場合は正式なリリース署名を使用する。存在しない場合
            // (万一の欠落・CI環境等)はdebug署名にフォールバックし、
            // ビルド自体は失敗させない(ただし配布用ビルドとしては不可)。
            signingConfig = if (hasReleaseSigningConfig) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
