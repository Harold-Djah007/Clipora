from fastapi import FastAPI
from app.api.routes import router

app = FastAPI(
    title="ThreadVault API",
    version="0.6.0",
    description="Optional resolver API for public and explicitly authorized Threads media.",
)
app.include_router(router, prefix="/api")

@app.get("/health")
def health():
    return {"ok": True, "service": "threadvault", "version": "0.6.0"}
