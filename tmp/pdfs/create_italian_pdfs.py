from __future__ import annotations

import html
import re
from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    KeepTogether,
    ListFlowable,
    ListItem,
    PageBreak,
    Paragraph,
    Preformatted,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)


ROOT = Path(__file__).resolve().parents[2]
DOCS = ROOT / "docs"
OUTPUT = ROOT / "output" / "pdf"
OUTPUT.mkdir(parents=True, exist_ok=True)

REGULAR = "/System/Library/Fonts/Supplemental/Verdana.ttf"
BOLD = "/System/Library/Fonts/Supplemental/Verdana Bold.ttf"
pdfmetrics.registerFont(TTFont("Verdana", REGULAR))
pdfmetrics.registerFont(TTFont("Verdana-Bold", BOLD))

NAVY = colors.HexColor("#183B5B")
BLUE = colors.HexColor("#1F6FAA")
LIGHT_BLUE = colors.HexColor("#EAF3FA")
GRID = colors.HexColor("#B9C8D4")
TEXT = colors.HexColor("#1F2933")


def normalize(text: str) -> str:
    return (
        text.replace("—", "-")
        .replace("–", "-")
        .replace("↔", "<->")
        .replace("’", "'")
        .replace("“", '"')
        .replace("”", '"')
    )


def rich_text(text: str) -> str:
    value = html.escape(normalize(text))
    value = re.sub(r"`([^`]+)`", r'<font face="Courier">\1</font>', value)
    value = re.sub(r"\*\*([^*]+)\*\*", r"<b>\1</b>", value)
    return value


def make_styles(compact: bool):
    styles = getSampleStyleSheet()
    body_size = 7.4 if compact else 9.3
    return {
        "title": ParagraphStyle(
            "PdfTitle", parent=styles["Title"], fontName="Verdana-Bold", fontSize=18,
            leading=22, textColor=NAVY, spaceAfter=12,
        ),
        "h2": ParagraphStyle(
            "PdfH2", parent=styles["Heading2"], fontName="Verdana-Bold", fontSize=12,
            leading=15, textColor=NAVY, spaceBefore=10, spaceAfter=6,
        ),
        "h3": ParagraphStyle(
            "PdfH3", parent=styles["Heading3"], fontName="Verdana-Bold", fontSize=10,
            leading=13, textColor=BLUE, spaceBefore=8, spaceAfter=4,
        ),
        "body": ParagraphStyle(
            "PdfBody", parent=styles["BodyText"], fontName="Verdana", fontSize=body_size,
            leading=body_size * 1.42, textColor=TEXT, spaceAfter=5,
        ),
        "table": ParagraphStyle(
            "PdfTable", parent=styles["BodyText"], fontName="Verdana", fontSize=6.0 if compact else 7.1,
            leading=7.3 if compact else 8.8, textColor=TEXT,
        ),
        "table_header": ParagraphStyle(
            "PdfTableHeader", parent=styles["BodyText"], fontName="Verdana-Bold", fontSize=6.0 if compact else 7.1,
            leading=7.3 if compact else 8.8, textColor=colors.white, alignment=TA_CENTER,
        ),
        "code": ParagraphStyle(
            "PdfCode", parent=styles["Code"], fontName="Courier", fontSize=7.4,
            leading=9.2, leftIndent=6, rightIndent=6, textColor=TEXT,
        ),
    }


def split_table_row(line: str):
    return [cell.strip() for cell in line.strip().strip("|").split("|")]


def is_separator(line: str) -> bool:
    cells = split_table_row(line)
    return bool(cells) and all(re.fullmatch(r":?-{3,}:?", cell) for cell in cells)


def table_widths(column_count: int, compact: bool):
    if compact and column_count == 8:
        return [35, 68, 77, 116, 61, 56, 150, 205]
    if compact and column_count == 7:
        return [35, 80, 88, 130, 125, 180, 130]
    if compact and column_count == 3:
        return [52, 132, 580]
    if compact and column_count == 2:
        return [90, 674]
    if column_count == 3:
        return [128, 172, 200]
    if column_count == 2:
        return [150, 350]
    return [500 / column_count] * column_count


def markdown_story(source: Path, compact: bool):
    styles = make_styles(compact)
    lines = source.read_text(encoding="utf-8").splitlines()
    story = []
    index = 0
    while index < len(lines):
        line = lines[index]
        if not line.strip():
            index += 1
            continue
        if line.startswith("# "):
            story.append(Paragraph(rich_text(line[2:]), styles["title"]))
            index += 1
            continue
        if line.startswith("## "):
            if line[3:] in {
                "Instaurazione della comunicazione verso uSS presso il cliente",
                "Separazione dei domini di sicurezza",
            }:
                story.append(PageBreak())
            story.append(Paragraph(rich_text(line[3:]), styles["h2"]))
            index += 1
            continue
        if line.startswith("### "):
            story.append(Paragraph(rich_text(line[4:]), styles["h3"]))
            index += 1
            continue
        if line.startswith("```"):
            index += 1
            code = []
            while index < len(lines) and not lines[index].startswith("```"):
                code.append(normalize(lines[index]))
                index += 1
            story.append(Preformatted("\n".join(code), styles["code"], maxLineLength=95))
            story.append(Spacer(1, 5))
            index += 1
            continue
        if line.startswith("|"):
            raw_rows = []
            while index < len(lines) and lines[index].startswith("|"):
                if not is_separator(lines[index]):
                    raw_rows.append(split_table_row(lines[index]))
                index += 1
            count = len(raw_rows[0])
            data = []
            for row_idx, row in enumerate(raw_rows):
                row = (row + [""] * count)[:count]
                style = styles["table_header"] if row_idx == 0 else styles["table"]
                data.append([Paragraph(rich_text(cell), style) for cell in row])
            table = Table(data, colWidths=table_widths(count, compact), repeatRows=1, hAlign="LEFT")
            table.setStyle(TableStyle([
                ("BACKGROUND", (0, 0), (-1, 0), NAVY),
                ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
                ("GRID", (0, 0), (-1, -1), 0.35, GRID),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 4),
                ("RIGHTPADDING", (0, 0), (-1, -1), 4),
                ("TOPPADDING", (0, 0), (-1, -1), 4),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
                ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, LIGHT_BLUE]),
            ]))
            story.append(table)
            story.append(Spacer(1, 8))
            continue
        ordered = re.match(r"^(\d+)\.\s+(.*)$", line)
        bullet = re.match(r"^-\s+(.*)$", line)
        if ordered or bullet:
            entries = []
            list_type = "1" if ordered else "bullet"
            while index < len(lines):
                match = re.match(r"^(\d+)\.\s+(.*)$", lines[index]) if ordered else re.match(r"^-\s+(.*)$", lines[index])
                if not match:
                    break
                content_group = 2 if ordered else 1
                entries.append(ListItem(Paragraph(rich_text(match.group(content_group)), styles["body"])))
                index += 1
            story.append(ListFlowable(entries, bulletType=list_type, leftIndent=16, bulletFontName="Verdana"))
            story.append(Spacer(1, 4))
            continue
        paragraph = [line.strip()]
        index += 1
        while index < len(lines) and lines[index].strip() and not re.match(r"^(#|\||```|[-]\s|\d+\.\s)", lines[index]):
            paragraph.append(lines[index].strip())
            index += 1
        story.append(Paragraph(rich_text(" ".join(paragraph)), styles["body"]))
    return story


def page_decorator(label: str):
    def decorate(canvas, document):
        canvas.saveState()
        width, height = document.pagesize
        canvas.setStrokeColor(GRID)
        canvas.setLineWidth(0.4)
        canvas.line(document.leftMargin, 13 * mm, width - document.rightMargin, 13 * mm)
        canvas.setFont("Verdana", 6.8)
        canvas.setFillColor(colors.HexColor("#536471"))
        canvas.drawString(document.leftMargin, 8.5 * mm, label)
        canvas.drawRightString(width - document.rightMargin, 8.5 * mm, f"Page {document.page}")
        canvas.restoreState()
    return decorate


def build(source_name: str, output_name: str, compact: bool):
    source = DOCS / source_name
    output = OUTPUT / output_name
    pagesize = landscape(A4) if compact else A4
    document = SimpleDocTemplate(
        str(output), pagesize=pagesize,
        leftMargin=12 * mm if compact else 18 * mm,
        rightMargin=12 * mm if compact else 18 * mm,
        topMargin=16 * mm, bottomMargin=19 * mm,
        title=source_name.replace(".md", ""), author="Arteco",
    )
    document.build(markdown_story(source, compact), onFirstPage=page_decorator("uSee / uSS"), onLaterPages=page_decorator("uSee / uSS"))


build("usee-network-flow-matrix.md", "usee-network-flow-matrix_it.pdf", compact=True)
build("usee-cloud-authentication-and-customer-communication.md", "usee-cloud-authentication-and-customer-communication_it.pdf", compact=False)
