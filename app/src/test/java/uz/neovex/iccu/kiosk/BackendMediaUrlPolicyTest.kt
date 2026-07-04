package uz.neovex.iccu.kiosk

import org.junit.Assert.assertEquals
import org.junit.Test

class BackendMediaUrlPolicyTest {
    @Test
    fun upgradesBackendMediaHttpUrlToHttps() {
        val url = "http://api.forum.iccu.uz/media/president/profile/photo.detail.webp"

        assertEquals(
            "https://api.forum.iccu.uz/media/president/profile/photo.detail.webp",
            BackendMediaUrlPolicy.upgradeToHttpsIfBackendMedia(url),
        )
    }

    @Test
    fun leavesNonBackendUrlsUnchanged() {
        val url = "http://example.com/media/photo.webp"

        assertEquals(url, BackendMediaUrlPolicy.upgradeToHttpsIfBackendMedia(url))
    }
}
