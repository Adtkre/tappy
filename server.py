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


# ---------------------------------------------------------------------------
# Neumorphic Tkinter GUI
#
# Tkinter has no blur/opacity for canvas shapes, so the "soft shadow" trick is
# faked with two solid rounded-rect duplicates behind the main panel: one
# offset down-right in Van Dyke Brown (dark shadow), one offset up-left in
# Pale Taupe (light shadow). A flat Milk Chocolate panel sits on top. Same
# palette and logic as the phone app, just redrawn with the Tk primitives
# available here.
# ---------------------------------------------------------------------------
ANTIQUE_WHITE = "#F7EBDF"
PALE_TAUPE = "#B7A087"
MILK_CHOCOLATE = "#825A3C"
VAN_DYKE_BROWN = "#5C3E28"   # swap in the exact hex if you have it
ONLINE_GREEN = "#8FBF8F"

FONT_FAMILY = "Segoe UI"     # same font already used in the original file


def _rounded_points(x1, y1, x2, y2, radius):
    r = radius
    return [
        x1 + r, y1,
        x2 - r, y1,
        x2, y1,
        x2, y1 + r,
        x2, y2 - r,
        x2, y2,
        x2 - r, y2,
        x1 + r, y2,
        x1, y2,
        x1, y2 - r,
        x1, y1 + r,
        x1, y1,
    ]


def draw_neu_panel(canvas, x1, y1, x2, y2, radius=18, depth=5, pressed=False):
    """Draws a raised (or, if pressed, recessed) neumorphic panel on a canvas
    and returns nothing — it just paints the shadow + flat surface."""
    if pressed:
        dark_off, light_off = (-depth, -depth), (depth, depth)
    else:
        dark_off, light_off = (depth, depth), (-depth, -depth)

    dx, dy = dark_off
    canvas.create_polygon(
        _rounded_points(x1 + dx, y1 + dy, x2 + dx, y2 + dy, radius),
        smooth=True, fill=VAN_DYKE_BROWN, outline="",
    )
    lx, ly = light_off
    canvas.create_polygon(
        _rounded_points(x1 + lx, y1 + ly, x2 + lx, y2 + ly, radius),
        smooth=True, fill=PALE_TAUPE, outline="",
    )
    canvas.create_polygon(
        _rounded_points(x1, y1, x2, y2, radius),
        smooth=True, fill=MILK_CHOCOLATE, outline="",
    )


class NeuButton:
    """A full-width neumorphic button drawn on its own canvas (not a raw
    tk.Button), so it stays visually anchored to the card instead of floating
    with default OS padding. Presses inward on click, matches the disabled
    state used on the phone app (muted Pale Taupe, no interaction)."""

    def __init__(self, parent, width, height, text, command=None, radius=16, depth=5):
        self.width, self.height = width, height
        self.radius, self.depth = radius, depth
        self.command = command
        self.enabled = command is not None
        self._pressed = False

        self.canvas = tk.Canvas(
            parent, width=width, height=height,
            bg=MILK_CHOCOLATE, highlightthickness=0, bd=0,
        )
        self.canvas.bind("<ButtonPress-1>", self._on_press)
        self.canvas.bind("<ButtonRelease-1>", self._on_release)
        self.set_text(text)

    def pack(self, **kw):
        self.canvas.pack(**kw)

    def set_enabled(self, enabled, command=None):
        self.enabled = enabled
        if command is not None:
            self.command = command
        self._redraw()

    def set_text(self, text):
        self._text = text
        self._redraw()

    def _redraw(self):
        c = self.canvas
        c.delete("all")
        margin = self.depth + 2
        draw_neu_panel(
            c, margin, margin, self.width - margin, self.height - margin,
            radius=self.radius, depth=self.depth, pressed=self._pressed,
        )
        fg = ANTIQUE_WHITE if self.enabled else PALE_TAUPE
        c.create_text(
            self.width / 2, self.height / 2, text=self._text,
            fill=fg, font=(FONT_FAMILY, 12, "bold"),
        )

    def _on_press(self, _event):
        if not self.enabled:
            return
        self._pressed = True
        self._redraw()

    def _on_release(self, event):
        if not self.enabled:
            return
        self._pressed = False
        self._redraw()
        inside = 0 <= event.x <= self.width and 0 <= event.y <= self.height
        if inside and self.command:
            self.command()


def run_gui():
    global connected_client_name
    root = tk.Tk()
    root.title("Tappy")
    icon_path = os.path.join(os.path.dirname(__file__), "logo.ico")
    if os.path.exists(icon_path):
        try:
            root.iconbitmap(icon_path)
        except Exception:
            pass
    root.geometry("340x520")
    root.resizable(False, False)
    root.configure(bg=MILK_CHOCOLATE)

    outer = tk.Frame(root, bg=MILK_CHOCOLATE)
    outer.pack(fill="both", expand=True, padx=22, pady=22)

    # Title
    tk.Label(
        outer, text="Tappy", font=(FONT_FAMILY, 22, "bold"),
        bg=MILK_CHOCOLATE, fg=ANTIQUE_WHITE,
    ).pack(pady=(4, 2))
    tk.Label(
        outer, text="Remote control server", font=(FONT_FAMILY, 10),
        bg=MILK_CHOCOLATE, fg=PALE_TAUPE,
    ).pack(pady=(0, 18))

    # IP pill — recessed panel, like an input field on the phone app
    ip_canvas = tk.Canvas(outer, width=296, height=48, bg=MILK_CHOCOLATE, highlightthickness=0)
    ip_canvas.pack()
    draw_neu_panel(ip_canvas, 6, 6, 290, 42, radius=14, depth=4, pressed=True)
    ip_canvas.create_text(
        148, 24, text=f"IP ADDRESS   {get_local_ip()}",
        fill=PALE_TAUPE, font=(FONT_FAMILY, 10, "bold"),
    )

    tk.Frame(outer, bg=MILK_CHOCOLATE, height=20).pack()

    # Status card — raised panel with a status dot + status text
    status_canvas = tk.Canvas(outer, width=296, height=150, bg=MILK_CHOCOLATE, highlightthickness=0)
    status_canvas.pack()

    disconnect_btn_holder = tk.Frame(outer, bg=MILK_CHOCOLATE)
    disconnect_btn_holder.pack(pady=(20, 0))
    disconnect_btn = NeuButton(
        disconnect_btn_holder, width=296, height=52, text="DISCONNECT", command=None,
    )
    disconnect_btn.pack()

    def do_disconnect():
        global connected_client_name
        with state_lock:
            connected_client_name = None

    def redraw_status(connected_name):
        status_canvas.delete("all")
        draw_neu_panel(status_canvas, 6, 6, 290, 144, radius=20, depth=5)

        dot_color = ONLINE_GREEN if connected_name else PALE_TAUPE
        status_canvas.create_oval(142, 26, 154, 38, fill=dot_color, outline="")

        if connected_name:
            title = "Connected"
            subtitle = connected_name
        else:
            title = "Waiting for phone"
            subtitle = "Open Tappy on your phone\nto connect"

        status_canvas.create_text(
            148, 70, text=title, fill=ANTIQUE_WHITE,
            font=(FONT_FAMILY, 13, "bold"),
        )
        status_canvas.create_text(
            148, 108, text=subtitle, fill=PALE_TAUPE,
            font=(FONT_FAMILY, 9), width=250, justify="center",
        )

    def refresh():
        with state_lock:
            name = connected_client_name
        redraw_status(name)
        disconnect_btn.set_enabled(bool(name), command=do_disconnect if name else None)
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