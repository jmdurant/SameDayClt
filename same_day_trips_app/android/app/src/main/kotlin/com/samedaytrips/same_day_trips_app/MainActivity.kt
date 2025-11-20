package com.samedaytrips.same_day_trips_app

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import androidx.annotation.NonNull
import com.oguzhnatly.flutter_android_auto.FAAConstants
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.samedaytrips/android_auto"

    override fun provideFlutterEngine(@NonNull context: Context): FlutterEngine? {
        // Use engine from cache if started by Android Auto service
        return FlutterEngineCache.getInstance().get(FAAConstants.flutterEngineId)
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        // Cache the engine so Android Auto service can reuse it
        FlutterEngineCache.getInstance().put(FAAConstants.flutterEngineId, flutterEngine)
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isAndroidAutoMode" -> {
                        result.success(isAndroidAutoMode())
                    }
                    "launchNavigation" -> {
                        val destination = call.argument<String>("destination")
                        if (destination != null) {
                            launchGoogleMapsNavigation(destination)
                            result.success(true)
                        } else {
                            result.error("INVALID_ARGUMENT", "Destination is required", null)
                        }
                    }
                    "launchNavigationWithWaypoints" -> {
                        val destination = call.argument<String>("destination")
                        val waypoints = call.argument<List<String>>("waypoints")
                        if (destination != null) {
                            launchGoogleMapsWithWaypoints(
                                destination,
                                waypoints ?: emptyList()
                            )
                            result.success(true)
                        } else {
                            result.error("INVALID_ARGUMENT", "Destination is required", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun isAndroidAutoMode(): Boolean {
        return try {
            val isAutomotive =
                packageManager.hasSystemFeature(PackageManager.FEATURE_AUTOMOTIVE)
            val uiModeManager =
                getSystemService(android.content.Context.UI_MODE_SERVICE) as android.app.UiModeManager
            val isCarMode =
                uiModeManager.currentModeType == android.content.res.Configuration.UI_MODE_TYPE_CAR
            android.util.Log.d("AndroidAuto", "isAutomotive: $isAutomotive, isCarMode: $isCarMode")
            isAutomotive || isCarMode
        } catch (e: Exception) {
            android.util.Log.e("AndroidAuto", "Error detecting Android Auto: ${e.message}")
            false
        }
    }

    private fun launchGoogleMapsNavigation(destination: String) {
        try {
            val uri = Uri.parse("google.navigation:q=$destination&mode=d")
            val intent = Intent(Intent.ACTION_VIEW, uri).apply {
                setPackage("com.google.android.apps.maps")
            }
            startActivity(intent)
        } catch (e: Exception) {
            val uri =
                Uri.parse("https://www.google.com/maps/dir/?api=1&destination=$destination")
            val intent = Intent(Intent.ACTION_VIEW, uri)
            startActivity(intent)
        }
    }

    private fun launchGoogleMapsWithWaypoints(
        destination: String,
        waypoints: List<String>
    ) {
        try {
          val waypointsStr = waypoints.joinToString("|")
          val uri = if (waypoints.isNotEmpty()) {
            Uri.parse("https://www.google.com/maps/dir/?api=1&destination=$destination&waypoints=$waypointsStr&travelmode=driving")
          } else {
            Uri.parse("google.navigation:q=$destination&mode=d")
          }
          val intent = Intent(Intent.ACTION_VIEW, uri).apply {
            setPackage("com.google.android.apps.maps")
          }
          startActivity(intent)
        } catch (e: Exception) {
          launchGoogleMapsNavigation(destination)
        }
    }
}

