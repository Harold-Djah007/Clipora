import uuid
from typing import Dict
from app.schemas.download import DownloadJob, DownloadRequest, MediaItem
from app.services.threads_provider import provider
from app.services.session_store import session_store

_jobs: Dict[str, DownloadJob] = {}

async def create_job(user_id: str, req: DownloadRequest) -> DownloadJob:
    job_id = str(uuid.uuid4())
    job = DownloadJob(id=job_id, status="running", items=[])
    _jobs[job_id] = job
    try:
        session = session_store.get(user_id)
        items = []
        for post_url in req.urls:
            post = await provider.resolve(str(post_url), session)
            for idx, media in enumerate(post.media, start=1):
                ext = "mp4" if media.media_type == "video" else "jpg"
                filename = req.filename_template.format(author=post.author, post_id=post.post_id, index=idx) + f".{ext}"
                items.append(MediaItem(
                    media_type=media.media_type,
                    source_url=media.url,
                    filename=filename,
                    caption=post.caption if req.include_caption else None,
                    width=media.width,
                    height=media.height,
                ))
        _jobs[job_id] = DownloadJob(id=job_id, status="completed", items=items)
    except Exception as exc:
        _jobs[job_id] = DownloadJob(id=job_id, status="failed", error=str(exc), items=[])
    return _jobs[job_id]


def get_job(job_id: str):
    return _jobs.get(job_id)
