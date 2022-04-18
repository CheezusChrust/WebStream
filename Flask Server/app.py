from flask import Flask, request, abort
import time

app = Flask(__name__)

storedData = {}

@app.route('/webstream', methods=['GET', 'POST'])
def webstream():
    if request.method != 'POST':
        print("Request method not POST")
        abort(400)

    form = request.form

    keysToBeRemoved = []
    for name, data in storedData.items():
        if time.time() - data['time'] > 30:
            keysToBeRemoved.append(name)

    for name in keysToBeRemoved:
        storedData.pop(name)

    if not 'name' in form:
        print("Missing name field")
        return "Missing name field", 400

    name = form['name']

    if len(name) > 50 or len(name) == 0:
        print("Bad name field")
        return "Bad name field", 400

    if 'data' in form:
        data = form['data']

        if len(data) == 0:
            print("Emtpy data field")
            return "Received empty data field"

        if len(data) > 500000:
            print("Data field too large")
            return "Data field too large", 413

        storedData[name] = {
            'data': data,
            'time': time.time()
        }

        return "Data received!"
    else:
        if not name in storedData:
            print("Data for requested name does not exist")
            return "Data for requested name does not exist", 400

        return storedData[name]['data']


@app.errorhandler(500)
def fatalerror(error):
    return "Something's gone horribly wrong with Cheezus' bad code: " + str(error), 500
