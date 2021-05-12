from jpsy import pythonify, jsify

from database_layer import RedisPersist
from bl import get_ticket_data


def handler(event, context):
    DB = RedisPersist()
    args_dict = pythonify(event["queryStringParameters"])
    ticket_id = args_dict.get("ticket_id")
    print("checking ticket validity")
    ticket_data = get_ticket_data(ticket_id=ticket_id, db=DB)
    is_valid_ticket = ticket_data.get("is_valid", True)
    if not is_valid_ticket:
        result = {"status": "Error", "reason": "Invalid ticket"}
    else:
        result = ticket_data["data"]
        result["start_date"] = str(result["start_date"])
        result = jsify(result)
    return result
