from jpsy import pythonify, jsify

from database_layer import RedisPersist
from bl import set_entry


def handler(event, context):
    args_dict = pythonify(event["queryStringParameters"])
    DB = RedisPersist()
    plate = args_dict["plate"]
    parking_lot = args_dict["parking_lot"]
    ticket_id = set_entry(plate=plate, parking_lot=parking_lot, db=DB)

    return jsify(dict(
        ticket_id=ticket_id,
        status="Success"
    ))
