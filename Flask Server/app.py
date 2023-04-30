from flask import Flask, request, abort, Response
from time import sleep, time
from threading import Thread

app = Flask(__name__)

storedData = {}

def clearOldData():
    while True:
        keysToBeRemoved = []

        for name, data in storedData.items():
            if time() - data["time"] > 30:
                keysToBeRemoved.append(name)

        for name in keysToBeRemoved:
            storedData.pop(name)
        
        sleep(5)

Thread(target=clearOldData, daemon=True).start()

@app.route("/", methods=["GET", "POST"])
def webstream():
    if request.method != "POST":
        return "OK", 200

    headers = request.headers

    if "WebStream-Name" not in headers:
        print("Missing name header")

        return "Missing name header", 400

    name = headers["WebStream-Name"]

    if len(name) > 255 or len(name) == 0:
        print("Bad name field")

        return "Bad name field", 400

    data = request.data

    if len(data) == 0:
        if not name in storedData:
            print("Data for requested name does not exist")

            return "Data for requested name does not exist", 400
        else:
            return Response(storedData[name]["data"], content_type='application/octet-stream')
    elif len(data) < 10000000:
        storedData[name] = {
            "data": data,
            "time": time()
        }

        return "Data received!", 200
    else:
        print("Data field too large")

        return "Data field too large", 413


@app.errorhandler(500)
def fatalerror(error):
    return "Something's gone horribly wrong: " + str(error), 500

Thread(target=lambda: app.run(host="0.0.0.0", port=55555)).start()