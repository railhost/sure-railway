# Sure for Railway.
# Builds on the official Sure image, pinned to a release tag. The update
# workflow (.github/workflows/update.yml) bumps SURE_VERSION after a smoke test.
#
# The only addition is docker-entrypoint.sh: it fixes volume ownership, creates
# the first admin from ADMIN_EMAIL and ADMIN_PASSWORD, and runs the web server
# and the Sidekiq worker side by side so both see the same uploads volume.
ARG SURE_VERSION=0.7.6-hotfix.2
FROM ghcr.io/we-promise/sure:${SURE_VERSION}

USER root
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY create-admin.rb /usr/local/share/railway/create-admin.rb
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Railway terminates TLS in front of the app, so Rails assumes SSL but does not
# redirect; Railway's healthcheck calls /up over plain HTTP.
# ONBOARDING_STATE=closed turns off public signup. The admin can open it again
# under Settings → Self-Hosting.
ENV PORT=8080 \
    SELF_HOSTED=true \
    RAILS_FORCE_SSL=false \
    RAILS_ASSUME_SSL=true \
    ONBOARDING_STATE=closed \
    RAILS_LOG_TO_STDOUT=true

EXPOSE 8080
ENTRYPOINT ["docker-entrypoint.sh"]
