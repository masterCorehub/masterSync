package com.nexus.mastersync.services

import android.content.res.Configuration
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.inputmethodservice.InputMethodService
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.LinearLayout
import android.widget.TextView
import java.util.Locale

class NexusKeyboard : InputMethodService() {
    private enum class Layout { LETTERS, NUMBERS, ACCENTS }
    private data class Key(val text: String, val width: Float = 1f, val action: () -> Unit)
    private var layout = Layout.LETTERS
    private var shift = false
    private var keys: LinearLayout? = null
    private val portuguese = Locale.forLanguageTag("pt-BR")

    override fun onCreateInputView(): View = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(dp(4), dp(7), dp(4), dp(7))
        keys = this
        drawKeys()
    }

    override fun onStartInputView(info: EditorInfo?, restarting: Boolean) {
        super.onStartInputView(info, restarting)
        layout = when (info?.inputType?.and(android.text.InputType.TYPE_MASK_CLASS)) {
            android.text.InputType.TYPE_CLASS_NUMBER, android.text.InputType.TYPE_CLASS_PHONE -> Layout.NUMBERS
            else -> Layout.LETTERS
        }
        shift = false
        drawKeys()
    }

    override fun onEvaluateFullscreenMode() = false

    private fun drawKeys() {
        val container = keys ?: return
        container.removeAllViews()
        val dark = resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES
        container.setBackgroundColor(if (dark) 0xFF171C29.toInt() else 0xFFE7EAF3.toInt())
        val rows = when (layout) {
            Layout.LETTERS -> listOf("qwertyuiop", "asdfghjkl", "zxcvbnmç")
            Layout.NUMBERS -> listOf("1234567890", "@#\$%&*-+()", "!?\"'/:;_")
            Layout.ACCENTS -> listOf("áàâãéêí", "óôõúüç", "äëïöÿñ")
        }

        rows.forEachIndexed { index, characters ->
            val buttons = characters.map { char ->
                val value = if (shift) char.toString().uppercase(portuguese) else char.toString()
                Key(value) {
                    currentInputConnection?.commitText(value, 1)
                    if (shift) { shift = false; drawKeys() }
                }
            }
            val row = if (index == rows.lastIndex) listOf(Key(if (shift) "⬆" else "⇧", 1.2f) {
                shift = !shift
                drawKeys()
            }) + buttons + Key("⌫", 1.2f) { sendDownUpKeyEvents(KeyEvent.KEYCODE_DEL) } else buttons
            addRow(container, row, dark)
        }
        addRow(container, listOf(
            Key(if (layout == Layout.NUMBERS) "ABC" else "123", 1.25f) {
                layout = if (layout == Layout.NUMBERS) Layout.LETTERS else Layout.NUMBERS
                drawKeys()
            },
            Key(if (layout == Layout.ACCENTS) "ABC" else "á", 1f) {
                layout = if (layout == Layout.ACCENTS) Layout.LETTERS else Layout.ACCENTS
                drawKeys()
            },
            Key("🌐", 1f) { getSystemService(InputMethodManager::class.java).showInputMethodPicker() },
            Key("Espaço", 4f) { currentInputConnection?.commitText(" ", 1) },
            Key(".", 0.8f) { currentInputConnection?.commitText(".", 1) },
            Key("↵", 1.35f) { enter() }
        ), dark)
    }

    private fun addRow(container: LinearLayout, buttons: List<Key>, dark: Boolean) {
        val row = LinearLayout(this).apply { gravity = Gravity.CENTER }
        buttons.forEach { key ->
            row.addView(TextView(this).apply {
                text = key.text
                textSize = if (key.text.length > 2) 15f else 19f
                gravity = Gravity.CENTER
                typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
                setTextColor(if (dark) Color.WHITE else 0xFF202536.toInt())
                background = GradientDrawable().apply {
                    setColor(if (dark) 0xFF30374B.toInt() else Color.WHITE)
                    cornerRadius = dp(8).toFloat()
                }
                contentDescription = when (key.text) {
                    "🌐" -> "Escolher teclado"
                    "⇧", "⬆" -> "Maiúscula"
                    "⌫" -> "Apagar"
                    "↵" -> "Enter"
                    else -> key.text
                }
                isFocusable = true
                setOnClickListener { key.action() }
            }, LinearLayout.LayoutParams(0, dp(44), key.width).apply { setMargins(dp(2), dp(2), dp(2), dp(2)) })
        }
        container.addView(row)
    }

    private fun enter() {
        val info = currentInputEditorInfo
        val action = info?.imeOptions?.and(EditorInfo.IME_MASK_ACTION)
        if (action != null && action != EditorInfo.IME_ACTION_NONE && action != EditorInfo.IME_ACTION_UNSPECIFIED &&
            info.imeOptions and EditorInfo.IME_FLAG_NO_ENTER_ACTION == 0) {
            currentInputConnection?.performEditorAction(action)
        } else sendDownUpKeyEvents(KeyEvent.KEYCODE_ENTER)
    }

    private fun dp(value: Int) = (value * resources.displayMetrics.density + 0.5f).toInt()
}
