package com.example.libview

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import android.util.Xml
import org.xmlpull.v1.XmlPullParser
import java.io.File
import java.io.InputStream
import java.util.zip.ZipFile
import kotlin.math.max
import kotlin.math.min

internal object OfficeThumbnailRenderer {
    private const val MAX_WIDTH = 400
    private const val EMU_PER_INCH = 914400L

    fun render(file: File, ext: String): Bitmap? {
        if (!file.exists() || file.length() < 64) return null
        return try {
            ZipFile(file).use { zip ->
                embeddedPreview(zip)
                    ?: when (ext) {
                        "pptx", "pptm", "ppsx", "ppsm" -> renderPptx(zip)
                        "docx", "docm" -> renderDocx(zip)
                        "xlsx", "xlsm" -> renderXlsx(zip)
                        else -> null
                    }
                    ?: firstMediaImage(zip)
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun embeddedPreview(zip: ZipFile): Bitmap? {
        val names = listOf(
            "docProps/thumbnail.jpeg",
            "docProps/thumbnail.jpg",
            "docProps/thumbnail.png",
            "docProps/thumbnail.wmf",
        )
        for (name in names) {
            val bitmap = decodeZipImage(zip, name, MAX_WIDTH, MAX_WIDTH * 2) ?: continue
            return scaleToMaxWidth(bitmap)
        }
        return null
    }

    private fun firstMediaImage(zip: ZipFile): Bitmap? {
        val entries = zip.entries().toList()
            .map { it.name }
            .filter { name ->
                val lower = name.lowercase()
                (lower.startsWith("ppt/media/") ||
                    lower.startsWith("word/media/") ||
                    lower.startsWith("xl/media/")) &&
                    lower.substringAfterLast('.') in setOf("jpg", "jpeg", "png", "webp", "gif")
            }
            .sorted()
        for (name in entries) {
            val bitmap = decodeZipImage(zip, name, MAX_WIDTH, MAX_WIDTH) ?: continue
            return scaleToMaxWidth(bitmap)
        }
        return null
    }

    private fun scaleToMaxWidth(bitmap: Bitmap): Bitmap {
        if (bitmap.width <= MAX_WIDTH) return bitmap
        val height = (bitmap.height * MAX_WIDTH.toFloat() / bitmap.width).toInt().coerceAtLeast(1)
        val scaled = Bitmap.createScaledBitmap(bitmap, MAX_WIDTH, height, true)
        if (scaled != bitmap) bitmap.recycle()
        return scaled
    }

    // --- PowerPoint first slide ------------------------------------------------

    private fun renderPptx(zip: ZipFile): Bitmap? {
        val slidePart = firstSlidePart(zip) ?: return null
        val rels = readRels(zip, relsPathFor(slidePart))
        var slideCx = 12192000L
        var slideCy = 6858000L
        zip.getEntry("ppt/presentation.xml")?.let { entry ->
            zip.getInputStream(entry).use { input ->
                val parser = xmlParser(input)
                while (parser.next() != XmlPullParser.END_DOCUMENT) {
                    if (parser.eventType == XmlPullParser.START_TAG && parser.tag() == "sldSz") {
                        slideCx = attrLong(parser, "cx") ?: slideCx
                        slideCy = attrLong(parser, "cy") ?: slideCy
                    }
                }
            }
        }
        val width = MAX_WIDTH
        val height = (MAX_WIDTH * slideCy / slideCx.toFloat()).toInt().coerceIn(225, 560)
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.drawColor(Color.WHITE)

        val slideEntry = zip.getEntry(slidePart) ?: return null
        zip.getInputStream(slideEntry).use { input ->
            val parser = xmlParser(input)
            var inBg = 0
            while (parser.next() != XmlPullParser.END_DOCUMENT) {
                when (parser.eventType) {
                    XmlPullParser.START_TAG -> when (parser.tag()) {
                        "bg", "bgPr" -> inBg++
                        "srgbClr" -> if (inBg > 0) {
                            attrHexColor(parser, "val")?.let { canvas.drawColor(it) }
                        }
                        "pic" -> drawPptxPic(parser, canvas, zip, slidePart, rels, slideCx, slideCy, width, height)
                        "sp" -> drawPptxSp(parser, canvas, slideCx, slideCy, width, height)
                    }
                    XmlPullParser.END_TAG -> if (parser.tag() == "bg" || parser.tag() == "bgPr") {
                        inBg = (inBg - 1).coerceAtLeast(0)
                    }
                }
            }
        }
        return bitmap
    }

    private fun firstSlidePart(zip: ZipFile): String? {
        val presentationRels = readRels(zip, "ppt/_rels/presentation.xml.rels")
        var firstRid: String? = null
        zip.getEntry("ppt/presentation.xml")?.let { entry ->
            zip.getInputStream(entry).use { input ->
                val parser = xmlParser(input)
                while (parser.next() != XmlPullParser.END_DOCUMENT) {
                    if (parser.eventType == XmlPullParser.START_TAG && parser.tag() == "sldId") {
                        firstRid = attrNs(parser, REL_NS, "id") ?: attr(parser, "id")
                        break
                    }
                }
            }
        }
        val target = firstRid?.let { presentationRels[it] }
        if (!target.isNullOrBlank()) {
            return resolveZipPath("ppt/presentation.xml", target)
        }
        return if (zip.getEntry("ppt/slides/slide1.xml") != null) "ppt/slides/slide1.xml" else null
    }

    private fun drawPptxPic(
        parser: XmlPullParser,
        canvas: Canvas,
        zip: ZipFile,
        slidePart: String,
        rels: Map<String, String>,
        slideCx: Long,
        slideCy: Long,
        width: Int,
        height: Int,
    ) {
        val box = Xfrm()
        var embed: String? = null
        val startDepth = parser.depth
        while (parser.next() != XmlPullParser.END_DOCUMENT) {
            if (parser.eventType == XmlPullParser.END_TAG && parser.tag() == "pic" && parser.depth == startDepth) {
                break
            }
            if (parser.eventType != XmlPullParser.START_TAG) continue
            when (parser.tag()) {
                "off" -> {
                    box.x = attrLong(parser, "x") ?: box.x
                    box.y = attrLong(parser, "y") ?: box.y
                }
                "ext" -> {
                    box.cx = attrLong(parser, "cx") ?: box.cx
                    box.cy = attrLong(parser, "cy") ?: box.cy
                }
                "blip" -> embed = attrNs(parser, REL_NS, "embed") ?: attr(parser, "embed")
            }
        }
        val part = embed?.let { rels[it] }?.let { resolveZipPath(slidePart, it) } ?: return
        val dest = emuRect(box, slideCx, slideCy, width, height)
        val image = decodeZipImage(
            zip,
            part,
            dest.width().toInt().coerceAtLeast(1),
            dest.height().toInt().coerceAtLeast(1),
        ) ?: return
        canvas.drawBitmap(image, null, dest, null)
        image.recycle()
    }

    private fun drawPptxSp(
        parser: XmlPullParser,
        canvas: Canvas,
        slideCx: Long,
        slideCy: Long,
        width: Int,
        height: Int,
    ) {
        val box = Xfrm()
        val text = StringBuilder()
        var fontSz = 1800
        var color = Color.BLACK
        var fill: Int? = null
        val startDepth = parser.depth
        while (parser.next() != XmlPullParser.END_DOCUMENT) {
            if (parser.eventType == XmlPullParser.END_TAG && parser.tag() == "sp" && parser.depth == startDepth) {
                break
            }
            if (parser.eventType == XmlPullParser.START_TAG) {
                when (parser.tag()) {
                    "off" -> {
                        box.x = attrLong(parser, "x") ?: box.x
                        box.y = attrLong(parser, "y") ?: box.y
                    }
                    "ext" -> {
                        box.cx = attrLong(parser, "cx") ?: box.cx
                        box.cy = attrLong(parser, "cy") ?: box.cy
                    }
                    "srgbClr" -> {
                        val parsed = attrHexColor(parser, "val")
                        if (parsed != null) {
                            if (fill == null) fill = parsed else color = parsed
                        }
                    }
                    "sz" -> fontSz = attr(parser, "val")?.toIntOrNull() ?: fontSz
                    "t" -> {
                        if (parser.next() == XmlPullParser.TEXT) {
                            if (text.isNotEmpty()) text.append(' ')
                            text.append(parser.text)
                        }
                    }
                }
            }
        }
        val dest = emuRect(box, slideCx, slideCy, width, height)
        if (fill != null && fill != Color.WHITE) {
            val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = fill!! }
            canvas.drawRect(dest, paint)
        }
        if (text.isNotBlank()) {
            val textPx = (fontSz * width * 127f / slideCx).coerceIn(6f, 42f)
            drawText(canvas, text.toString(), dest, textPx, color)
        }
    }

    // --- Word first page ------------------------------------------------------

    private fun renderDocx(zip: ZipFile): Bitmap? {
        val part = "word/document.xml"
        if (zip.getEntry(part) == null) return null
        val rels = readRels(zip, relsPathFor(part))
        val width = MAX_WIDTH
        val height = (MAX_WIDTH * 11f / 8.5f).toInt()
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.drawColor(Color.WHITE)
        val margin = width * 0.08f
        var y = margin
        val maxY = height - margin
        val contentWidth = width - margin * 2
        val textPx = (11f / 72f) * (width / 8.5f)
        val paragraphPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.BLACK
            textSize = textPx.coerceAtLeast(6f)
            typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.NORMAL)
        }

        zip.getInputStream(zip.getEntry(part)).use { input ->
            val parser = xmlParser(input)
            val paragraph = StringBuilder()
            while (parser.next() != XmlPullParser.END_DOCUMENT && y < maxY) {
                when (parser.eventType) {
                    XmlPullParser.START_TAG -> when (parser.tag()) {
                        "blip" -> {
                            if (paragraph.isNotBlank()) {
                                y = flushParagraph(canvas, paragraph, margin, y, contentWidth, maxY, paragraphPaint)
                            }
                            val embed = attrNs(parser, REL_NS, "embed") ?: attr(parser, "embed")
                            val imagePart = embed?.let { rels[it] }?.let { resolveZipPath(part, it) }
                            if (imagePart != null) {
                                val imgH = (contentWidth * 0.45f)
                                val image = decodeZipImage(zip, imagePart, contentWidth.toInt(), imgH.toInt())
                                if (image != null) {
                                    val destH = image.height * contentWidth / image.width.toFloat()
                                    val dest = RectF(margin, y, margin + contentWidth, min(y + destH, maxY))
                                    canvas.drawBitmap(image, null, dest, null)
                                    image.recycle()
                                    y = dest.bottom + 8f
                                }
                            }
                        }
                        "br", "cr" -> paragraph.append('\n')
                        "tab" -> paragraph.append(' ')
                        "t" -> {
                            if (parser.next() == XmlPullParser.TEXT) {
                                paragraph.append(parser.text)
                            }
                        }
                    }
                    XmlPullParser.END_TAG -> if (parser.tag() == "p") {
                        y = flushParagraph(canvas, paragraph, margin, y, contentWidth, maxY, paragraphPaint)
                    }
                }
            }
            if (y < maxY && paragraph.isNotBlank()) {
                flushParagraph(canvas, paragraph, margin, y, contentWidth, maxY, paragraphPaint)
            }
        }
        return bitmap
    }

    private fun flushParagraph(
        canvas: Canvas,
        paragraph: StringBuilder,
        x: Float,
        y: Float,
        width: Float,
        maxY: Float,
        paint: TextPaint,
    ): Float {
        val text = paragraph.toString().trim()
        paragraph.clear()
        if (text.isEmpty()) return y + paint.textSize * 0.6f
        if (y >= maxY) return y
        @Suppress("DEPRECATION")
        val layout = StaticLayout(
            text,
            paint,
            width.toInt().coerceAtLeast(1),
            Layout.Alignment.ALIGN_NORMAL,
            1.15f,
            0f,
            false,
        )
        val allowed = (maxY - y).toInt().coerceAtLeast(0)
        canvas.save()
        canvas.translate(x, y)
        canvas.clipRect(0f, 0f, width, allowed.toFloat())
        layout.draw(canvas)
        canvas.restore()
        return y + min(layout.height.toFloat(), allowed.toFloat()) + 4f
    }

    // --- Excel first sheet ----------------------------------------------------

    private fun renderXlsx(zip: ZipFile): Bitmap? {
        val sheetPart = firstSheetPart(zip) ?: return null
        val strings = readSharedStrings(zip)
        val rows = readSheetCells(zip, sheetPart, strings, maxRows = 12, maxCols = 8)
        if (rows.isEmpty()) return null

        val width = MAX_WIDTH
        val height = (MAX_WIDTH * 0.72f).toInt().coerceAtLeast(240)
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.drawColor(Color.WHITE)

        val cols = (rows.maxOfOrNull { it.size } ?: 1).coerceAtLeast(1)
        val rowCount = rows.size
        val pad = 8f
        val colW = (width - pad * 2) / cols
        val rowH = (height - pad * 2) / rowCount.toFloat()
        val line = Paint().apply {
            color = Color.parseColor("#E5E7EB")
            strokeWidth = 1f
        }
        val header = Paint().apply { color = Color.parseColor("#F3F4F6") }
        val textPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#111827")
            textSize = (rowH * 0.42f).coerceIn(8f, 14f)
        }

        canvas.drawRect(pad, pad, width - pad, pad + rowH, header)
        for (r in 0..rowCount) {
            val y = pad + r * rowH
            canvas.drawLine(pad, y, width - pad, y, line)
        }
        for (c in 0..cols) {
            val x = pad + c * colW
            canvas.drawLine(x, pad, x, height - pad, line)
        }

        for ((r, row) in rows.withIndex()) {
            for ((c, value) in row.withIndex()) {
                if (value.isBlank()) continue
                val x = pad + c * colW + 3f
                val y = pad + r * rowH + 3f
                val dest = RectF(x, y, pad + (c + 1) * colW - 3f, pad + (r + 1) * rowH - 3f)
                drawText(canvas, value, dest, textPaint.textSize, textPaint.color)
            }
        }
        return bitmap
    }

    private fun firstSheetPart(zip: ZipFile): String? {
        val rels = readRels(zip, "xl/_rels/workbook.xml.rels")
        var firstRid: String? = null
        zip.getEntry("xl/workbook.xml")?.let { entry ->
            zip.getInputStream(entry).use { input ->
                val parser = xmlParser(input)
                while (parser.next() != XmlPullParser.END_DOCUMENT) {
                    if (parser.eventType == XmlPullParser.START_TAG && parser.tag() == "sheet") {
                        firstRid = attrNs(parser, REL_NS, "id") ?: attr(parser, "id")
                        break
                    }
                }
            }
        }
        val target = firstRid?.let { rels[it] }
        if (!target.isNullOrBlank()) {
            return resolveZipPath("xl/workbook.xml", target)
        }
        return if (zip.getEntry("xl/worksheets/sheet1.xml") != null) {
            "xl/worksheets/sheet1.xml"
        } else {
            null
        }
    }

    private fun readSharedStrings(zip: ZipFile): List<String> {
        val entry = zip.getEntry("xl/sharedStrings.xml") ?: return emptyList()
        val values = mutableListOf<String>()
        zip.getInputStream(entry).use { input ->
            val parser = xmlParser(input)
            val current = StringBuilder()
            while (parser.next() != XmlPullParser.END_DOCUMENT) {
                when (parser.eventType) {
                    XmlPullParser.START_TAG -> if (parser.tag() == "si") current.clear()
                    XmlPullParser.END_TAG -> if (parser.tag() == "si") {
                        values.add(current.toString())
                    }
                    XmlPullParser.TEXT -> {
                        // handled via t
                    }
                }
                if (parser.eventType == XmlPullParser.START_TAG && parser.tag() == "t") {
                    if (parser.next() == XmlPullParser.TEXT) current.append(parser.text)
                }
            }
        }
        return values
    }

    private fun readSheetCells(
        zip: ZipFile,
        sheetPart: String,
        strings: List<String>,
        maxRows: Int,
        maxCols: Int,
    ): List<List<String>> {
        val entry = zip.getEntry(sheetPart) ?: return emptyList()
        val grid = LinkedHashMap<Int, HashMap<Int, String>>()
        zip.getInputStream(entry).use { input ->
            val parser = xmlParser(input)
            var row = 0
            var col = 0
            var type = ""
            var inV = false
            var inIs = false
            val value = StringBuilder()
            while (parser.next() != XmlPullParser.END_DOCUMENT) {
                when (parser.eventType) {
                    XmlPullParser.START_TAG -> when (parser.tag()) {
                        "c" -> {
                            type = attr(parser, "t").orEmpty()
                            val ref = attr(parser, "r")
                            if (ref != null) {
                                col = cellCol(ref)
                                row = cellRow(ref)
                            }
                            value.clear()
                            inV = false
                            inIs = false
                        }
                        "v" -> inV = true
                        "is" -> inIs = true
                        "t" -> if (inIs && parser.next() == XmlPullParser.TEXT) {
                            value.append(parser.text)
                        }
                    }
                    XmlPullParser.TEXT -> if (inV) value.append(parser.text)
                    XmlPullParser.END_TAG -> when (parser.tag()) {
                        "v" -> inV = false
                        "is" -> inIs = false
                        "c" -> {
                            if (row in 0 until maxRows && col in 0 until maxCols) {
                                val raw = value.toString()
                                val cell = when (type) {
                                    "s" -> strings.getOrNull(raw.toIntOrNull() ?: -1).orEmpty()
                                    else -> raw
                                }
                                grid.getOrPut(row) { HashMap() }[col] = cell
                            }
                            col++
                        }
                    }
                }
            }
        }
        if (grid.isEmpty()) return emptyList()
        val lastRow = min(grid.keys.max(), maxRows - 1)
        val lastCol = min(grid.values.maxOf { it.keys.maxOrNull() ?: 0 }, maxCols - 1)
        return (0..lastRow).map { r ->
            (0..lastCol).map { c -> grid[r]?.get(c).orEmpty() }
        }
    }

    // --- helpers --------------------------------------------------------------

    private class Xfrm {
        var x = 0L
        var y = 0L
        var cx = 0L
        var cy = 0L
    }

    private fun emuRect(box: Xfrm, slideCx: Long, slideCy: Long, width: Int, height: Int): RectF {
        val sx = width / slideCx.toFloat()
        val sy = height / slideCy.toFloat()
        val left = box.x * sx
        val top = box.y * sy
        val right = (box.x + box.cx.coerceAtLeast(EMU_PER_INCH / 20)) * sx
        val bottom = (box.y + box.cy.coerceAtLeast(EMU_PER_INCH / 20)) * sy
        return RectF(left, top, right, bottom)
    }

    private fun drawText(canvas: Canvas, text: String, dest: RectF, textSize: Float, color: Int) {
        if (dest.width() < 4f || dest.height() < 4f || text.isBlank()) return
        val paint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = color
            this.textSize = textSize.coerceAtLeast(5f)
        }
        @Suppress("DEPRECATION")
        val layout = StaticLayout(
            text,
            paint,
            dest.width().toInt().coerceAtLeast(1),
            Layout.Alignment.ALIGN_NORMAL,
            1.1f,
            0f,
            false,
        )
        canvas.save()
        canvas.translate(dest.left, dest.top)
        canvas.clipRect(0f, 0f, dest.width(), dest.height())
        layout.draw(canvas)
        canvas.restore()
    }

    private fun readRels(zip: ZipFile, relsPath: String): Map<String, String> {
        val entry = zip.getEntry(relsPath) ?: return emptyMap()
        val map = HashMap<String, String>()
        zip.getInputStream(entry).use { input ->
            val parser = xmlParser(input)
            while (parser.next() != XmlPullParser.END_DOCUMENT) {
                if (parser.eventType == XmlPullParser.START_TAG && parser.tag() == "Relationship") {
                    val id = attr(parser, "Id") ?: continue
                    val target = attr(parser, "Target") ?: continue
                    map[id] = target
                }
            }
        }
        return map
    }

    private fun relsPathFor(part: String): String {
        val dir = part.substringBeforeLast('/', "")
        val name = part.substringAfterLast('/')
        return if (dir.isEmpty()) "_rels/$name.rels" else "$dir/_rels/$name.rels"
    }

    private fun resolveZipPath(fromPart: String, target: String): String {
        var t = target.replace('\\', '/')
        if (t.startsWith("/")) t = t.trimStart('/')
        val baseDir = fromPart.substringBeforeLast('/', "")
        val parts = ArrayList<String>()
        if (baseDir.isNotEmpty()) parts += baseDir.split('/').filter { it.isNotEmpty() }
        parts += t.split('/')
        val stack = ArrayDeque<String>()
        for (part in parts) {
            when (part) {
                "", "." -> {}
                ".." -> if (stack.isNotEmpty()) stack.removeLast()
                else -> stack.addLast(part)
            }
        }
        return stack.joinToString("/")
    }

    private fun decodeZipImage(zip: ZipFile, entryName: String, maxW: Int, maxH: Int): Bitmap? {
        val entry = zip.getEntry(entryName) ?: return null
        val bytes = zip.getInputStream(entry).use { it.readBytes() }
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        val srcW = bounds.outWidth.coerceAtLeast(1)
        val srcH = bounds.outHeight.coerceAtLeast(1)
        var sample = 1
        while (srcW / sample > maxW * 2 || srcH / sample > maxH * 2) {
            sample *= 2
        }
        val options = BitmapFactory.Options().apply { inSampleSize = sample }
        return BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
    }

    private fun xmlParser(input: InputStream): XmlPullParser {
        val parser = Xml.newPullParser()
        parser.setFeature(XmlPullParser.FEATURE_PROCESS_NAMESPACES, true)
        parser.setInput(input, "UTF-8")
        return parser
    }

    private fun XmlPullParser.tag(): String = (name ?: "").substringAfter(':')

    private fun attr(parser: XmlPullParser, name: String): String? {
        return parser.getAttributeValue(null, name)
            ?: (0 until parser.attributeCount)
                .firstNotNullOfOrNull { i ->
                    if (parser.getAttributeName(i) == name ||
                        parser.getAttributeName(i).substringAfter(':') == name
                    ) {
                        parser.getAttributeValue(i)
                    } else {
                        null
                    }
                }
    }

    private fun attrNs(parser: XmlPullParser, ns: String, name: String): String? {
        return parser.getAttributeValue(ns, name) ?: attr(parser, name)
    }

    private fun attrLong(parser: XmlPullParser, name: String): Long? {
        return attr(parser, name)?.toLongOrNull()
    }

    private fun attrHexColor(parser: XmlPullParser, name: String): Int? {
        val raw = attr(parser, name)?.trim()?.removePrefix("#") ?: return null
        if (raw.length != 6) return null
        return try {
            Color.parseColor("#$raw")
        } catch (_: Exception) {
            null
        }
    }

    private fun cellCol(ref: String): Int {
        var n = 0
        for (c in ref) {
            if (!c.isLetter()) break
            n = n * 26 + (c.uppercaseChar() - 'A' + 1)
        }
        return (n - 1).coerceAtLeast(0)
    }

    private fun cellRow(ref: String): Int {
        val digits = ref.takeLastWhile { it.isDigit() }
        return (digits.toIntOrNull() ?: 1) - 1
    }

    private const val REL_NS =
        "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
}
