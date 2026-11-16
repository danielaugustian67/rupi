package com.daniel.keuangan_ai

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/// Widget layar utama: saldo bulan ini + tombol tambah cepat.
class RupiWidget : HomeWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray, data: SharedPreferences) {
        for (id in ids) {
            val v = RemoteViews(context.packageName, R.layout.rupi_widget)
            v.setTextViewText(R.id.judul, data.getString("judul", "Saldo bulan ini"))
            v.setTextViewText(R.id.saldo, data.getString("saldo", "Buka Rupi"))
            v.setTextViewText(R.id.rincian, data.getString("rincian", ""))
            v.setOnClickPendingIntent(R.id.root, HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java))
            v.setOnClickPendingIntent(R.id.tambah, HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse("rupi://tambah")))
            manager.updateAppWidget(id, v)
        }
    }
}
