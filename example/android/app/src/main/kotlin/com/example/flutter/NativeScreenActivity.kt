package com.example.flutter

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Shader
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import android.widget.Button
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

class NativeScreenActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val root =
            LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER_HORIZONTAL
                setBackgroundColor(Color.parseColor("#3F51B5"))
                setPadding(56, 96, 56, 96)
            }

        root.addView(hero())
        root.addView(spacer(28))
        root.addView(text("Unlock Premium", 28f, bold = true))
        root.addView(text("Get the most out of your app", 15f, alpha = "#D9"))
        root.addView(spacer(24))
        root.addView(text("✓  Unlimited session replays", 16f))
        root.addView(text("✓  Priority support", 16f))
        root.addView(text("✓  Advanced analytics", 16f))
        root.addView(spacer(24))
        root.addView(text("$9.99 / month", 24f, bold = true))
        root.addView(spacer(20))
        root.addView(
            Button(this).apply {
                text = "Subscribe"
                setOnClickListener { finish() }
            },
        )
        root.addView(
            Button(this).apply {
                text = "Restore purchases"
                setBackgroundColor(Color.TRANSPARENT)
                setTextColor(Color.parseColor("#D9FFFFFF"))
                setOnClickListener { finish() }
            },
        )
        root.addView(spacer(12))
        root.addView(text("Cancel anytime · Terms apply", 12f, alpha = "#99"))

        setContentView(
            ScrollView(this).apply {
                setBackgroundColor(Color.parseColor("#3F51B5"))
                addView(
                    root,
                    ViewGroup.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.WRAP_CONTENT,
                    ),
                )
            },
        )
    }

    private fun text(
        value: String,
        size: Float,
        bold: Boolean = false,
        alpha: String = "#FF",
    ) = TextView(this).apply {
        this.text = value
        setTextColor(Color.parseColor(alpha + "FFFFFF"))
        textSize = size
        gravity = Gravity.CENTER
        if (bold) setTypeface(typeface, android.graphics.Typeface.BOLD)
    }

    private fun spacer(heightDp: Int) =
        android.view.View(this).apply {
            layoutParams = LinearLayout.LayoutParams(1, heightDp)
        }

    private fun hero() =
        ImageView(this).apply {
            setImageBitmap(heroBitmap())
            layoutParams = LinearLayout.LayoutParams(480, 240)
            scaleType = ImageView.ScaleType.FIT_CENTER
        }

    private fun heroBitmap(): Bitmap {
        val bmp = Bitmap.createBitmap(240, 120, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        paint.shader =
            LinearGradient(
                0f, 0f, 240f, 120f,
                Color.parseColor("#EC407A"), Color.parseColor("#FF7043"),
                Shader.TileMode.CLAMP,
            )
        canvas.drawRect(0f, 0f, 240f, 120f, paint)
        paint.shader = null
        paint.color = Color.WHITE
        canvas.drawCircle(120f, 60f, 28f, paint)
        return bmp
    }
}
