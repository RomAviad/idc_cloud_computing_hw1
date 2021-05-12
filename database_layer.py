import json
import os

from redis import StrictRedis


REDIS_HOST = os.environ.get("REDIS_HOST", "localhost")
REDIS_PORT = int(os.environ.get("REDIS_PORT", 6379))


def get_redis_instance(host=REDIS_HOST, port=REDIS_PORT):
    return StrictRedis(host=host, port=port)


class RedisPersist(object):

    def __init__(self, redis_connection=None):
        self.redis: StrictRedis = redis_connection or get_redis_instance()

    def __getitem__(self, item):
        redis_item = self.redis.get(name=item)
        redis_item = json.loads(redis_item) if redis_item is not None else redis_item
        return redis_item

    def __setitem__(self, key, value):
        self.redis.set(
            name=key,
            value=json.dumps(value)
        )

    def get(self, item, default_value=None):
        db_item = self.__getitem__(item)
        return db_item if db_item is not None else default_value
