Build one or more AgentCore Docker images.

Usage: /build [image]

Where [image] is one of: minimal, ubuntu, kali, all

If no argument is given, build the minimal image.

Build commands:
- minimal: `docker build -f dockerfiles/Dockerfile.minimal -t agentcore:minimal .`
- ubuntu: `docker build -f dockerfiles/Dockerfile.ubuntu -t agentcore:ubuntu .`
- kali: `docker build -f dockerfiles/Dockerfile.kali -t agentcore:kali .`
- all: build all three in sequence

Run the build from the project root directory. Report the build result (success/failure, image size via `docker images agentcore`).

If the build fails, read the relevant Dockerfile and the failing base/ install script, diagnose the issue, and suggest a fix.
