package uz.neovex.iccu.kiosk

import android.app.admin.DevicePolicyManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.wifi.WifiConfiguration
import android.net.wifi.WifiManager
import android.util.Log

class WifiProvisionReceiver : BroadcastReceiver() {
    @Suppress("DEPRECATION")
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_PROVISION_WIFI) return

        val ssid = intent.getStringExtra(EXTRA_SSID)?.trim().orEmpty()
        val password = intent.getStringExtra(EXTRA_PASSWORD).orEmpty()
        if (ssid.isEmpty() || password.isEmpty()) {
            Log.w(TAG, "Wi-Fi provisioning skipped: missing SSID or password")
            return
        }

        val devicePolicyManager = context.getSystemService(DevicePolicyManager::class.java)
        val adminComponent = ComponentName(context, KioskDeviceAdminReceiver::class.java)
        if (!devicePolicyManager.isAdminActive(adminComponent) ||
            !devicePolicyManager.isDeviceOwnerApp(context.packageName)
        ) {
            Log.w(TAG, "Wi-Fi provisioning skipped: app is not Device Owner")
            return
        }

        tryProvisionWifi(context, ssid, password)
    }

    @Suppress("DEPRECATION")
    private fun tryProvisionWifi(context: Context, ssid: String, password: String) {
        val wifiManager = context.applicationContext.getSystemService(WifiManager::class.java)
        try {
            wifiManager.setWifiEnabled(true)
        } catch (exception: SecurityException) {
            Log.w(TAG, "Could not enable Wi-Fi", exception)
        }

        try {
            val configuration = WifiConfiguration().apply {
                SSID = quoteWifiValue(ssid)
                preSharedKey = quoteWifiValue(password)
                status = WifiConfiguration.Status.ENABLED
                allowedKeyManagement.set(WifiConfiguration.KeyMgmt.WPA_PSK)
                allowedProtocols.set(WifiConfiguration.Protocol.RSN)
                allowedProtocols.set(WifiConfiguration.Protocol.WPA)
                allowedPairwiseCiphers.set(WifiConfiguration.PairwiseCipher.CCMP)
                allowedPairwiseCiphers.set(WifiConfiguration.PairwiseCipher.TKIP)
                allowedGroupCiphers.set(WifiConfiguration.GroupCipher.CCMP)
                allowedGroupCiphers.set(WifiConfiguration.GroupCipher.TKIP)
            }

            val existingNetworkId = wifiManager.configuredNetworks
                ?.firstOrNull { normalizeWifiValue(it.SSID) == ssid }
                ?.networkId
                ?: -1

            val networkId = if (existingNetworkId >= 0) {
                configuration.networkId = existingNetworkId
                wifiManager.updateNetwork(configuration)
            } else {
                wifiManager.addNetwork(configuration)
            }

            if (networkId < 0) {
                Log.e(TAG, "Wi-Fi provisioning failed: add/update network returned $networkId")
                return
            }

            wifiManager.disconnect()
            val enabled = wifiManager.enableNetwork(networkId, true)
            val reconnecting = wifiManager.reconnect()
            Log.i(TAG, "Wi-Fi provisioning requested for $ssid, enabled=$enabled, reconnecting=$reconnecting")
        } catch (exception: SecurityException) {
            Log.e(TAG, "Wi-Fi provisioning blocked by Android security policy", exception)
        } catch (exception: RuntimeException) {
            Log.e(TAG, "Wi-Fi provisioning failed", exception)
        }
    }

    private fun quoteWifiValue(value: String): String = "\"${value.replace("\"", "\\\"")}\""

    private fun normalizeWifiValue(value: String?): String = value
        ?.trim()
        ?.removePrefix("\"")
        ?.removeSuffix("\"")
        .orEmpty()

    companion object {
        const val ACTION_PROVISION_WIFI = "uz.neovex.iccu.kiosk.PROVISION_WIFI"
        const val EXTRA_SSID = "ssid"
        const val EXTRA_PASSWORD = "password"
        private const val TAG = "IccuWifiProvision"
    }
}
