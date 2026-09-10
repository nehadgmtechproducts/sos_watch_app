package com.dgm.sosemergency

import android.appwidget.AppWidgetManager
import android.content.Context
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Home-screen widget: a single big SOS button. Tapping it opens the app with
 * the sosemergency://sos URI, which the Flutter side (HomeScreen) detects and
 * fires the alert.
 */
class SosWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: android.content.SharedPreferences
    ) {
        appWidgetIds.forEach { id ->
            val views = RemoteViews(context.packageName, R.layout.sos_widget_layout)
            val pending = HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                android.net.Uri.parse("sosemergency://sos")
            )
            views.setOnClickPendingIntent(R.id.widget_sos_button, pending)
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
