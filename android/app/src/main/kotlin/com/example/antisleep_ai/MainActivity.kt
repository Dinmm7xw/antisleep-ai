package com.example.antisleep_ai

import android.Manifest
import android.app.PictureInPictureParams
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.util.Rational
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "antisleep_ai/background"
    private var autoPipEnabled = true
    private var lastLocation: Location? = null
    private var locationManager: LocationManager? = null

    private val locationListener = object : LocationListener {
        override fun onLocationChanged(location: Location) {
            lastLocation = location
        }
        @Deprecated("Deprecated in Java")
        override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
        override fun onProviderEnabled(provider: String) {}
        override fun onProviderDisabled(provider: String) {}
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enterPip" -> {
                        val entered = enterSystemPip()
                        result.success(entered)
                    }
                    "setAutoPip" -> {
                        autoPipEnabled = call.argument<Boolean>("enabled") ?: true
                        result.success(autoPipEnabled)
                    }
                    "startGps" -> {
                        startNativeGps()
                        result.success(true)
                    }
                    "getGps" -> {
                        val loc = lastLocation
                        if (loc != null) {
                            result.success(
                                mapOf(
                                    "lat" to loc.latitude,
                                    "lng" to loc.longitude,
                                    "speedKmh" to (loc.speed * 3.6),
                                    "heading" to loc.bearing.toDouble(),
                                    "accuracy" to loc.accuracy.toDouble()
                                )
                            )
                        } else {
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun startNativeGps() {
        try {
            if (ActivityCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED &&
                ActivityCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION) != PackageManager.PERMISSION_GRANTED
            ) {
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION),
                    1002
                )
                return
            }
            locationManager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
            val gpsEnabled = locationManager?.isProviderEnabled(LocationManager.GPS_PROVIDER) == true
            val netEnabled = locationManager?.isProviderEnabled(LocationManager.NETWORK_PROVIDER) == true
            if (gpsEnabled) {
                locationManager?.requestLocationUpdates(LocationManager.GPS_PROVIDER, 1000L, 1f, locationListener)
                lastLocation = locationManager?.getLastKnownLocation(LocationManager.GPS_PROVIDER)
            }
            if (netEnabled && lastLocation == null) {
                locationManager?.requestLocationUpdates(LocationManager.NETWORK_PROVIDER, 1000L, 1f, locationListener)
                lastLocation = locationManager?.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
            }
        } catch (_: Exception) {}
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (autoPipEnabled) {
            enterSystemPip()
        }
    }

    private fun enterSystemPip(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            return try {
                val params = PictureInPictureParams.Builder()
                    .setAspectRatio(Rational(9, 16))
                    .build()
                enterPictureInPictureMode(params)
            } catch (e: Exception) {
                false
            }
        }
        return false
    }
}
