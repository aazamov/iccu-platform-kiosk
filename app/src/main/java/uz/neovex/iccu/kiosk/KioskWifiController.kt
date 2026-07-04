package uz.neovex.iccu.kiosk

import android.annotation.SuppressLint
import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.wifi.WifiConfiguration
import android.net.wifi.WifiManager

class KioskWifiController(context: Context) {
    private val appContext = context.applicationContext
    private val wifiManager = appContext.getSystemService(WifiManager::class.java)
    private val connectivityManager = appContext.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

    fun isWifiEnabled(): Boolean = wifiManager.isWifiEnabled

    @Suppress("DEPRECATION")
    fun setWifiEnabled(enabled: Boolean): WifiConnectionResult =
        try {
            if (wifiManager.setWifiEnabled(enabled)) {
                WifiConnectionResult.Success
            } else {
                WifiOperationMessages.failed(if (enabled) "enable" else "disable")
            }
        } catch (_: SecurityException) {
            WifiOperationMessages.blocked()
        } catch (_: RuntimeException) {
            WifiOperationMessages.failed(if (enabled) "enable" else "disable")
        }

    @SuppressLint("MissingPermission")
    fun scanNetworks(): List<WifiNetworkInfo> {
        runCatching { wifiManager.startScan() }
            .getOrElse { return emptyList() }
        val connectedSsid = currentSsid()
        return runCatching { wifiManager.scanResults }
            .getOrElse { return emptyList() }
            .filter { it.SSID.isNotBlank() }
            .groupBy { it.SSID }
            .map { (_, results) -> results.maxBy { it.level } }
            .sortedByDescending { it.level }
            .map { result ->
                val security = WifiSecurityParser.parse(result.capabilities)
                WifiNetworkInfo(
                    ssid = result.SSID,
                    signalLevel = WifiManager.calculateSignalLevel(result.level, 4),
                    secured = security != WifiSecurity.OPEN,
                    connected = result.SSID == connectedSsid,
                    security = security,
                )
            }
    }

    fun currentSsid(): String? {
        val network = connectivityManager.activeNetwork ?: return null
        val capabilities = connectivityManager.getNetworkCapabilities(network) ?: return null
        if (!capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) return null

        return wifiManager.connectionInfo?.ssid
            ?.trim()
            ?.removePrefix("\"")
            ?.removeSuffix("\"")
            ?.takeIf { it.isNotBlank() && it != "<unknown ssid>" }
    }

    @Suppress("DEPRECATION")
    fun connect(network: WifiNetworkInfo, password: String): WifiConnectionResult {
        if (network.security == WifiSecurity.UNSUPPORTED) {
            return WifiOperationMessages.unsupportedSecurity()
        }

        return try {
            val configuration = WifiConfiguration().apply {
                SSID = quoteWifiValue(network.ssid)
                status = WifiConfiguration.Status.ENABLED
                when (network.security) {
                    WifiSecurity.OPEN -> {
                        allowedKeyManagement.set(WifiConfiguration.KeyMgmt.NONE)
                    }

                    WifiSecurity.WPA_PSK -> {
                        preSharedKey = quoteWifiValue(password)
                        allowedKeyManagement.set(WifiConfiguration.KeyMgmt.WPA_PSK)
                        allowedProtocols.set(WifiConfiguration.Protocol.RSN)
                        allowedProtocols.set(WifiConfiguration.Protocol.WPA)
                        allowedPairwiseCiphers.set(WifiConfiguration.PairwiseCipher.CCMP)
                        allowedPairwiseCiphers.set(WifiConfiguration.PairwiseCipher.TKIP)
                        allowedGroupCiphers.set(WifiConfiguration.GroupCipher.CCMP)
                        allowedGroupCiphers.set(WifiConfiguration.GroupCipher.TKIP)
                    }

                    WifiSecurity.UNSUPPORTED -> return WifiOperationMessages.unsupportedSecurity()
                }
            }

            val existingNetworkId = wifiManager.configuredNetworks
                ?.firstOrNull { normalizeWifiValue(it.SSID) == network.ssid }
                ?.networkId
                ?: -1

            val networkId = if (existingNetworkId >= 0) {
                configuration.networkId = existingNetworkId
                wifiManager.updateNetwork(configuration)
            } else {
                wifiManager.addNetwork(configuration)
            }

            if (networkId < 0) return WifiOperationMessages.failed("connect")

            wifiManager.disconnect()
            val enabled = wifiManager.enableNetwork(networkId, true)
            val reconnecting = wifiManager.reconnect()
            if (enabled && reconnecting) WifiConnectionResult.Success else WifiOperationMessages.failed("connect")
        } catch (_: SecurityException) {
            WifiOperationMessages.blocked()
        } catch (_: RuntimeException) {
            WifiOperationMessages.failed("connect")
        }
    }

    private fun quoteWifiValue(value: String): String = "\"${value.replace("\"", "\\\"")}\""

    private fun normalizeWifiValue(value: String?): String = value
        ?.trim()
        ?.removePrefix("\"")
        ?.removeSuffix("\"")
        .orEmpty()
}
