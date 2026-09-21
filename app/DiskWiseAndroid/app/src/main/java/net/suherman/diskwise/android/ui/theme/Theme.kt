package net.suherman.diskwise.android.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val Green = Color(0xFF0B6E4F)
private val GreenContainer = Color(0xFFD8F3E7)
private val OnGreen = Color(0xFFFFFFFF)
private val Surface = Color(0xFFF7FAF8)
private val OnSurface = Color(0xFF122018)

private val LightColors = lightColorScheme(
    primary = Green,
    onPrimary = OnGreen,
    primaryContainer = GreenContainer,
    onPrimaryContainer = Color(0xFF063D2C),
    secondary = Color(0xFF3D6B5A),
    surface = Surface,
    onSurface = OnSurface,
    background = Surface,
    onBackground = OnSurface
)

@Composable
fun DiskWiseTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = LightColors,
        content = content
    )
}
