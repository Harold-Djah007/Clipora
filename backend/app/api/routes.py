from fastapi import APIRouter, Header, HTTPException
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field
from app.core.version import API_SERVICE_NAME, API_VERSION
from app.schemas.download import DownloadRequest
from app.services.download_service import create_job, get_job
from app.services.file_cache import media_file_cache
from app.services.threads_provider import provider
from app.services.universal_provider import universal_provider
from app.services.resolver_errors import public_resolver_error

router = APIRouter()

class ResolveRequest(BaseModel):
    url: str = Field(min_length=8, max_length=4096)

@router.get("/health")
def health():
    return {"ok": True, "service": API_SERVICE_NAME, "version": API_VERSION}

@router.post("/detect")
async def detect_platform(body: ResolveRequest):
    try:
        return await universal_provider.detect(body.url)
    except Exception as exc:
        raise HTTPException(422, public_resolver_error(exc)) from exc

@router.post("/resolve")
async def resolve(body: ResolveRequest):
    """Legacy Threads resolver kept for compatibility with the existing app/tests."""
    try:
        post = await provider.resolve(body.url)
        return post
    except Exception as exc:
        raise HTTPException(422, public_resolver_error(exc)) from exc

@router.post("/resolve/universal")
async def resolve_universal(body: ResolveRequest):
    try:
        return await universal_provider.resolve(body.url)
    except Exception as exc:
        raise HTTPException(422, public_resolver_error(exc)) from exc


@router.get("/files/{token}")
def get_resolved_file(token: str):
    path = media_file_cache.get(token)
    if path is None:
        raise HTTPException(404, "Resolved file expired. Save the link again.")
    media_type = "video/mp4" if path.suffix.lower() == ".mp4" else None
    return FileResponse(path, filename=path.name, media_type=media_type)


@router.post("/downloads")
async def downloads(body: DownloadRequest, x_user_id: str = Header(default="local-user")):
    return await create_job(x_user_id, body)

@router.get("/downloads/{job_id}")
def download_status(job_id: str):
    job = get_job(job_id)
    if not job:
        raise HTTPException(404, "Download job not found")
    return job
