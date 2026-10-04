"""Small task API used to demonstrate container deployment on AWS."""
import os
import socket
from datetime import datetime, timezone
from itertools import count

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

app = FastAPI(title="Task API", version=os.getenv("APP_VERSION", "1.0.0"))

_tasks: dict[int, dict] = {}
_ids = count(1)


class TaskIn(BaseModel):
    title: str = Field(min_length=1, max_length=120)
    done: bool = False


@app.get("/health")
def health():
    """Used by ECS / ALB / Docker HEALTHCHECK."""
    return {"status": "ok"}


@app.get("/info")
def info():
    """Shows which container served the request (handy to prove it's running on AWS)."""
    return {
        "hostname": socket.gethostname(),
        "version": app.version,
        "time": datetime.now(timezone.utc).isoformat(),
    }


@app.post("/tasks", status_code=201)
def create_task(task: TaskIn):
    task_id = next(_ids)
    _tasks[task_id] = {"id": task_id, **task.model_dump()}
    return _tasks[task_id]


@app.get("/tasks")
def list_tasks():
    return list(_tasks.values())


@app.get("/tasks/{task_id}")
def get_task(task_id: int):
    if task_id not in _tasks:
        raise HTTPException(404, "Task not found")
    return _tasks[task_id]


@app.put("/tasks/{task_id}")
def update_task(task_id: int, task: TaskIn):
    if task_id not in _tasks:
        raise HTTPException(404, "Task not found")
    _tasks[task_id] = {"id": task_id, **task.model_dump()}
    return _tasks[task_id]


@app.delete("/tasks/{task_id}", status_code=204)
def delete_task(task_id: int):
    if _tasks.pop(task_id, None) is None:
        raise HTTPException(404, "Task not found")
