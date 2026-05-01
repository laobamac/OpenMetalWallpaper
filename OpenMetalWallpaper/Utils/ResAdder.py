import os
import json
import shutil
import sys

VALID_TEXTURE_EXTENSIONS = {'.png', '.webp', '.tga', '.mp4'}
SEARCH_PREFIXES = ["", "materials", "particles", "models", "ui"]
RELEVANT_KEYS = {'image', 'texture', 'textures', 'file', 'model', 'particle', 'material', 'effect'}

def get_all_json_files(directory):
    json_files = []
    for root, _, files in os.walk(directory):
        for file in files:
            if file.lower().endswith('.json'):
                json_files.append(os.path.join(root, file))
    return json_files

def extract_references(json_path):
    refs = set()
    try:
        with open(json_path, 'r', encoding='utf-8', errors='ignore') as f:
            data = json.load(f)
        
        def recursive_scan(obj):
            if isinstance(obj, dict):
                for key, value in obj.items():
                    if key.lower() in RELEVANT_KEYS:
                        if isinstance(value, str):
                            refs.add(value)
                        elif isinstance(value, list):
                            for item in value:
                                if isinstance(item, str):
                                    refs.add(item)
                    recursive_scan(value)
            elif isinstance(obj, list):
                for item in obj:
                    recursive_scan(item)
        
        recursive_scan(data)
    except Exception:
        pass
    return refs

def normalize_path(path):
    return path.replace('\\', '/').strip('/')

def find_source_file(assets_root, relative_path):
    clean_rel = normalize_path(relative_path)
    base_name, original_ext = os.path.splitext(clean_rel)
    
    is_json_ref = original_ext.lower() == '.json'
    
    for prefix in SEARCH_PREFIXES:
        search_dir = os.path.join(assets_root, prefix)
        
        if is_json_ref:
            candidate = os.path.join(search_dir, clean_rel)
            if os.path.exists(candidate):
                return candidate
        else:
            for ext in VALID_TEXTURE_EXTENSIONS:
                candidate = os.path.join(search_dir, base_name + ext)
                if os.path.exists(candidate):
                    return candidate
    return None

def main():
    args = sys.argv[1:]
    force_overwrite = False
    if '-f' in args:
        force_overwrite = True
        args.remove('-f')

    if len(args) < 2:
        return

    assets_dir = args[0]
    wallpaper_dir = args[1]

    if not os.path.exists(assets_dir):
        return

    queue = get_all_json_files(wallpaper_dir)
    processed_jsons = set(os.path.abspath(p) for p in queue)
    
    idx = 0
    while idx < len(queue):
        current_json = queue[idx]
        idx += 1
        
        refs = extract_references(current_json)
        
        for ref in refs:
            if not ref or " " in ref and "/" not in ref:
                continue
                
            clean_ref = normalize_path(ref)
            
            src_file = find_source_file(assets_dir, ref)
            if not src_file:
                continue

            is_rooted = any(clean_ref.startswith(p + '/') for p in ["materials", "particles", "models", "ui"])
            if is_rooted:
                dest_rel = clean_ref
            else:
                dest_rel = "materials/" + clean_ref
            
            src_ext = os.path.splitext(src_file)[1]
            dest_path = os.path.join(wallpaper_dir, os.path.splitext(dest_rel)[0] + src_ext)

            if os.path.exists(dest_path) and not force_overwrite:
                continue

            try:
                os.makedirs(os.path.dirname(dest_path), exist_ok=True)
                shutil.copy2(src_file, dest_path)
                print(f"{os.path.basename(src_file)} -> {dest_path}")
                
                if src_file.lower().endswith('.json'):
                    abs_dest = os.path.abspath(dest_path)
                    if abs_dest not in processed_jsons:
                        queue.append(dest_path)
                        processed_jsons.add(abs_dest)
            except Exception:
                pass

if __name__ == "__main__":
    main()