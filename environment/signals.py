class Signal:
    def __init__(self):
        self._listeners = []

    def connect(self, callback):
        self._listeners.append(callback)

    def disconnect(self, callback):
        self._listeners.remove(callback)

    def emit(self, *args, **kwargs):
        for callback in self._listeners:
            callback(*args, **kwargs)