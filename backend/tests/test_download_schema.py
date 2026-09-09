from app.schemas.download import MediaItem


def test_media_item_allows_universal_metadata():
    item = MediaItem(
        media_type="video",
        source_url="https://cdn.example/video.mp4",
        filename="x_creator_123_1.mp4",
        platform="x",
        source_page_url="https://x.com/user/status/123",
        filesize=12345,
        quality="720p",
    )

    assert item.platform == "x"
    assert item.quality == "720p"
    assert item.filename.endswith(".mp4")
