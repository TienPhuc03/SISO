allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// shortcut: h3_flutter 0.6.x viết cho bộ công cụ Android cũ: chưa khai báo namespace (AGP 8+ bắt buộc)
// và dịch theo android-31 (androidx hiện cần >= 34). Bù cho plugin nào thiếu; bỏ khối này khi nâng
// h3_flutter lên bản mới. Phải đứng trước evaluationDependsOn.
subprojects {
    afterEvaluate {
        val android = extensions.findByName("android") ?: return@afterEvaluate
        android.withGroovyBuilder {
            if (getProperty("namespace") == null) setProperty("namespace", group.toString())
            val compileSdk = getProperty("compileSdk") as Int?
            if (compileSdk != null && compileSdk < 34) setProperty("compileSdk", 36)
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
