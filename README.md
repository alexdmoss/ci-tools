# ci-tools

Docker container for use within CI jobs that contains a bunch of useful tools.

Defaults to build for linux/amd64, but can supply `docker build --build-arg PLATFORM=linux/arm64 .` if desired for local testing.
