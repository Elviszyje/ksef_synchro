from .base import *  # noqa
from decouple import config

DEBUG = False

SECURE_BROWSER_XSS_FILTER = True
SECURE_CONTENT_TYPE_NOSNIFF = True
X_FRAME_OPTIONS = 'DENY'

# Włącz tylko gdy aplikacja działa za HTTPS (np. za reverse proxy z SSL)
HTTPS_ONLY = config('HTTPS_ONLY', default=False, cast=bool)
SESSION_COOKIE_SECURE = HTTPS_ONLY
CSRF_COOKIE_SECURE = HTTPS_ONLY
