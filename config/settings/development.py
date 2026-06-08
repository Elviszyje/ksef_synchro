from .base import *  # noqa

DEBUG = True

INSTALLED_APPS += ['debug_toolbar']  # noqa
MIDDLEWARE += ['debug_toolbar.middleware.DebugToolbarMiddleware']  # noqa

INTERNAL_IPS = ['127.0.0.1']

DATABASES['default']['HOST'] = 'localhost'  # noqa

CELERY_TASK_ALWAYS_EAGER = True

CORS_ALLOW_ALL_ORIGINS = True
