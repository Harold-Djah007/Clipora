import uuid
from typing import Dict

from app.schemas.download import DownloadJob, DownloadRequest, MediaItem
from app.services.platforms import safe_filename_part
from app.services.resolver_errors import public_resolver_error
from app.services.universal_provider import universal_provider

_jobs: Dict[str, DownloadJob] = {}


def _extension_for(media_type: str) -> str:
    if media_type == "video":
        return "mp4"
    if media_type == "audio":
        return "m4a"
    return "jpg"


async def create_job(user_id: str, req: DownloadRequest) -> DownloadJob:
    job_id = str(uuid.uuid4())
    job = DownloadJob(id=job_id, status="running", items=[])
    _jobs[job_id] = job
    try:
        items = []
        for post_url in req.urls:
            post = await universal_provider.resolve(str(post_url))
            author = safe_filename_part(post.author, "clipora")
            post_id = safe_filename_part(post.post_id, "media")
            for idx, media in enumerate(post.media, start=1):
                ext = _extension_for(media.media_type)
                filename = req.filename_template.format(
                    author=author,
                    post_id=post_id,
                    index=idx,
                    platform=post.platform,
                ) + f".{ext}"
                items.append(MediaItem(
                    media_type=media.media_type,
                    source_url=media.url,
                    filename=filename,
                    caption=post.caption if req.include_caption else None,
                    width=media.width,
                    height=media.height,
                    platform=post.platform,
                    source_page_url=post.source_url,
                    filesize=media.filesize,
                    quality=media.quality,
                ))
        _jobs[job_id] = DownloadJob(id=job_id, status="completed", items=items)
    except Exception as exc:
        _jobs[job_id] = DownloadJob(id=job_id, status="failed", error=public_resolver_error(exc), items=[])
    return _jobs[job_id]


def get_job(job_id: str):
    return _jobs.get(job_id)
