import com.android.build.gradle.AppExtension

val android = project.extensions.getByType(AppExtension::class.java)

android.apply {
    flavorDimensions("flavor-type")

    productFlavors {
        create("staging") {
            dimension = "flavor-type"
            applicationId = "com.masterly.minikickers"
            resValue(type = "string", name = "app_name", value = "Mini Kickers Staging")
        }
        create("prod") {
            dimension = "flavor-type"
            applicationId = "com.masterly.minikickers"
            resValue(type = "string", name = "app_name", value = "Mini Kickers")
        }
    }
}