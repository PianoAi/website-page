from slowapi import Limiter
from slowapi.util import get_remote_address

# 默认按请求 IP 限速；OTP 接口另用手机号作 key
limiter = Limiter(key_func=get_remote_address, default_limits=[])
