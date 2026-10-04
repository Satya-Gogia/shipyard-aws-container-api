from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health():
    assert client.get("/health").json() == {"status": "ok"}


def test_task_lifecycle():
    r = client.post("/tasks", json={"title": "deploy to ECS"})
    assert r.status_code == 201
    tid = r.json()["id"]

    assert client.get(f"/tasks/{tid}").json()["title"] == "deploy to ECS"

    r = client.put(f"/tasks/{tid}", json={"title": "deploy to ECS", "done": True})
    assert r.json()["done"] is True

    assert client.delete(f"/tasks/{tid}").status_code == 204
    assert client.get(f"/tasks/{tid}").status_code == 404


def test_validation():
    assert client.post("/tasks", json={"title": ""}).status_code == 422
