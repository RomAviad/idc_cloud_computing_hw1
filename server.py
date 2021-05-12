import os


from flask import Flask, request, jsonify
from jpsy import jsify, pythonify

from bl import set_entry, get_ticket_data
from database_layer import RedisPersist, StrictRedis

app = Flask(__name__)

REDIS_HOST = os.environ.get("REDIS_HOST", "localhost")
DB = RedisPersist(StrictRedis(host=REDIS_HOST))

HOURLY_RATE = 10.

@app.route("/")
def health():
    return "I'm Alive!"


@app.route("/entry", methods=["POST"])
def entry():
    args_dict = pythonify(request.args)
    plate = args_dict.get("plate")
    parking_lot = args_dict.get("parking_lot")

    if not plate or not parking_lot:
        result = {"status": "Error",
                  "reason": "Missing entry parameters. required parameters are 'plate' and 'parkingLot'"}
        result_code = 400
    else:
        ticket_id = set_entry(plate=plate, parking_lot=parking_lot, db=DB)
        result = {"status": "Success", "ticket_id": ticket_id}
        print("Persisting...")
        result = jsify(result)
        result_code = 201
    return jsonify(result), result_code


@app.route("/exit", methods=["POST"])
def exit_handler():
    args_dict = pythonify(request.args)
    ticket_id = args_dict.get("ticket_id")
    print("checking ticket validity")
    ticket_data = get_ticket_data(ticket_id=ticket_id, db=DB)
    is_valid_ticket = ticket_data.get("is_valid", True)
    if not is_valid_ticket:
        result = {"status": "Error", "reason": "Invalid ticket"}
        result_code = 500
    else:
        result = ticket_data["data"]
        result_code = 200
        result = jsify(result)
    return jsonify(result), result_code


if __name__ == "__main__":
    app.run("0.0.0.0", debug=False)
