package uz.neovex.iccu.kiosk

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory

class AndroidCompatibilityTest {
    @Test
    fun targetSdkKeepsAndroidTenWifiToggleAvailable() {
        val manifest = File("build/intermediates/merged_manifest/debug/processDebugMainManifest/AndroidManifest.xml")
        assertTrue("Merged debug manifest does not exist: ${manifest.absolutePath}", manifest.isFile)

        val document = DocumentBuilderFactory.newInstance()
            .apply { isNamespaceAware = true }
            .newDocumentBuilder()
            .parse(manifest)
        val usesSdk = document.getElementsByTagName("uses-sdk").item(0)
        val targetSdk = usesSdk.attributes
            .getNamedItemNS("http://schemas.android.com/apk/res/android", "targetSdkVersion")
            .nodeValue
            .toInt()

        assertTrue(
            "Android 10 Wi-Fi toggle compatibility requires targetSdkVersion <= 28, got $targetSdk",
            targetSdk <= 28,
        )
    }
}
