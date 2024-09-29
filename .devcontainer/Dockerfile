# [Choice] Ruby version (use -bullseye variants on local arm64/Apple Silicon): 3, 3.3, 3.2, 3.1, 3-bookworm, 3.3-bookworm, 3.2-bookworm, 3.1-bookworm, 3-bullseye, 3.3-bullseye, 3.2-bullseye, 3.1-bullseye, 3-buster, 3.2-buster 3.1-buster
ARG VARIANT=2.6
FROM ruby:${VARIANT}

RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    # Remove imagemagick due to https://security-tracker.debian.org/tracker/CVE-2019-10131
    && apt-get purge -y imagemagick imagemagick-6-common 
