from flask import Flask, request, jsonify
import pyautogui
import threading
import socket
import time
import tkinter as tk
import os
app = Flask(__name__)

BROADCAST_PORT = 5051
BROADCAST_MSG_PREFIX = "TAPPY_SERVER:"


state_lock = threading.Lock()
connected_client_name = None   


def get_local_ip():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(('8.8.8.8', 80))
        ip = s.getsockname()[0]
    except Exception:
        ip = '127.0.0.1'
    finally:
        s.close()
    return ip


def broadcast_presence():
    """Jab tak app khuli hai, LAN pe apna IP + laptop ka naam broadcast karta rehta hai
    taaki phone 'Nearby Laptops' list mein isse dhoond sake."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    hostname = socket.gethostname()
    while True:
        try:
            ip = get_local_ip()
            message = f"{BROADCAST_MSG_PREFIX}{ip}|{hostname}".encode('utf-8')
            sock.sendto(message, ('<broadcast>', BROADCAST_PORT))
        except Exception as e:
            print("Broadcast error:", e)
        time.sleep(2)



@app.route('/connect', methods=['POST'])
def connect():
    """Phone yahan se session shuru karta hai. Ek time pe sirf ek hi phone connect ho sakta hai."""
    global connected_client_name
    data = request.json or {}
    name = data.get('name', 'Unknown phone')
    with state_lock:
        if connected_client_name is not None and connected_client_name != name:
            return jsonify({'status': 'busy', 'connected_to': connected_client_name}), 409
        connected_client_name = name
    return jsonify({'status': 'connected', 'laptop_name': socket.gethostname()})


@app.route('/disconnect', methods=['POST'])
def disconnect():
    global connected_client_name
    with state_lock:
        connected_client_name = None
    return jsonify({'status': 'disconnected'})


@app.route('/ping', methods=['GET'])
def ping():
    with state_lock:
        connected = connected_client_name
    return jsonify({'status': 'ok', 'name': socket.gethostname(), 'connected_to': connected})


def require_connection():
    with state_lock:
        return connected_client_name is not None


@app.route('/type', methods=['POST'])
def type_text():
    if not require_connection():
        return jsonify({'status': 'not_connected'}), 409
    data = request.json
    text = data.get('text', '')
    pyautogui.write(text)
    return jsonify({'status': 'typed', 'text': text})


@app.route('/move', methods=['POST'])
def move_mouse():
    if not require_connection():
        return jsonify({'status': 'not_connected'}), 409
    data = request.json
    dx = int(data.get('dx', 0))
    dy = int(data.get('dy', 0))
    x, y = pyautogui.position()
    pyautogui.moveTo(x + dx, y + dy)
    return jsonify({'status': 'moved', 'dx': dx, 'dy': dy})


@app.route('/click', methods=['POST'])
def click_mouse():
    if not require_connection():
        return jsonify({'status': 'not_connected'}), 409
    data = request.json
    button = data.get('button', 'left')
    pyautogui.click(button=button)
    return jsonify({'status': 'clicked', 'button': button})


@app.route('/scroll', methods=['POST'])
def scroll_mouse():
    if not require_connection():
        return jsonify({'status': 'not_connected'}), 409
    data = request.json
    amount = int(data.get('amount', 0))
    pyautogui.scroll(amount)
    return jsonify({'status': 'scrolled', 'amount': amount})


def run_flask():
    app.run(host='0.0.0.0', port=5000)




def run_gui():
    root = tk.Tk()
    icon_path = os.path.join(os.path.dirname(__file__), "logo.ico")
    root.title("Tappy")
    root.geometry("320x220")
    root.resizable(False, False)
    root.configure(bg="#DEB7FF")

    tk.Label(root, text="Tappy", font=("Segoe UI", 20, "bold"),
             bg="#DEB7FF").pack(pady=(20, 5))

    ip_label = tk.Label(root, text=f"IP: {get_local_ip()}", font=("Segoe UI", 10),
                         bg="#DEB7FF")
    ip_label.pack()

    status_label = tk.Label(root, text="Waiting for phone to connect...",
                             font=("Segoe UI", 12), bg="#DEB7FF", fg="#555555",
                             wraplength=260, justify="center")
    status_label.pack(pady=20)

    def do_disconnect():
        global connected_client_name
        with state_lock:
            connected_client_name = None

    disconnect_btn = tk.Button(root, text="Disconnect", state=tk.DISABLED,
                                command=do_disconnect, bg="#C296FC", relief="flat",
                                padx=10, pady=6)
    disconnect_btn.pack()

    def refresh():
        with state_lock:
            name = connected_client_name
        if name:
            status_label.config(text=f"Connected to {name}", fg="#1a7f37")
            disconnect_btn.config(state=tk.NORMAL)
        else:
            status_label.config(text="Waiting for phone to connect...", fg="#555555")
            disconnect_btn.config(state=tk.DISABLED)
        root.after(500, refresh)

    def on_close():
        root.destroy()
        os._exit(0)  
   
    root.protocol("WM_DELETE_WINDOW", on_close)
    refresh()
    root.mainloop()


if __name__ == '__main__':
    threading.Thread(target=run_flask, daemon=True).start()
    threading.Thread(target=broadcast_presence, daemon=True).start()
    run_gui()  
