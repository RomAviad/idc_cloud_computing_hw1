import datetime
import math


QUARTER_HOUR_SECONDS = 15 * 60


def set_entry(plate, parking_lot, db):
    now = datetime.datetime.utcnow()
    ticket_id = f"{plate}__{parking_lot}__{now.timestamp()}"
    ticket_data = dict(
        ticket_id=ticket_id,
        plate=plate,
        parking_lot=parking_lot,
        start_date=now.timestamp()
    )
    db[ticket_id] = ticket_data
    return ticket_id


def get_ticket_data(ticket_id, db):
    now = datetime.datetime.utcnow()
    ticket_data = db.get(ticket_id, {})
    ticket_data["start_date"] = datetime.datetime.fromtimestamp(ticket_data["start_date"])
    is_valid = len(ticket_data) > 0
    result = {"is_valid": is_valid}
    if is_valid:
        seconds_elapsed = (now - ticket_data["start_date"]).seconds
        num_quarter_hours = seconds_elapsed / QUARTER_HOUR_SECONDS
        ticket_data["to_pay"] = math.ceil(num_quarter_hours) * 2.5
        result["data"] = ticket_data
    return result
