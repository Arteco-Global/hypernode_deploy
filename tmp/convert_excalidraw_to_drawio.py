from __future__ import annotations

import html
import json
from pathlib import Path
from xml.etree.ElementTree import Element, ElementTree, SubElement


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "docs/assets/uss-usee-global-architecture.excalidraw"
DESTINATION = ROOT / "docs/assets/uss-usee-global-architecture.drawio"
OFFSET_X = 460
OFFSET_Y = 30


def as_float(value: float | int | None) -> str:
    return f"{float(value or 0):.2f}".rstrip("0").rstrip(".")


def style_for_shape(element: dict) -> str:
    shape = "ellipse" if element["type"] == "ellipse" else "rounded=1"
    stroke = element.get("strokeColor", "#1e1e1e")
    fill = element.get("backgroundColor", "none")
    fill = "none" if fill == "transparent" else fill
    return (
        f"{shape};whiteSpace=wrap;html=1;strokeWidth={element.get('strokeWidth', 2)};"
        f"strokeColor={stroke};fillColor={fill};"
    )


def text_style(element: dict) -> str:
    alignment = {"left": "left", "center": "center", "right": "right"}.get(
        element.get("textAlign"), "center"
    )
    valign = {"top": "top", "middle": "middle", "bottom": "bottom"}.get(
        element.get("verticalAlign"), "middle"
    )
    return (
        "text;html=1;strokeColor=none;fillColor=none;whiteSpace=wrap;overflow=hidden;"
        f"align={alignment};verticalAlign={valign};fontColor={element.get('strokeColor', '#1e1e1e')};"
        f"fontSize={element.get('fontSize', 16)};fontFamily=Helvetica;"
    )


def add_vertex(parent: Element, element: dict, style: str, value: str = "") -> None:
    cell = SubElement(
        parent,
        "mxCell",
        id=element["id"],
        value=value,
        style=style,
        vertex="1",
        parent="1",
    )
    SubElement(
        cell,
        "mxGeometry",
        x=as_float(element.get("x", 0) + OFFSET_X),
        y=as_float(element.get("y", 0) + OFFSET_Y),
        width=as_float(element.get("width", 1)),
        height=as_float(element.get("height", 1)),
        **{"as": "geometry"},
    )


def add_edge(parent: Element, element: dict, existing_ids: set[str]) -> None:
    points = element.get("points") or [[0, 0], [element.get("width", 0), element.get("height", 0)]]
    start = element.get("startBinding") or {}
    end = element.get("endBinding") or {}
    source = start.get("elementId") if start.get("elementId") in existing_ids else None
    target = end.get("elementId") if end.get("elementId") in existing_ids else None
    start_arrow = "block" if element.get("startArrowhead") else "none"
    end_arrow = "block" if element["type"] == "arrow" or element.get("endArrowhead") else "none"
    style = (
        "edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;"
        f"strokeColor={element.get('strokeColor', '#1e1e1e')};strokeWidth={element.get('strokeWidth', 2)};"
        f"startArrow={start_arrow};endArrow={end_arrow};"
    )
    attributes = {
        "id": element["id"],
        "value": "",
        "style": style,
        "edge": "1",
        "parent": "1",
    }
    if source:
        attributes["source"] = source
    if target:
        attributes["target"] = target
    cell = SubElement(parent, "mxCell", **attributes)
    geometry = SubElement(cell, "mxGeometry", relative="1", **{"as": "geometry"})
    first = points[0]
    last = points[-1]
    SubElement(
        geometry,
        "mxPoint",
        x=as_float(element.get("x", 0) + first[0] + OFFSET_X),
        y=as_float(element.get("y", 0) + first[1] + OFFSET_Y),
        **{"as": "sourcePoint"},
    )
    SubElement(
        geometry,
        "mxPoint",
        x=as_float(element.get("x", 0) + last[0] + OFFSET_X),
        y=as_float(element.get("y", 0) + last[1] + OFFSET_Y),
        **{"as": "targetPoint"},
    )
    if len(points) > 2:
        array = SubElement(geometry, "Array", **{"as": "points"})
        for point in points[1:-1]:
            SubElement(
                array,
                "mxPoint",
                x=as_float(element.get("x", 0) + point[0] + OFFSET_X),
                y=as_float(element.get("y", 0) + point[1] + OFFSET_Y),
            )


def main() -> None:
    document = json.loads(SOURCE.read_text(encoding="utf-8"))
    elements = [item for item in document.get("elements", []) if not item.get("isDeleted")]
    element_ids = {item["id"] for item in elements if item["type"] in {"rectangle", "ellipse", "text"}}

    mxfile = Element("mxfile", host="app.diagrams.net", modified="2026-10-14T00:00:00.000Z", agent="Codex", version="26.0.0")
    diagram = SubElement(mxfile, "diagram", id="uss-usee-architecture", name="uSS + uSee architecture")
    model = SubElement(
        diagram,
        "mxGraphModel",
        dx="2400", dy="1400", grid="1", gridSize="10", guides="1", tooltips="1",
        connect="1", arrows="1", fold="1", page="1", pageScale="1", pageWidth="2339",
        pageHeight="1654", math="0", shadow="0",
    )
    root = SubElement(model, "root")
    SubElement(root, "mxCell", id="0")
    SubElement(root, "mxCell", id="1", parent="0")

    for element in elements:
        if element["type"] in {"rectangle", "ellipse"}:
            add_vertex(root, element, style_for_shape(element))
        elif element["type"] == "text":
            value = html.escape(element.get("text", "")).replace("\n", "<br>")
            add_vertex(root, element, text_style(element), value=value)

    for element in elements:
        if element["type"] in {"arrow", "line"}:
            add_edge(root, element, element_ids)

    ElementTree(mxfile).write(DESTINATION, encoding="utf-8", xml_declaration=True)
    print(f"Created {DESTINATION}")


if __name__ == "__main__":
    main()
