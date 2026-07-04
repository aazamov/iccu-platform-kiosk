package uz.neovex.iccu.kiosk

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.app.ActivityManager
import android.app.AlertDialog
import android.app.admin.DevicePolicyManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Color
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.BatteryManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.ActionMode
import android.view.ContextMenu
import android.view.Gravity
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.Window
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.ConsoleMessage
import android.webkit.WebChromeClient
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.SeekBar
import android.widget.TextView
import android.widget.Toast
import java.net.HttpURLConnection
import java.net.URL

class MainActivity : Activity() {
    private lateinit var webView: WebView
    private lateinit var offlineView: TextView
    private lateinit var loadingView: TextView
    private lateinit var batteryText: TextView
    private lateinit var wifiButton: ImageButton
    private lateinit var wifiPanel: LinearLayout
    private lateinit var wifiStatusText: TextView
    private lateinit var wifiController: KioskWifiController
    private lateinit var wifiNetworksContainer: LinearLayout
    private lateinit var wifiPasswordDisplay: TextView
    private lateinit var wifiKeyboardContainer: LinearLayout
    private lateinit var wifiMessageText: TextView
    private lateinit var wifiPowerButton: TextView
    private lateinit var brightnessPanel: LinearLayout
    private lateinit var brightnessSlider: SeekBar
    private lateinit var devicePolicyManager: DevicePolicyManager
    private lateinit var adminComponent: ComponentName
    private val exitHandler = Handler(Looper.getMainLooper())
    private val actionHandler = Handler(Looper.getMainLooper())
    private val brightnessHandler = Handler(Looper.getMainLooper())
    private val wifiPanelHandler = Handler(Looper.getMainLooper())
    private val wifiPanelGate = TimedActionGate(WIFI_PANEL_COOLDOWN_MS)
    private var exitDialogPending = false
    private var reloadActionPending = false
    private var blankPageReloadCount = 0
    private var lastConsoleMessage = ""
    private var selectedWifiNetwork: WifiNetworkInfo? = null
    private val wifiPasswordState = WifiPasswordInputState()
    private val batteryReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            updateBattery(intent)
        }
    }
    private val networkReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            clearWifiSelection()
            updateWifiStatus()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestWindowFeature(Window.FEATURE_NO_TITLE)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        devicePolicyManager = getSystemService(DevicePolicyManager::class.java)
        adminComponent = ComponentName(this, KioskDeviceAdminReceiver::class.java)
        wifiController = KioskWifiController(this)

        configureDeviceOwnerPolicies()
        setContentView(createLayout())
        keepSystemUiHidden()
        configureWebView()
        webView.postDelayed({ loadKioskPage() }, 800L)
        registerReceiver(batteryReceiver, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        @Suppress("DEPRECATION")
        registerReceiver(networkReceiver, IntentFilter(ConnectivityManager.CONNECTIVITY_ACTION))
        updateWifiStatus()
    }

    override fun onDestroy() {
        runCatching { unregisterReceiver(batteryReceiver) }
        runCatching { unregisterReceiver(networkReceiver) }
        wifiPanelHandler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }

    override fun onResume() {
        super.onResume()
        enterFullscreen()
        configureDeviceOwnerPolicies()
        if (::webView.isInitialized) {
            webView.onResume()
            webView.resumeTimers()
        }
        startKioskMode()
        webView.postDelayed({
            enterFullscreen()
            configureDeviceOwnerPolicies()
            startKioskMode()
        }, RELOCK_AFTER_EXTERNAL_PANEL_DELAY_MS)
        wifiPanelGate.reset()
        updateWifiStatus()
        if (::webView.isInitialized && webView.url.isNullOrBlank()) {
            webView.postDelayed({ loadKioskPage() }, 1_500L)
        }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) enterFullscreen()
    }

    @Suppress("OVERRIDE_DEPRECATION")
    override fun onBackPressed() {
        webView.loadUrl(KIOSK_URL)
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        if (keyCode == KeyEvent.KEYCODE_BACK) {
            webView.loadUrl(KIOSK_URL)
            return true
        }
        return super.onKeyDown(keyCode, event)
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun configureWebView() {
        WebView.setWebContentsDebuggingEnabled(false)
        webView.setBackgroundColor(Color.WHITE)
        webView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            databaseEnabled = true
            mediaPlaybackRequiresUserGesture = false
            cacheMode = WebSettings.LOAD_DEFAULT
            mixedContentMode = WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
            loadsImagesAutomatically = true
            javaScriptCanOpenWindowsAutomatically = true
            allowContentAccess = true
            allowFileAccess = false
            useWideViewPort = true
            loadWithOverviewMode = true
            builtInZoomControls = false
            displayZoomControls = false
            setSupportZoom(false)
            textZoom = 100
            userAgentString =
                "Mozilla/5.0 (Linux; Android 10; HK17 Pro Max) AppleWebKit/537.36 " +
                    "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
        }
        webView.isLongClickable = false
        webView.isHapticFeedbackEnabled = false
        webView.setOnLongClickListener { true }
        webView.setOnCreateContextMenuListener { menu: ContextMenu, _, _ -> menu.clear() }
        webView.setOnTouchListener { _, event ->
            event.pointerCount > 1 || event.actionMasked == MotionEvent.ACTION_POINTER_DOWN
        }
        webView.webChromeClient = object : WebChromeClient() {
            override fun onConsoleMessage(consoleMessage: ConsoleMessage): Boolean {
                lastConsoleMessage =
                    "${consoleMessage.message()} (${consoleMessage.sourceId()}:${consoleMessage.lineNumber()})"
                return true
            }
        }
        webView.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                view.loadUrl(request.url.toString())
                return true
            }

            override fun onPageFinished(view: WebView, url: String) {
                disablePageZoomAndSelection(view)
                webView.visibility = View.VISIBLE
                verifyPageHasContentOrReload()
            }

            override fun shouldInterceptRequest(
                view: WebView,
                request: WebResourceRequest,
            ): WebResourceResponse? {
                val originalUrl = request.url.toString()
                val upgradedUrl = BackendMediaUrlPolicy.upgradeToHttpsIfBackendMedia(originalUrl)
                if (upgradedUrl == originalUrl) return null

                return runCatching { openHttpsResource(upgradedUrl) }.getOrNull()
            }

            override fun onReceivedHttpError(
                view: WebView,
                request: WebResourceRequest,
                errorResponse: WebResourceResponse,
            ) {
                if (request.isForMainFrame) {
                    showOfflineMessage("Website unavailable (${errorResponse.statusCode})")
                }
            }

            override fun onReceivedError(
                view: WebView,
                request: WebResourceRequest,
                error: WebResourceError,
            ) {
                if (request.isForMainFrame) showOfflineMessage("Connection unavailable")
            }
        }
    }

    private fun openHttpsResource(url: String): WebResourceResponse {
        val connection = (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = RESOURCE_CONNECT_TIMEOUT_MS
            readTimeout = RESOURCE_READ_TIMEOUT_MS
            instanceFollowRedirects = true
            setRequestProperty("Accept", "image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8")
        }
        val contentType = connection.contentType ?: "application/octet-stream"
        val mimeType = contentType.substringBefore(";").trim().ifBlank { "application/octet-stream" }
        val charset = contentType.substringAfter("charset=", "").substringBefore(";").ifBlank { null }
        return WebResourceResponse(mimeType, charset, connection.inputStream)
    }

    private fun createLayout(): View {
        webView = object : WebView(this) {
            override fun performLongClick(): Boolean = true

            override fun startActionMode(callback: ActionMode.Callback?): ActionMode? = null

            override fun startActionMode(
                callback: ActionMode.Callback?,
                type: Int,
            ): ActionMode? = null
        }
        offlineView = TextView(this).apply {
            setBackgroundColor(Color.WHITE)
            setTextColor(Color.rgb(28, 28, 28))
            text = "Connection unavailable"
            textSize = 22f
            gravity = Gravity.CENTER
            visibility = View.GONE
        }
        loadingView = TextView(this).apply {
            setBackgroundColor(Color.WHITE)
            setTextColor(Color.rgb(28, 28, 28))
            text = "Loading forum..."
            textSize = 22f
            gravity = Gravity.CENTER
            visibility = View.VISIBLE
        }

        wifiButton = ImageButton(this).apply {
            setImageResource(R.drawable.ic_wifi)
            setBackgroundColor(Color.TRANSPARENT)
            scaleType = ImageView.ScaleType.CENTER
            contentDescription = "Wi-Fi"
            setOnClickListener {
                if (wifiPanelGate.tryEnter()) {
                    toggleWifiPanel()
                }
            }
        }

        batteryText = TextView(this).apply {
            textSize = 12f
            gravity = Gravity.CENTER
            setTextColor(Color.rgb(218, 185, 73))
            includeFontPadding = false
        }

        val batteryIndicator = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            addView(
                batteryText,
                LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    ViewGroup.LayoutParams.MATCH_PARENT,
                ),
            )
            addView(
                ImageView(this@MainActivity).apply {
                    setImageResource(R.drawable.ic_battery)
                    setColorFilter(Color.rgb(218, 185, 73))
                    scaleType = ImageView.ScaleType.CENTER
                },
                LinearLayout.LayoutParams(dp(18), dp(18)),
            )
            setOnTouchListener { view, event ->
                when (event.actionMasked) {
                    MotionEvent.ACTION_DOWN -> {
                        reloadActionPending = true
                        actionHandler.postDelayed({
                            if (reloadActionPending) {
                                reloadActionPending = false
                                reloadWebsite()
                            }
                        }, CONTROL_PRESS_DURATION_MS)
                    }

                    MotionEvent.ACTION_UP -> {
                        reloadActionPending = false
                        actionHandler.removeCallbacksAndMessages(null)
                        view.performClick()
                    }

                    MotionEvent.ACTION_CANCEL -> {
                        reloadActionPending = false
                        actionHandler.removeCallbacksAndMessages(null)
                    }
                }
                false
            }
        }

        val brightnessButton = ImageButton(this).apply {
            setImageResource(R.drawable.ic_brightness)
            setColorFilter(ACTIVE_CONTROL_COLOR)
            setBackgroundColor(Color.TRANSPARENT)
            scaleType = ImageView.ScaleType.CENTER
            contentDescription = "Brightness"
            setOnClickListener { toggleBrightnessPanel() }
        }

        brightnessSlider = SeekBar(this).apply {
            max = 100
            progress = currentBrightnessProgress()
            setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                override fun onProgressChanged(seekBar: SeekBar, progress: Int, fromUser: Boolean) {
                    if (fromUser) setAppBrightness(progress)
                }

                override fun onStartTrackingTouch(seekBar: SeekBar) {
                    brightnessHandler.removeCallbacksAndMessages(null)
                }

                override fun onStopTrackingTouch(seekBar: SeekBar) {
                    scheduleBrightnessPanelHide()
                }
            })
        }

        val brightnessMinusButton = TextView(this).apply {
            text = "-"
            textSize = 18f
            gravity = Gravity.CENTER
            setTextColor(ACTIVE_CONTROL_COLOR)
            includeFontPadding = false
            contentDescription = "Decrease brightness"
            setOnClickListener { adjustBrightness(-BRIGHTNESS_STEP) }
        }

        val brightnessPlusButton = TextView(this).apply {
            text = "+"
            textSize = 18f
            gravity = Gravity.CENTER
            setTextColor(ACTIVE_CONTROL_COLOR)
            includeFontPadding = false
            contentDescription = "Increase brightness"
            setOnClickListener { adjustBrightness(BRIGHTNESS_STEP) }
        }

        brightnessPanel = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setPadding(dp(6), 0, dp(6), 0)
            setBackgroundColor(Color.argb(220, 6, 36, 22))
            visibility = View.GONE
            addView(
                brightnessMinusButton,
                LinearLayout.LayoutParams(dp(28), ViewGroup.LayoutParams.MATCH_PARENT),
            )
            addView(
                brightnessSlider,
                LinearLayout.LayoutParams(dp(128), ViewGroup.LayoutParams.WRAP_CONTENT),
            )
            addView(
                brightnessPlusButton,
                LinearLayout.LayoutParams(dp(28), ViewGroup.LayoutParams.MATCH_PARENT),
            )
        }

        wifiStatusText = TextView(this).apply {
            textSize = 12f
            gravity = Gravity.CENTER
            setTextColor(ACTIVE_CONTROL_COLOR)
            includeFontPadding = false
        }

        wifiPowerButton = TextView(this).apply {
            textSize = 12f
            gravity = Gravity.CENTER
            setTextColor(ACTIVE_CONTROL_COLOR)
            includeFontPadding = false
            setPadding(dp(6), dp(5), dp(6), dp(5))
            setOnClickListener { toggleWifiPower() }
        }

        val wifiRefreshButton = TextView(this).apply {
            text = "Refresh"
            textSize = 12f
            gravity = Gravity.CENTER
            setTextColor(ACTIVE_CONTROL_COLOR)
            includeFontPadding = false
            setPadding(dp(6), dp(5), dp(6), dp(5))
            setOnClickListener { refreshWifiPanel() }
        }

        val wifiPanelCloseButton = TextView(this).apply {
            text = "x"
            textSize = 14f
            gravity = Gravity.CENTER
            setTextColor(ACTIVE_CONTROL_COLOR)
            includeFontPadding = false
            contentDescription = "Close Wi-Fi status"
            setPadding(dp(6), dp(5), dp(6), dp(5))
            setOnClickListener {
                clearWifiSelection()
                wifiPanel.visibility = View.GONE
                wifiPanelHandler.removeCallbacksAndMessages(null)
                wifiPanelGate.reset()
                enterFullscreen()
                startKioskMode()
            }
        }

        val wifiPanelHeader = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            addView(
                wifiPowerButton,
                LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f),
            )
            addView(
                wifiRefreshButton,
                LinearLayout.LayoutParams(dp(70), ViewGroup.LayoutParams.WRAP_CONTENT),
            )
            addView(
                wifiPanelCloseButton,
                LinearLayout.LayoutParams(dp(28), ViewGroup.LayoutParams.WRAP_CONTENT),
            )
        }

        wifiNetworksContainer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
        }

        wifiPasswordDisplay = TextView(this).apply {
            text = "Password"
            textSize = 12f
            gravity = Gravity.CENTER_VERTICAL
            setTextColor(Color.WHITE)
            setPadding(dp(8), dp(6), dp(8), dp(6))
            setBackgroundColor(Color.argb(130, 2, 18, 12))
            visibility = View.GONE
            setOnClickListener {
                if (selectedWifiNetwork?.security == WifiSecurity.WPA_PSK) {
                    wifiKeyboardContainer.visibility = View.VISIBLE
                    renderWifiKeyboard()
                    enforceKioskAfterWifiAction()
                }
            }
        }

        wifiKeyboardContainer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            visibility = View.GONE
        }

        val wifiConnectButton = TextView(this).apply {
            text = "Connect"
            textSize = 12f
            gravity = Gravity.CENTER
            setTextColor(ACTIVE_CONTROL_COLOR)
            includeFontPadding = false
            setPadding(dp(6), dp(6), dp(6), dp(6))
            setOnClickListener { connectSelectedWifiNetwork() }
        }

        wifiMessageText = TextView(this).apply {
            textSize = 11f
            setTextColor(INACTIVE_CONTROL_COLOR)
            includeFontPadding = false
            setPadding(dp(6), dp(3), dp(6), dp(6))
        }

        wifiPanel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(8), dp(6), dp(8), dp(6))
            setBackgroundColor(Color.argb(225, 6, 36, 22))
            visibility = View.GONE
            addView(
                wifiPanelHeader,
                LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                ),
            )
            addView(
                wifiStatusText,
                LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                ),
            )
            addView(
                wifiNetworksContainer,
                LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                ),
            )
            addView(
                wifiPasswordDisplay,
                LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                ),
            )
            addView(
                wifiKeyboardContainer,
                LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                ),
            )
            addView(
                wifiConnectButton,
                LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                ),
            )
            addView(
                wifiMessageText,
                LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                ),
            )
        }

        val exitHotspot = View(this).apply {
            alpha = 0.02f
            setBackgroundColor(Color.TRANSPARENT)
            contentDescription = "Exit"
            setOnTouchListener { view, event ->
                when (event.actionMasked) {
                    MotionEvent.ACTION_DOWN -> {
                        enterFullscreen()
                        exitDialogPending = true
                        exitHandler.postDelayed({
                            if (exitDialogPending) {
                                exitDialogPending = false
                                showExitPinDialog()
                            }
                        }, EXIT_PRESS_DURATION_MS)
                    }

                    MotionEvent.ACTION_UP -> {
                        exitDialogPending = false
                        exitHandler.removeCallbacksAndMessages(null)
                        view.performClick()
                    }

                    MotionEvent.ACTION_CANCEL -> {
                        exitDialogPending = false
                        exitHandler.removeCallbacksAndMessages(null)
                    }
                }
                false
            }
        }

        return FrameLayout(this).apply {
            setBackgroundColor(Color.WHITE)
            addView(
                webView,
                FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT,
                ),
            )
            addView(
                offlineView,
                FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT,
                ),
            )
            addView(
                loadingView,
                FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT,
                ),
            )
            addView(
                wifiButton,
                FrameLayout.LayoutParams(dp(28), dp(28), Gravity.TOP or Gravity.END).apply {
                    topMargin = dp(3)
                    marginEnd = dp(10)
                },
            )
            addView(
                batteryIndicator,
                FrameLayout.LayoutParams(dp(56), dp(24), Gravity.TOP or Gravity.END).apply {
                    topMargin = dp(6)
                    marginEnd = dp(42)
                },
            )
            addView(
                brightnessButton,
                FrameLayout.LayoutParams(dp(28), dp(28), Gravity.TOP or Gravity.END).apply {
                    topMargin = dp(3)
                    marginEnd = dp(100)
                },
            )
            addView(
                brightnessPanel,
                FrameLayout.LayoutParams(dp(202), dp(34), Gravity.TOP or Gravity.END).apply {
                    topMargin = dp(34)
                    marginEnd = dp(64)
                },
            )
            addView(
                wifiPanel,
                FrameLayout.LayoutParams(dp(260), dp(420), Gravity.TOP or Gravity.END).apply {
                    topMargin = dp(34)
                    marginEnd = dp(8)
                },
            )
            addView(
                exitHotspot,
                FrameLayout.LayoutParams(dp(48), dp(48), Gravity.TOP or Gravity.START),
            )
        }
    }

    private fun updateBattery(intent: Intent) {
        if (!::batteryText.isInitialized) return

        val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
        val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
        if (level < 0 || scale <= 0) return

        val percent = (level * 100) / scale
        batteryText.text = "$percent%"
    }

    private fun updateWifiStatus() {
        if (!::wifiButton.isInitialized) return

        val color = if (isWifiConnected()) ACTIVE_CONTROL_COLOR else INACTIVE_CONTROL_COLOR
        wifiButton.setColorFilter(color)
        if (::wifiStatusText.isInitialized) {
            wifiStatusText.text = if (isWifiConnected()) "Wi-Fi connected" else "Wi-Fi offline"
            wifiStatusText.setTextColor(color)
        }
    }

    private fun isWifiConnected(): Boolean {
        val connectivityManager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val network = connectivityManager.activeNetwork ?: return false
        val capabilities = connectivityManager.getNetworkCapabilities(network) ?: return false
        return capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) &&
            capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
    }

    private fun configureDeviceOwnerPolicies() {
        if (!devicePolicyManager.isDeviceOwnerApp(packageName)) return

        devicePolicyManager.setLockTaskPackages(adminComponent, arrayOf(packageName))
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
            devicePolicyManager.setLockTaskFeatures(
                adminComponent,
                DevicePolicyManager.LOCK_TASK_FEATURE_NONE,
            )
        }
        runCatching {
            devicePolicyManager.setPermissionGrantState(
                adminComponent,
                packageName,
                Manifest.permission.ACCESS_FINE_LOCATION,
                DevicePolicyManager.PERMISSION_GRANT_STATE_GRANTED,
            )
        }
        devicePolicyManager.setKeyguardDisabled(adminComponent, true)
        devicePolicyManager.setStatusBarDisabled(adminComponent, true)
    }

    private fun startKioskMode() {
        val isAlreadyLocked = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
            val activityManager = getSystemService(ActivityManager::class.java)
            activityManager.lockTaskModeState != ActivityManager.LOCK_TASK_MODE_NONE
        } else {
            false
        }

        if (!isAlreadyLocked) {
            try {
                startLockTask()
            } catch (_: IllegalStateException) {
                Toast.makeText(
                    this,
                    "Set this app as Device Owner to enable full kiosk mode.",
                    Toast.LENGTH_LONG,
                ).show()
            }
        }
    }

    private fun stopKioskMode() {
        try {
            stopLockTask()
        } catch (_: IllegalStateException) {
            // App was not running in lock-task mode.
        }

        if (devicePolicyManager.isDeviceOwnerApp(packageName)) {
            devicePolicyManager.setStatusBarDisabled(adminComponent, false)
            devicePolicyManager.setKeyguardDisabled(adminComponent, false)
        }
    }

    private fun showExitPinDialog() {
        enterFullscreen()

        val pinInput = EditText(this).apply {
            inputType = android.text.InputType.TYPE_CLASS_NUMBER or
                android.text.InputType.TYPE_NUMBER_VARIATION_PASSWORD
            hint = "PIN"
            setSingleLine(true)
        }

        val dialog = AlertDialog.Builder(this)
            .setTitle("Exit kiosk")
            .setView(pinInput)
            .setNegativeButton("Cancel", null)
            .setPositiveButton("Exit", null)
            .create()

        dialog.setOnShowListener {
            dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                if (PinValidator.isExitPin(pinInput.text.toString())) {
                    dialog.dismiss()
                    exitApplication()
                } else {
                    pinInput.text.clear()
                    pinInput.error = "Wrong PIN"
                }
            }
        }
        dialog.setOnDismissListener { enterFullscreen() }
        dialog.show()
    }

    private fun toggleWifiPanel() {
        enterFullscreen()
        configureDeviceOwnerPolicies()
        startKioskMode()
        refreshWifiPanel()

        if (wifiPanel.visibility == View.VISIBLE) {
            clearWifiSelection()
            wifiPanel.visibility = View.GONE
            wifiPanelHandler.removeCallbacksAndMessages(null)
            wifiPanelGate.reset()
        } else {
            wifiPanel.visibility = View.VISIBLE
            if (!KioskActionPolicy.shouldAutoHide(KioskAction.WIFI_PANEL)) {
                wifiPanelHandler.removeCallbacksAndMessages(null)
            }
        }
    }

    private fun refreshWifiPanel() {
        updateWifiStatus()
        wifiPowerButton.text = if (wifiController.isWifiEnabled()) "Wi-Fi ON" else "Wi-Fi OFF"
        wifiStatusText.text = wifiController.currentSsid()?.let { "Connected: $it" } ?: "Wi-Fi offline"
        refreshWifiNetworks()
    }

    private fun refreshWifiNetworks() {
        if (!::wifiNetworksContainer.isInitialized) return
        wifiNetworksContainer.removeAllViews()
        val networks = runCatching { wifiController.scanNetworks() }
            .getOrElse {
                if (::wifiMessageText.isInitialized) {
                    wifiMessageText.text = WifiOperationMessages.blocked().message
                }
                emptyList()
            }
            .take(6)
        networks.forEach { network ->
            wifiNetworksContainer.addView(createWifiNetworkRow(network))
        }
    }

    private fun createWifiNetworkRow(network: WifiNetworkInfo): View =
        TextView(this).apply {
            text = buildString {
                append(if (network.connected) "* " else "")
                append(network.ssid)
                append("  ")
                append(if (network.secured) "lock" else "open")
                append("  ")
                append("${network.signalLevel}/3")
            }
            textSize = 12f
            setTextColor(if (network.connected) ACTIVE_CONTROL_COLOR else Color.WHITE)
            includeFontPadding = false
            setPadding(dp(6), dp(5), dp(6), dp(5))
            setOnClickListener {
                wifiPasswordState.reset()
                updateWifiPasswordDisplay()
                selectedWifiNetwork = network
                val needsPassword = network.security == WifiSecurity.WPA_PSK
                wifiPasswordDisplay.visibility = if (needsPassword) View.VISIBLE else View.GONE
                wifiKeyboardContainer.visibility = if (needsPassword) View.VISIBLE else View.GONE
                if (needsPassword) renderWifiKeyboard()
                wifiMessageText.text = if (network.security == WifiSecurity.UNSUPPORTED) {
                    WifiOperationMessages.unsupportedSecurity().message
                } else {
                    network.ssid
                }
            }
        }

    private fun renderWifiKeyboard() {
        if (!::wifiKeyboardContainer.isInitialized) return
        wifiKeyboardContainer.removeAllViews()
        val rows = if (wifiPasswordState.mode == WifiKeyboardMode.LETTERS) {
            listOf(
                listOf("q", "w", "e", "r", "t", "y", "u", "i", "o", "p"),
                listOf("a", "s", "d", "f", "g", "h", "j", "k", "l"),
                listOf("Shift", "z", "x", "c", "v", "b", "n", "m", "Backspace"),
                listOf("123", "Clear", "Done"),
            )
        } else {
            listOf(
                listOf("1", "2", "3", "4", "5", "6", "7", "8", "9", "0"),
                listOf("!", "@", "#", "$", "%", "&", "*", "_", "-", "."),
                listOf("ABC", "/", ":", ";", "?", "+", "=", "Backspace"),
                listOf("Clear", "Done"),
            )
        }
        rows.forEach { labels ->
            wifiKeyboardContainer.addView(createWifiKeyboardRow(labels))
        }
    }

    private fun createWifiKeyboardRow(labels: List<String>): LinearLayout =
        LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            labels.forEach { label ->
                addView(
                    createWifiKeyboardKey(label),
                    LinearLayout.LayoutParams(0, dp(28), wifiKeyboardKeyWeight(label)).apply {
                        setMargins(dp(1), dp(1), dp(1), dp(1))
                    },
                )
            }
        }

    private fun wifiKeyboardKeyWeight(label: String): Float =
        when (label) {
            "Backspace" -> 1.45f
            "Shift", "Clear", "Done", "123", "ABC" -> 1.2f
            else -> 1f
        }

    private fun createWifiKeyboardKey(label: String): TextView =
        TextView(this).apply {
            text = wifiKeyboardDisplayLabel(label)
            textSize = if (label == "Backspace") 9f else 11f
            gravity = Gravity.CENTER
            includeFontPadding = false
            maxLines = 1
            setTextColor(ACTIVE_CONTROL_COLOR)
            setBackgroundColor(Color.argb(180, 10, 48, 30))
            setOnClickListener { handleWifiKeyboardKey(label) }
        }

    private fun wifiKeyboardDisplayLabel(label: String): String =
        when (label) {
            "Backspace" -> "Bksp"
            "Clear" -> "Clr"
            "Shift" -> if (wifiPasswordState.shifted) "SHFT" else "Shift"
            else -> label
        }

    private fun handleWifiKeyboardKey(label: String) {
        when (label) {
            "Shift" -> wifiPasswordState.toggleShift()
            "123", "ABC" -> wifiPasswordState.toggleMode()
            "Backspace" -> wifiPasswordState.backspace()
            "Clear" -> wifiPasswordState.reset()
            "Done" -> wifiKeyboardContainer.visibility = View.GONE
            else -> wifiPasswordState.appendKey(label)
        }
        updateWifiPasswordDisplay()
        renderWifiKeyboard()
        enforceKioskAfterWifiAction()
    }

    private fun updateWifiPasswordDisplay() {
        if (!::wifiPasswordDisplay.isInitialized) return
        wifiPasswordDisplay.text = wifiPasswordState.maskedPassword().ifBlank { "Password" }
    }

    private fun toggleWifiPower() {
        enforceKioskAfterWifiAction()
        val result = wifiController.setWifiEnabled(!wifiController.isWifiEnabled())
        showWifiResult(result)
        refreshWifiPanel()
        enforceKioskAfterWifiAction()
    }

    private fun connectSelectedWifiNetwork() {
        enforceKioskAfterWifiAction()
        val network = selectedWifiNetwork ?: run {
            wifiMessageText.text = "Select Wi-Fi network"
            return
        }
        val password = wifiPasswordState.password
        wifiPasswordState.reset()
        val result = wifiController.connect(network, password)
        showWifiResult(result)
        selectedWifiNetwork = null
        wifiPasswordDisplay.visibility = View.GONE
        wifiKeyboardContainer.visibility = View.GONE
        refreshWifiPanel()
        enforceKioskAfterWifiAction()
    }

    private fun showWifiResult(result: WifiConnectionResult) {
        wifiMessageText.text = when (result) {
            WifiConnectionResult.Success -> "Wi-Fi action started"
            is WifiConnectionResult.Failure -> result.message
        }
    }

    private fun enforceKioskAfterWifiAction() {
        enterFullscreen()
        configureDeviceOwnerPolicies()
        startKioskMode()
    }

    private fun clearWifiSelection() {
        selectedWifiNetwork = null
        wifiPasswordState.reset()
        if (::wifiPasswordDisplay.isInitialized) {
            updateWifiPasswordDisplay()
            wifiPasswordDisplay.visibility = View.GONE
        }
        if (::wifiKeyboardContainer.isInitialized) {
            wifiKeyboardContainer.visibility = View.GONE
        }
    }

    private fun toggleBrightnessPanel() {
        enterFullscreen()
        if (brightnessPanel.visibility == View.VISIBLE) {
            brightnessPanel.visibility = View.GONE
            brightnessHandler.removeCallbacksAndMessages(null)
        } else {
            brightnessSlider.progress = currentBrightnessProgress()
            brightnessPanel.visibility = View.VISIBLE
            scheduleBrightnessPanelHide()
        }
    }

    private fun scheduleBrightnessPanelHide() {
        brightnessHandler.removeCallbacksAndMessages(null)
        brightnessHandler.postDelayed({
            if (::brightnessPanel.isInitialized) {
                brightnessPanel.visibility = View.GONE
            }
        }, BRIGHTNESS_PANEL_HIDE_DELAY_MS)
    }

    private fun currentBrightnessProgress(): Int {
        val current = window.attributes.screenBrightness
        val normalized = if (current in 0f..1f) current else 0.65f
        return (normalized * 100).toInt().coerceIn(MIN_BRIGHTNESS_PROGRESS, 100)
    }

    private fun adjustBrightness(delta: Int) {
        brightnessHandler.removeCallbacksAndMessages(null)
        val nextProgress = (brightnessSlider.progress + delta).coerceIn(MIN_BRIGHTNESS_PROGRESS, 100)
        brightnessSlider.progress = nextProgress
        setAppBrightness(nextProgress)
        scheduleBrightnessPanelHide()
    }

    private fun setAppBrightness(progress: Int) {
        val safeProgress = progress.coerceIn(MIN_BRIGHTNESS_PROGRESS, 100)
        val attributes = window.attributes
        attributes.screenBrightness = safeProgress / 100f
        window.attributes = attributes
    }

    private fun reloadWebsite() {
        enterFullscreen()
        blankPageReloadCount = 0
        webView.clearCache(true)
        webView.clearHistory()
        webView.clearFormData()
        loadingView.text = "Reloading forum..."
        loadingView.visibility = View.VISIBLE
        offlineView.visibility = View.GONE
        webView.loadUrl(KIOSK_URL)
    }

    private fun disablePageZoomAndSelection(view: WebView) {
        view.evaluateJavascript(
            """
            (function() {
              var viewport = document.querySelector('meta[name="viewport"]');
              if (!viewport) {
                viewport = document.createElement('meta');
                viewport.name = 'viewport';
                document.head.appendChild(viewport);
              }
              viewport.content = 'width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no';

              var style = document.getElementById('kiosk-no-select-style');
              if (!style) {
                style = document.createElement('style');
                style.id = 'kiosk-no-select-style';
                document.head.appendChild(style);
              }
              style.textContent = [
                '* {',
                '  -webkit-user-select: none !important;',
                '  user-select: none !important;',
                '  -webkit-touch-callout: none !important;',
                '}',
                'html, body {',
                '  touch-action: pan-x pan-y !important;',
                '}'
              ].join('\n');
            })();
            """.trimIndent(),
            null,
        )
    }

    private fun exitApplication() {
        if (KioskActionPolicy.shouldStopKioskFor(KioskAction.PIN_EXIT)) {
            stopKioskMode()
        }
        finishAndRemoveTask()
    }

    private fun loadKioskPage() {
        blankPageReloadCount = 0
        loadingView.text = "Loading forum..."
        loadingView.visibility = View.VISIBLE
        offlineView.visibility = View.GONE
        webView.visibility = View.VISIBLE

        if (hasNetwork()) {
            webView.onResume()
            webView.resumeTimers()
            webView.loadUrl(KIOSK_URL)
            webView.postDelayed({
                if (webView.url.isNullOrBlank()) {
                    webView.loadUrl(KIOSK_URL)
                } else {
                    webView.reload()
                }
            }, 3_000L)
            webView.postDelayed({ webView.reload() }, 8_000L)
            webView.postDelayed({ webView.reload() }, 15_000L)
            webView.postDelayed({ verifyPageHasContentOrReload() }, 20_000L)
        } else {
            showOfflineMessage("Connection unavailable")
        }
    }

    private fun showOfflineMessage(message: String) {
        webView.visibility = View.GONE
        loadingView.visibility = View.GONE
        offlineView.text = "$message\nRetrying..."
        offlineView.visibility = View.VISIBLE
        offlineView.postDelayed({ loadKioskPage() }, RETRY_DELAY_MS)
    }

    private fun verifyPageHasContentOrReload() {
        webView.postDelayed({
            webView.evaluateJavascript(
                """
                (function() {
                  var app = document.getElementById('app');
                  var textLength = (document.body && document.body.innerText || '').trim().length;
                  var appArea = app ? (app.scrollWidth * app.scrollHeight) : 0;
                  var bodyArea = document.body ? (document.body.scrollWidth * document.body.scrollHeight) : 0;
                  return textLength + appArea + bodyArea;
                })();
                """.trimIndent(),
            ) { rawResult ->
                val visibleScore = rawResult.trim('"').toIntOrNull() ?: 0
                val looksBlank = visibleScore == 0
                if (looksBlank && hasNetwork()) {
                    blankPageReloadCount += 1
                    loadingView.text = "Reloading forum..."
                    loadingView.visibility = View.VISIBLE
                    offlineView.visibility = View.GONE
                    if (blankPageReloadCount <= MAX_BLANK_PAGE_RELOADS) {
                        webView.reload()
                    } else {
                        showRenderProblem()
                    }
                } else {
                    blankPageReloadCount = 0
                    loadingView.visibility = View.GONE
                    offlineView.visibility = View.GONE
                    webView.visibility = View.VISIBLE
                }
            }
        }, BLANK_PAGE_CHECK_DELAY_MS)
    }

    private fun showRenderProblem() {
        val message = if (lastConsoleMessage.isBlank()) {
            "Website did not render.\nPlease update Android System WebView or Chrome, then reload."
        } else {
            "Website did not render.\n$lastConsoleMessage"
        }
        loadingView.text = "$message\nRetrying..."
        loadingView.visibility = View.VISIBLE
        offlineView.visibility = View.GONE
        webView.clearCache(true)
        blankPageReloadCount = 0
        webView.postDelayed({ webView.loadUrl(KIOSK_URL) }, RETRY_DELAY_MS)
    }

    private fun hasNetwork(): Boolean {
        val connectivityManager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val network = connectivityManager.activeNetwork ?: return false
        val capabilities = connectivityManager.getNetworkCapabilities(network) ?: return false
        return capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
    }

    private fun enterFullscreen() {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
            window.insetsController?.let { controller ->
                controller.hide(WindowInsets.Type.statusBars() or WindowInsets.Type.navigationBars())
                controller.systemBarsBehavior =
                    WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = (
                View.SYSTEM_UI_FLAG_FULLSCREEN
                    or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                    or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                    or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                    or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                    or View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                )
        }
    }

    private fun keepSystemUiHidden() {
        window.decorView.setOnSystemUiVisibilityChangeListener {
            enterFullscreen()
        }
        window.decorView.setOnClickListener {
            enterFullscreen()
        }
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    companion object {
        private const val KIOSK_URL = "https://forum.iccu.uz/"
        private const val RETRY_DELAY_MS = 5_000L
        private const val BLANK_PAGE_CHECK_DELAY_MS = 1_200L
        private const val MAX_BLANK_PAGE_RELOADS = 3
        private const val EXIT_PRESS_DURATION_MS = 5_000L
        private const val CONTROL_PRESS_DURATION_MS = 3_000L
        private const val WIFI_PANEL_COOLDOWN_MS = 6_000L
        private const val BRIGHTNESS_PANEL_HIDE_DELAY_MS = 6_000L
        private const val RELOCK_AFTER_EXTERNAL_PANEL_DELAY_MS = 1_000L
        private const val RESOURCE_CONNECT_TIMEOUT_MS = 8_000
        private const val RESOURCE_READ_TIMEOUT_MS = 12_000
        private const val MIN_BRIGHTNESS_PROGRESS = 5
        private const val BRIGHTNESS_STEP = 10
        private val ACTIVE_CONTROL_COLOR = Color.rgb(218, 185, 73)
        private val INACTIVE_CONTROL_COLOR = Color.rgb(110, 118, 102)
    }
}
