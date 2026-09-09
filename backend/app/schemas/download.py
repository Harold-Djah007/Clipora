from typing import List, Literal, Optional
from pydantic import BaseModel, Field, HttpUrl

MediaType = Literal["video", "image"]

class DownloadRequest(BaseModel):
    urls: List[HttpUrl] = Field(min_length=1, max_length=50)
    prefer_quality: Literal["best", "balanced", "data_saver"] = "best"
    include_caption: bool = True
    filename_template: str = Field(default="{author}_{post_id}_{index}", max_length=120)

class MediaItem(BaseModel):
    media_type: MediaType
    source_url: str
    filename: str
    caption: Optional[str] = None
    width: Optional[int] = None
    height: Optional[int] = None

class DownloadJob(BaseModel):
    id: str
    status: Literal["queued", "running", "completed", "failed"]
    items: List[MediaItem] = Field(default_factory=list)
    error: Optional[str] = None
