package uz.neovex.iccu.kiosk

import android.app.admin.DevicePolicyManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

class DeviceOwnerControlReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_CLEAR_DEVICE_OWNER) return

        val devicePolicyManager = context.getSystemService(DevicePolicyManager::class.java)
        val adminComponent = ComponentName(context, KioskDeviceAdminReceiver::class.java)
        if (!devicePolicyManager.isAdminActive(adminComponent) ||
            !devicePolicyManager.isDeviceOwnerApp(context.packageName)
        ) {
            Log.i(TAG, "Clear Device Owner skipped: app is not Device Owner")
            return
        }

        try {
            devicePolicyManager.setLockTaskPackages(adminComponent, emptyArray())
            devicePolicyManager.clearPackagePersistentPreferredActivities(adminComponent, context.packageName)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                devicePolicyManager.setStatusBarDisabled(adminComponent, false)
            }
            @Suppress("DEPRECATION")
            devicePolicyManager.clearDeviceOwnerApp(context.packageName)
            Log.i(TAG, "Device Owner cleared by kiosk app")
        } catch (exception: RuntimeException) {
            Log.e(TAG, "Could not clear Device Owner", exception)
        }
    }

    companion object {
        const val ACTION_CLEAR_DEVICE_OWNER = "uz.neovex.iccu.kiosk.CLEAR_DEVICE_OWNER"
        private const val TAG = "IccuDeviceOwnerControl"
    }
}
