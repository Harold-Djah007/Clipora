from fastapi import APIRouter, Header, HTTPException
from pydantic import BaseModel, Field
from app.schemas.download import DownloadRequest
from app.services.download_service import create_job, get_job
from app.services.session_store import session_store
from app.services.threads_provider import provider
from app.services.universal_provider import universal_provider

router = APIRouter()

class SessionConnect(BaseModel):
    session_blob: str = Field(min_length=1, max_length=32768)
    ttl_minutes: int = Field(default=60, ge=5, le=10080)

class ResolveRequest(BaseModel):
    url: str

@router.get("/health")
def health():
    return {"ok": True, "service": "clipora", "version": "0.8.4-universal-foundation"}

@router.post("/session/connect")
def connect_session(body: SessionConnect, x_user_id: str = Header(default="local-user")):
    session_store.put(x_user_id, body.session_blob, body.ttl_minutes)
    return {"connected": True, "ttl_minutes": body.ttl_minutes}

@router.get("/session/status")
def session_status(x_user_id: str = Header(default="local-user")):
    return {"connected": session_store.get(x_user_id) is not None}

@router.post("/session/disconnect")
def disconnect_session(x_user_id: str = Header(default="local-user")):
    session_store.delete(x_user_id)
    return {"connected": False, "deleted": True}

@router.post("/detect")
async def detect_platform(body: ResolveRequest):
    try:
        return await universal_provider.detect(body.url)
    except Exception as exc:
        raise HTTPException(422, str(exc)) from exc

@router.post("/resolve")
async def resolve(body: ResolveRequest, x_user_id: str = Header(default="local-user")):
    """Legacy Threads resolver kept for compatibility with the existing app/tests."""
    try:
        post = await provider.resolve(body.url, session_store.get(x_user_id))
        return post
    except Exception as exc:
        raise HTTPException(422, str(exc)) from exc

@router.post("/resolve/universal")
async def resolve_universal(body: ResolveRequest, x_user_id: str = Header(default="local-user")):
    try:
        return await universal_provider.resolve(body.url, session_store.get(x_user_id))
    except Exception as exc:
        raise HTTPException(422, str(exc)) from exc

@router.post("/downloads")
async def downloads(body: DownloadRequest, x_user_id: str = Header(default="local-user")):
    return await create_job(x_user_id, body)

@router.get("/downloads/{job_id}")
def download_status(job_id: str):
    job = get_job(job_id)
    if not job:
        raise HTTPException(404, "Download job not found")
    return job
