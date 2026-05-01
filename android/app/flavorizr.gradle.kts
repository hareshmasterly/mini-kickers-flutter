import com.android.build.gradle.AppExtension

val android = project.extensions.getByType(AppExtension::class.java)

android.apply {
    flavorDimensions("flavor-type")

    productFlavors {
        create("staging") {
            dimension = "flavor-type"
            // Staging and prod share the same applicationId for now, so they
            // also share one Firebase project + google-services.json. Trade-off:
            //   - Staging and prod CAN'T be installed side-by-side on a device.
            //   - Staging analytics events land in prod Firebase analytics.
            // Switch to `com.masterly.minikickers.staging` here (and register
            // it in Firebase) when those become problems.
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