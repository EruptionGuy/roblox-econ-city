#!/usr/bin/env python3
"""Gói src/ thành file place .rbxlx, mở thẳng bằng Studio.

Map như Rojo: *.server.luau là Script, *.client.luau là LocalScript, *.luau là ModuleScript, thư mục là Folder.
Chạy: python3 tools/build_rbxlx.py [file_ra]
"""
import os
import sys
from xml.sax.saxutils import escape

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_ref = [0]


def ref():
    _ref[0] += 1
    return "RBX%08X" % _ref[0]


def cdata(text):
    return "<![CDATA[" + text.replace("]]>", "]]]]><![CDATA[>") + "]]>"


def item(cls, name, children="", extra=""):
    return (
        f'<Item class="{cls}" referent="{ref()}"><Properties>'
        f'<string name="Name">{escape(name)}</string>{extra}</Properties>{children}</Item>'
    )


def script_item(path, filename):
    with open(path, encoding="utf-8") as f:
        source = f.read()
    if filename.endswith(".server.luau"):
        cls, name = "Script", filename[: -len(".server.luau")]
    elif filename.endswith(".client.luau"):
        cls, name = "LocalScript", filename[: -len(".client.luau")]
    else:
        cls, name = "ModuleScript", filename[: -len(".luau")]
    extra = f'<ProtectedString name="Source">{cdata(source)}</ProtectedString>'
    return item(cls, name, extra=extra)


def folder_items(directory):
    parts = []
    for entry in sorted(os.listdir(directory)):
        full = os.path.join(directory, entry)
        if os.path.isdir(full):
            parts.append(item("Folder", entry, folder_items(full)))
        elif entry.endswith(".luau"):
            parts.append(script_item(full, entry))
    return "".join(parts)


def build(out_path):
    src = os.path.join(ROOT, "src")
    shared = item("Folder", "EconCity", folder_items(os.path.join(src, "shared")))
    server = item("Folder", "EconCityServer", folder_items(os.path.join(src, "server")))
    client = item("Folder", "EconCityClient", folder_items(os.path.join(src, "client")))
    body = "".join([
        item("Workspace", "Workspace"),
        # Technology 3 = ShadowMap, để mở file không bị hỏi "Lighting Technology Migration"
        item("Lighting", "Lighting", extra='<token name="Technology">3</token>'),
        item("ReplicatedStorage", "ReplicatedStorage", shared),
        item("ServerScriptService", "ServerScriptService", server),
        item("StarterPlayer", "StarterPlayer",
             item("StarterPlayerScripts", "StarterPlayerScripts", client)
             + item("StarterCharacterScripts", "StarterCharacterScripts")),
        item("StarterGui", "StarterGui"),
    ])
    xml = (
        '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">'
        '<External>null</External><External>nil</External>'
        + body + "</roblox>"
    )
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(xml)
    return out_path


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build", "EconCity.rbxlx")
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    print("Đã tạo", build(out))
