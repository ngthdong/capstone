import os
import logging
from contextlib import contextmanager
from typing import Optional
from fastapi.staticfiles import StaticFiles

import psycopg2
import psycopg2.extras
from fastapi import FastAPI, HTTPException, status
from pydantic import BaseModel, Field
from dotenv import load_dotenv

# Configuration: read from environment variables (systemd's EnvironmentFile
# will set these variables). load_dotenv() is only useful when running locally
# with a .env file and has no effect under systemd (EnvironmentFile loads
# variables directly into the environment).
load_dotenv()

DB_HOST = os.environ.get("DB_HOST", "127.0.0.1")
DB_PORT = os.environ.get("DB_PORT", "5432")
DB_NAME = os.environ.get("DB_NAME", "tododb")
DB_USER = os.environ.get("DB_USER", "todo_app")
DB_PASSWORD = os.environ.get("DB_PASSWORD")

if not DB_PASSWORD:
    # Do not fall back to a default password -> fail early and clearly.
    raise RuntimeError(
        "DB_PASSWORD chưa được set. Kiểm tra EnvironmentFile của systemd unit."
    )

# Logging -> send logs to stdout so that journald can capture them.
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger("todoapp")

app = FastAPI(title="TodoList API", version="1.0.0")
app.mount("/", StaticFiles(directory="static", html=True), name="static")

# Connect database
@contextmanager
def get_conn():
    conn = psycopg2.connect(
        host=DB_HOST,
        port=DB_PORT,
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD,
        connect_timeout=5,
    )
    try:
        yield conn
    finally:
        conn.close()


def init_db():
    """Create the todos table if it does not exist. Called when the app starts."""
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                CREATE TABLE IF NOT EXISTS todos (
                    id SERIAL PRIMARY KEY,
                    title TEXT NOT NULL,
                    done BOOLEAN NOT NULL DEFAULT FALSE,
                    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
                );
                """
            )
        conn.commit()
    logger.info("Checked/initialized the todos table.")


@app.on_event("startup")
def on_startup():
    logger.info("TodoList application is starting...")
    init_db()
    logger.info("Startup completed.")


# Schemas
class TodoIn(BaseModel):
    title: str = Field(..., min_length=1, max_length=255)


class TodoOut(BaseModel):
    id: int
    title: str
    done: bool
    created_at: str


# Endpoints
@app.get("/health")
def health():
    """Used by the health-check script to verify that the app is alive
    and the database connection is still working."""
    try:
        with get_conn() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT 1;")
        return {"status": "ok"}
    except Exception as exc:
        logger.error("Health check failed: %s", exc)
        raise HTTPException(status_code=503, detail="Cannot connect to the database")


@app.get("/api/todos", response_model=list[TodoOut])
def list_todos():
    with get_conn() as conn:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute(
                "SELECT id, title, done, created_at FROM todos ORDER BY id;"
            )
            rows = cur.fetchall()
    logger.info("Retrieved todo list (%d records)", len(rows))
    return [
        TodoOut(
            id=r["id"],
            title=r["title"],
            done=r["done"],
            created_at=r["created_at"].isoformat(),
        )
        for r in rows
    ]


@app.post("/api/todos", response_model=TodoOut, status_code=status.HTTP_201_CREATED)
def create_todo(todo: TodoIn):
    with get_conn() as conn:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute(
                "INSERT INTO todos (title) VALUES (%s) "
                "RETURNING id, title, done, created_at;",
                (todo.title,),
            )
            row = cur.fetchone()
        conn.commit()
    logger.info("Inserted todo id=%s title=%r", row["id"], row["title"])
    return TodoOut(
        id=row["id"],
        title=row["title"],
        done=row["done"],
        created_at=row["created_at"].isoformat(),
    )


@app.delete("/api/todos/{todo_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_todo(todo_id: int):
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM todos WHERE id = %s;", (todo_id,))
            deleted = cur.rowcount
        conn.commit()
    if deleted == 0:
        logger.warning("Delete dailed: todo not found id=%s", todo_id)
        raise HTTPException(status_code=404, detail="Task not found")
    logger.info("Deleted todo id=%s", todo_id)
    return None