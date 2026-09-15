from fastapi import FastAPI
from app.api.routes import router
from app.core.version import API_SERVICE_NAME, API_VERSION
from app.services.session_config import session_status

app = FastAPI(
    title="Clipora Resolver API",
    version=API_VERSION,
    description="Resolver API for supported public social-media links.",
)
app.include_router(router, prefix="/api")


@app.get("/")
def root():
    return {
        "ok": True,
        "service": API_SERVICE_NAME,
        "version": API_VERSION,
        "health": "/health",
        "docs": "/docs",
        "platform_session": session_status(),
    }


@app.get("/health")
def health():
    return {"ok": True, "service": API_SERVICE_NAME, "version": API_VERSION, **session_status()}
