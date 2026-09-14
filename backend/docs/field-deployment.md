# Clipora free field deployment

The repository includes a Render Blueprint at `/render.yaml`. It deploys the resolver from `backend/Dockerfile` on Render's free Frankfurt service, enables HTTPS and health checks, installs FFmpeg, runs as a non-root user, and automatically deploys only after GitHub checks pass.

## One-time setup

1. Open the repository's **Deploy to Render** button and connect the `Harold-Djah007/Clipora` repository if prompted.
2. Accept the Blueprint and wait for the service to become live.
3. Open `https://YOUR-SERVICE.onrender.com/health`. Confirm `ok` is `true` and `version` is `2.0.8`.
4. Open GitHub **Actions → Build field APK → Run workflow**.
5. Enter the service's full HTTPS URL without `/health`, download the resulting `clipora-field-apk` artifact, and install `app-release.apk`.

The workflow rejects localhost and non-HTTPS resolver addresses. The URL is compiled into Flutter and Android's native instant-share service, so the field phone does not require Settings changes, ADB, or a computer.

## Free-tier behavior

Render's free web service sleeps after 15 minutes without incoming traffic. Clipora's Android background worker retries transient connection and HTTP failures for up to 90 seconds while the notification says that the resolver is waking. The share receiver still closes immediately, allowing the user to return to the social app.

The free tier can also be suspended for monthly usage or unusually high outbound traffic. Upgrade the Render service when continuous instant downloads or broader distribution is required.

## Distribution boundary

The generated field APK is release-mode but uses the repository's current debug signing fallback. It is suitable for direct field evaluation. Configure and securely retain a production keystore before Play Store submission or long-term distribution, because Android upgrades must use the same signing identity.
