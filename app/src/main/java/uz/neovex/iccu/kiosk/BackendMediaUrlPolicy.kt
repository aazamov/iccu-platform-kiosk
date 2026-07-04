package uz.neovex.iccu.kiosk

import java.net.URI

object BackendMediaUrlPolicy {
    fun upgradeToHttpsIfBackendMedia(url: String): String {
        val uri = runCatching { URI(url) }.getOrNull() ?: return url
        if (uri.scheme != "http") return url
        if (uri.host != "api.forum.iccu.uz") return url
        if (!uri.path.orEmpty().startsWith("/media/")) return url

        return URI(
            "https",
            uri.userInfo,
            uri.host,
            uri.port,
            uri.path,
            uri.query,
            uri.fragment,
        ).toString()
    }
}
