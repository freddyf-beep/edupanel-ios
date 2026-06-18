import os
import re
import sys
import hashlib

project_dir = os.getcwd()
pbxproj_path = os.path.join(project_dir, "EduPanel.xcodeproj", "project.pbxproj")

def generate_xcode_id(name, salt):
    h = hashlib.md5(f"{salt}:{name}".encode()).hexdigest().upper()
    return "44" + h[:22]

def sync_project():
    print("Sincronizando project.pbxproj con los archivos del disco...")
    if not os.path.exists(pbxproj_path):
        print(f"No se encuentra el archivo {pbxproj_path}")
        sys.exit(1)

    with open(pbxproj_path, "r", encoding="utf-8") as f:
        content = f.read()

    group_regex = re.compile(r"^[ \t]*(\w{24})\s*/\*\s*([^*]+)\s*\*/\s*=\s*\{\s*isa\s*=\s*PBXGroup;", re.MULTILINE)
    existing_groups = {}
    for match in group_regex.finditer(content):
        g_id, g_name = match.groups()
        existing_groups[g_name.strip()] = g_id

    if "EduPanel" not in existing_groups:
        existing_groups["EduPanel"] = "100000000000000000000010"

    all_swift_files = []
    edu_panel_path = os.path.join(project_dir, "EduPanel")
    for root, dirs, files in os.walk(edu_panel_path):
        for file in files:
            if file.endswith(".swift"):
                full_path = os.path.join(root, file)
                rel_path = os.path.relpath(full_path, project_dir)
                all_swift_files.append((file, rel_path))

    new_files = []
    for file_name, rel_path in all_swift_files:
        pattern = rf"/\*\s*{re.escape(file_name)}\s*\*/"
        if not re.search(pattern, content):
            new_files.append((file_name, rel_path))

    if not new_files:
        print("¡Todos los archivos del disco ya están referenciados!")
        return

    pbx_build_files = []
    pbx_file_refs = []
    group_children_additions = {}
    sources_build_additions = []
    new_groups_to_define = {}

    for f_name, r_path in new_files:
        parts = r_path.replace("\\", "/").split("/")
        file_id = generate_xcode_id(f_name, "file_ref")
        build_id = generate_xcode_id(f_name, "build_file")

        pbx_build_files.append(f"\t\t{build_id} /* {f_name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_id} /* {f_name} */; }};")
        pbx_file_refs.append(f"\t\t{file_id} /* {f_name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {f_name}; sourceTree = \"<group>\"; }};")

        parent_folder = parts[-2]
        grandparent_folder = parts[-3] if len(parts) >= 3 else None

        target_group_id = None
        if parent_folder in existing_groups:
            target_group_id = existing_groups[parent_folder]
        else:
            parent_group_id = generate_xcode_id(parent_folder, "group")
            if parent_folder not in existing_groups and parent_group_id not in new_groups_to_define:
                grandparent_id = existing_groups.get(grandparent_folder, existing_groups["Views"])
                new_groups_to_define[parent_group_id] = {
                    "name": parent_folder,
                    "path": parent_folder,
                    "children": [],
                    "parent_group_id": grandparent_id
                }
                if grandparent_id not in group_children_additions:
                    group_children_additions[grandparent_id] = []
                group_children_additions[grandparent_id].append(f"\t\t\t\t{parent_group_id} /* {parent_folder} */,")

            existing_groups[parent_folder] = parent_group_id
            target_group_id = parent_group_id

        if target_group_id not in group_children_additions:
            group_children_additions[target_group_id] = []
        group_children_additions[target_group_id].append(f"\t\t\t\t{file_id} /* {f_name} */,")

        if target_group_id in new_groups_to_define:
            new_groups_to_define[target_group_id]["children"].append(f"\t\t\t\t{file_id} /* {f_name} */,")

        sources_build_additions.append(f"\t\t\t\t{build_id} /* {f_name} in Sources */,")

    build_file_marker = "/* Begin PBXBuildFile section */"
    idx = content.find(build_file_marker)
    if idx != -1:
        content = content[:idx + len(build_file_marker)] + "\n" + "\n".join(pbx_build_files) + content[idx + len(build_file_marker):]

    file_ref_marker = "/* Begin PBXFileReference section */"
    idx = content.find(file_ref_marker)
    if idx != -1:
        content = content[:idx + len(file_ref_marker)] + "\n" + "\n".join(pbx_file_refs) + content[idx + len(file_ref_marker):]

    group_end_marker = "/* End PBXGroup section */"
    idx = content.find(group_end_marker)
    if idx != -1:
        new_groups_defs = []
        for g_id, g_info in new_groups_to_define.items():
            children_str = "\n".join(g_info["children"])
            group_def = f"""\t\t{g_id} /* {g_info["name"]} */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{children_str}
\t\t\t);
\t\t\tpath = {g_info["path"]};
\t\t\tsourceTree = "<group>";
\t\t}};"""
            new_groups_defs.append(group_def)
        if new_groups_defs:
            content = content[:idx] + "\n".join(new_groups_defs) + "\n" + content[idx:]

    for group_id, additions in group_children_additions.items():
        pattern_str = r"^([ \t]*" + re.escape(group_id) + r"[ \t]*/\*[^\n]*?\*/[ \t]*=[ \t]*\{[^{}]*?children[ \t]*=[ \t]*$)"
        group_pattern = re.compile(pattern_str, re.MULTILINE | re.DOTALL)
        match = group_pattern.search(content)
        if match:
            matched_str = match.group(1)
            valid_additions = [add for add in additions if add not in content]
            if valid_additions:
                insert_pos = content.find(matched_str) + len(matched_str)
                content = content[:insert_pos] + "\n" + "\n".join(valid_additions) + content[insert_pos:]

    sources_pattern = re.compile(r"^\s*(100000000000000000000006\s*/\*\s*Sources\s*\*/\s*=\s*\{.*?files\s*=\s*$)", re.MULTILINE | re.DOTALL)
    match = sources_pattern.search(content)
    if match:
        matched_str = match.group(1)
        valid_sources = [add for add in sources_build_additions if add not in content]
        if valid_sources:
            insert_pos = content.find(matched_str) + len(matched_str)
            content = content[:insert_pos] + "\n" + "\n".join(valid_sources) + content[insert_pos:]

    with open(pbxproj_path, "w", encoding="utf-8") as f:
        f.write(content)
    print("Sincronización robusta completada.")

if __name__ == "__main__":
    sync_project()
