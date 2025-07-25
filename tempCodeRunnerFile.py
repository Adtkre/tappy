from flask import Flask, request, jsonify
import pyautogui
import threading

app = Flask(__name__)

@app.route('/type', methods=['POST'])
def type_text():
    data = request.json
    text = data.get('text', '')
    pyautogui.write(text)
    return jsonify({'status': 'typed', 'text': text})

@app.route('/move', methods=['POST'])
def move_mouse():
    data = request.json
    dx = int(data.get('dx', 0))
    dy = int(data.get('dy', 0))
    x, y = pyautogui.position()
    pyautogui.moveTo(x + dx, y + dy)
    return jsonify({'status': 'moved', 'dx': dx, 'dy': dy})

@app.route('/click', methods=['POST'])
def click_mouse():
    data = request.json
    button = data.get('button', 'left')
    pyautogui.click(button=button)
    return jsonify({'status': 'clicked', 'button': button})

@app.route('/scroll', methods=['POST'])
def scroll_mouse():
    data = request.json
    amount = int(data.get('amount', 0))
    pyautogui.scroll(amount)
    return jsonify({'status': 'scrolled', 'amount': amount})

def run_server():
    app.run(host='0.0.0.0', port=5000)

if __name__ == '__main__':
    threading.Thread(target=run_server).start()
