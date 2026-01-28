import subprocess
import json
import time
import os
from datetime import datetime
import select

def log(msg):
    timestamp = datetime.now().strftime("%H:%M:%S.%f")[:-3]
    print(f"[{timestamp}] {msg}")

def send_request(proc, method, params=None, req_id=1):
    req = {
        "jsonrpc": "2.0",
        "id": req_id,
        "method": method,
        "params": params or {}
    }
    line = json.dumps(req) + "\n"
    proc.stdin.write(line.encode('utf-8'))
    proc.stdin.flush()

def read_response(proc, timeout=3):
    start = time.time()
    while time.time() - start < timeout:
        # Use select to wait for data on stdout
        ready, _, _ = select.select([proc.stdout], [], [], 0.1)
        if ready:
            line = proc.stdout.readline()
            if not line:
                break
            line = line.decode('utf-8').strip()
            if not line:
                continue
            # log(f"RAW: {line}") # Debug
            try:
                resp = json.loads(line)
                if "id" in resp:
                    return resp
            except json.JSONDecodeError:
                continue
        time.sleep(0.01)
    return None

def test_uibridge():
    server_path = "/System/Library/Tools/UIBridgeServer"
    if not os.path.exists(server_path):
        server_path = "/home/devuan/gershwin-build/repos/gershwin-components/UIBridge/Server/obj/UIBridgeServer"
    
    log(f"Starting {server_path}...")
    proc = subprocess.Popen([server_path], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    try:
        # 1. initialize
        log("Testing: initialize")
        send_request(proc, "initialize")
        resp = read_response(proc)
        assert resp and "result" in resp, f"Initialize failed or timed out: {resp}"
        
        # 2. list_apps
        log("Testing: list_apps")
        send_request(proc, "tools/call", {"name": "list_apps", "arguments": {}})
        resp = read_response(proc)
        assert resp and not resp.get("result", {}).get("isError"), f"list_apps failed or timed out: {resp}"
        
        # 3. launch_app
        log("Testing: launch_app (TextEdit)")
        subprocess.run(["pkill", "TextEdit"], capture_output=True)
        send_request(proc, "tools/call", {"name": "launch_app", "arguments": {"app_path": "/Local/Applications/TextEdit.app"}})
        resp = read_response(proc)
        assert resp and not resp.get("result", {}).get("isError"), f"launch_app failed or timed out: {resp}"
        
        time.sleep(3)
        
        # 4. get_root
        log("Testing: get_root")
        send_request(proc, "tools/call", {"name": "get_root", "arguments": {}})
        resp = read_response(proc)
        assert resp and not resp.get("result", {}).get("isError"), f"get_root failed or timed out: {resp}"
        root_data = json.loads(resp["result"]["content"][0]["text"])
        assert "windows" in root_data, "No windows in root_data"

        # 6. list_menus (Moved up so we can use it in hierarchy exploration if needed, 
        # and to avoid UnboundLocalError)
        log("Testing: list_menus")
        send_request(proc, "tools/call", {"name": "list_menus", "arguments": {}})
        resp = read_response(proc)
        assert resp and not resp.get("result", {}).get("isError"), f"list_menus failed or timed out: {resp}"
        menus = json.loads(resp["result"]["content"][0]["text"])
        log(f"Menu traversal complete. Found {len(menus)} menus.")
        
        # 5. get_object_details and subview exploration
        log("Testing: Window hierarchy exploration")
        editor_view_id = None
        
        # Ensure we have a document window open
        has_doc = False
        for win in root_data["windows"]:
            send_request(proc, "tools/call", {"name": "get_object_details", "arguments": {"object_id": win["object_id"]}})
            resp = read_response(proc)
            if resp and "result" in resp:
                d = json.loads(resp["result"]["content"][0]["text"])
                if "UNTITLED" in d.get("title", "").upper():
                    has_doc = True
                    break
        
        if not has_doc:
            log("No 'UNTITLED' window found. Creating a new one via Document -> New.")
            new_item = None
            for menu in menus:
                for item in menu.get("items", []):
                    if item.get("title") == "New":
                        new_item = item
                        break
                if new_item: break
            
            if new_item:
                send_request(proc, "tools/call", {"name": "invoke_menu_item", "arguments": {"object_id": new_item["object_id"]}})
                read_response(proc)
                time.sleep(1)
                # Refresh root
                send_request(proc, "tools/call", {"name": "get_root", "arguments": {}})
                resp = read_response(proc)
                root_data = json.loads(resp["result"]["content"][0]["text"])

        log(f"Found {len(root_data['windows'])} windows.")
        for win in root_data["windows"][:10]: # Check first 10
            win_id = win["object_id"]
            send_request(proc, "tools/call", {"name": "get_object_details", "arguments": {"object_id": win_id}})
            resp = read_response(proc)
            if not resp or "result" not in resp: continue
            win_details = json.loads(resp["result"]["content"][0]["text"])
            
            title = win_details.get("title", "NO TITLE")
            cls = win_details.get("class", "Unknown")
            log(f"  Window: '{title}' (Class: {cls}, ID: {win_id})")
            
            # Look for NSTextView in any window that has a contentView and is not a menu/panel
            if cls == "NSWindow" or cls == "NSPanel":
                content_view = win_details.get("contentView")
                if content_view:
                    cv_id = content_view["object_id"]
                    send_request(proc, "tools/call", {"name": "get_object_details", "arguments": {"object_id": cv_id}})
                    resp = read_response(proc)
                    if not resp or "result" not in resp: continue
                    cv_details = json.loads(resp["result"]["content"][0]["text"])
                    
                    subviews = cv_details.get("subviews", [])
                    # DFS for TextView
                    stack = list(subviews)
                    visited = set()
                    while stack:
                        item = stack.pop()
                        # item can be an object_id string or a dict reflecting the object
                        sv_id = item["object_id"] if isinstance(item, dict) else item
                        if not sv_id or sv_id in visited: continue
                        visited.add(sv_id)
                        
                        send_request(proc, "tools/call", {"name": "get_object_details", "arguments": {"object_id": sv_id}})
                        resp = read_response(proc)
                        if not resp or "result" not in resp: continue
                        sv_details = json.loads(resp["result"]["content"][0]["text"])
                        sv_cls = sv_details.get('class', '')
                        log(f"      Checking {sv_cls} ({sv_id})")
                        if "TextView" in sv_cls:
                            log(f"    Found Editor View: {sv_cls} ({sv_id}) in window '{title}'")
                            editor_view_id = sv_id
                            break
                        child_subviews = sv_details.get("subviews", [])
                        stack.extend(child_subviews)
                    if editor_view_id: break

        if editor_view_id:
            log(f"Found Editor View: {editor_view_id}")
            # 5b. Type into the editor
            log("Testing: Typing into editor")
            # We assume window is focused or use x11_type
            send_request(proc, "tools/call", {"name": "x11_type", "arguments": {"text": "Hello, UIBridge!\nThis is an automated TextEdit test.\n"}})
            read_response(proc)
            log("Typed text into editor.")
            
            # 5c. Select All
            log("Testing: Select All")
            send_request(proc, "tools/call", {"name": "invoke_selector", "arguments": {"object_id": editor_view_id, "selector": "selectAll:"}})
            read_response(proc)
            log("Selector selectAll: invoked.")
            
            # 5d. Make Bold via Menu
            log("Testing: Make Bold via Menu")
            bold_item = None
            for menu in menus:
                for item in menu.get("items", []):
                    if item.get("title") == "Bold":
                        bold_item = item
                        break
                if bold_item: break
            
            if bold_item:
                send_request(proc, "tools/call", {"name": "invoke_menu_item", "arguments": {"object_id": bold_item["object_id"]}})
                read_response(proc)
                log("Bold menu item invoked.")
            
            # 5e. Test Save As panel
            log("Testing: Open Save Panel")
            save_as_item = None
            for menu in menus:
                for item in menu.get("items", []):
                    if "Save As..." in item.get("title", ""):
                        save_as_item = item
                        break
                if save_as_item: break
            
            if save_as_item:
                send_request(proc, "tools/call", {"name": "invoke_menu_item", "arguments": {"object_id": save_as_item["object_id"]}})
                read_response(proc)
                log("Save As... menu item invoked. Waiting for panel...")
                time.sleep(1)
                # Check for new windows
                send_request(proc, "tools/call", {"name": "get_root", "arguments": {}})
                resp = read_response(proc)
                new_root = json.loads(resp["result"]["content"][0]["text"])
                log(f"Now found {len(new_root['windows'])} windows.")
                for win in new_root["windows"]:
                    log(f"  Window: '{win.get('title')}'")

        for menu in menus:
            m_title = menu.get("title", "UNTITLED")
            items = menu.get("items", [])
            item_titles = [i.get("title", "NO TITLE") for i in items]
            log(f"Menu '{m_title}' has items: {item_titles}")

        # 7. invoke_menu_item (Help -> About TextEdit or similar)
        log("Testing: invoke_menu_item (About/Info/Help)")
        target_item = None
        for menu in menus:
            menu_title = menu.get("title", "Unknown")
            for item in menu.get("items", []):
                title = item.get("title", "").lower()
                if "about" in title or "info panel" in title or "help" in title:
                    log(f"Found target item: '{item['title']}' in menu '{menu_title}'")
                    target_item = item
                    break
            if target_item:
                break

        if target_item:
            send_request(proc, "tools/call", {"name": "invoke_menu_item", "arguments": {"object_id": target_item["object_id"]}})
            resp = read_response(proc)
            assert resp and not resp.get("result", {}).get("isError"), f"invoke_menu_item failed or timed out: {resp}"
            log(f"Target menu item '{target_item['title']}' invoked successfully.")
        else:
            log("No About/Info/Help item found. Skipping.")
        log("Testing: invoke_menu_item (closest to 'About')")
        about_item_id = None
        about_item_title = None
        for menu in menus:
            for item in menu.get("items", []):
                title = item.get("title", "")
                if "about" in title.lower():
                    about_item_id = item["object_id"]
                    about_item_title = title
                    break
            if about_item_id: break
        
        if about_item_id:
            log(f"Found item: '{about_item_title}' (ID: {about_item_id})")
            send_request(proc, "tools/call", {"name": "invoke_menu_item", "arguments": {"object_id": about_item_id}})
            resp = read_response(proc)
            assert resp and not resp.get("result", {}).get("isError")
        else:
            log("Skipping invoke_menu_item: No 'About' item found")

        # 8. Quit TextEdit via menu
        log("Testing: Quit TextEdit via menu")
        quit_item_id = None
        for menu in menus:
            for item in menu.get("items", []):
                if "Quit" == item.get("title", ""):
                    quit_item_id = item["object_id"]
                    break
            if quit_item_id: break
            
        if quit_item_id:
            send_request(proc, "tools/call", {"name": "invoke_menu_item", "arguments": {"object_id": quit_item_id}})
            resp = read_response(proc)
            assert resp and not resp.get("result", {}).get("isError")
        else:
            log("Skipping Quit: 'Quit' item not found")

        log("\nALL TESTS PASSED!")

    except Exception as e:
        log(f"TEST FAILED: {e}")
        # Print stderr if possible
        stderr = proc.stderr.read(1000)
        if stderr:
             log(f"Server Stderr: {stderr.decode('utf-8')}")
        raise
    finally:
        proc.terminate()
        proc.wait()

if __name__ == "__main__":
    from datetime import datetime
    test_uibridge()
