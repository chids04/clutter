allprojects {
    repositories {
        google()
        mavenCentral()
        val ffmpegKitProject = rootProject.findProject(":ffmpeg_kit_next_flutter")
        if (ffmpegKitProject != null) {
            maven {
                url = uri("${ffmpegKitProject.projectDir}/libs-maven")
            }
        }
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
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
