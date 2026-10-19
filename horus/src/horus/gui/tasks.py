"""Tarefas em segundo plano com progresso para a interface.

O Horos usa NSThread + ThreadsManager e mostra as tarefas na janela de
atividade. Aqui um QThreadPool executa a função e os sinais trazem
progresso e resultado de volta à thread da interface.
"""

from __future__ import annotations

import traceback
from typing import Any, Callable

from PySide6.QtCore import QObject, QRunnable, QThreadPool, Signal


class TaskSignals(QObject):
    progress = Signal(str, int, int)
    finished = Signal(object)
    failed = Signal(str)


class Task(QRunnable):
    def __init__(self, fn: Callable[..., Any], *args: Any, **kwargs: Any):
        super().__init__()
        self.fn = fn
        self.args = args
        self.kwargs = kwargs
        self.signals = TaskSignals()
        self.cancel_requested = False

    def cancelled(self) -> bool:
        return self.cancel_requested

    def report(self, message: str, done: int = 0, total: int = 0) -> None:
        self.signals.progress.emit(message, int(done), int(total))

    def run(self) -> None:
        try:
            result = self.fn(self, *self.args, **self.kwargs)
        except Exception as exc:  # devolvido à interface, que mostra ao usuário
            detail = "".join(traceback.format_exception_only(type(exc), exc)).strip()
            self.signals.failed.emit(str(exc) or detail)
            return
        self.signals.finished.emit(result)


class TaskRunner:
    """Mantém as tarefas vivas até terminarem (o pool não guarda os sinais)."""

    def __init__(self) -> None:
        self.pool = QThreadPool.globalInstance()
        self._alive: set[Task] = set()

    def start(
        self,
        fn: Callable[..., Any],
        *args: Any,
        on_done: Callable[[Any], None] | None = None,
        on_error: Callable[[str], None] | None = None,
        on_progress: Callable[[str, int, int], None] | None = None,
        **kwargs: Any,
    ) -> Task:
        task = Task(fn, *args, **kwargs)
        task.setAutoDelete(False)
        self._alive.add(task)

        def finish(result: Any) -> None:
            self._alive.discard(task)
            if on_done:
                on_done(result)

        def fail(message: str) -> None:
            self._alive.discard(task)
            if on_error:
                on_error(message)

        task.signals.finished.connect(finish)
        task.signals.failed.connect(fail)
        if on_progress:
            task.signals.progress.connect(on_progress)
        self.pool.start(task)
        return task

    def wait(self, msecs: int = -1) -> bool:
        return self.pool.waitForDone(msecs)
