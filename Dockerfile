# syntax=docker/dockerfile:1
#
# Imagem de produção do fork kv2m-erp (app_name = erpnext).
# Mesmo contrato da imagem oficial frappe/erpnext: gunicorn, nginx-entrypoint,
# workers e scheduler — para caber na task ECS kv2m-erpnext-poc.
#
# Este repo é o ERPNext (não um custom app). É copiado para apps/erpnext
# para o diretório não herdar o nome GitHub kv2m-erp.
#
# Build (arm64, o cluster é Graviton):
#   docker buildx build --platform linux/arm64 \
#     --build-arg FRAPPE_BRANCH=develop \
#     --build-arg CACHE_BUST=$(git rev-parse HEAD) \
#     -t 537968013910.dkr.ecr.us-east-1.amazonaws.com/kv2m-erpnext-poc:local .

ARG FRAPPE_BRANCH=develop
ARG FRAPPE_IMAGE_PREFIX=frappe

FROM ${FRAPPE_IMAGE_PREFIX}/build:${FRAPPE_BRANCH} AS builder

ARG FRAPPE_BRANCH=develop
ARG FRAPPE_PATH=https://github.com/frappe/frappe
ARG CACHE_BUST=""

USER frappe

# bench init é a camada cara e estável (frappe). O COPY do fork fica DEPOIS
# para não invalidar esse cache a cada commit.
RUN bench init \
      --frappe-branch="${FRAPPE_BRANCH}" \
      --frappe-path="${FRAPPE_PATH}" \
      --no-procfile \
      --no-backups \
      --skip-redis-config-generation \
      --verbose \
      /home/frappe/frappe-bench

# hooks.py declara app_name = erpnext; a pasta precisa ter esse nome.
COPY --chown=frappe:frappe . /tmp/erpnext

# get-app --resolve-deps em path local (sem .git) estoura
# `'App' object has no attribute 'org'`. Copiamos o tree e puxamos
# payments — dependência de runtime do ERPNext — direto do GitHub.
RUN : "${CACHE_BUST}" && \
    cd /home/frappe/frappe-bench && \
    cp -a /tmp/erpnext apps/erpnext && \
    rm -rf /tmp/erpnext && \
    ./env/bin/pip install --quiet -e apps/erpnext && \
    grep -qx erpnext sites/apps.txt || echo erpnext >> sites/apps.txt && \
    bench get-app --branch="${FRAPPE_BRANCH}" --skip-assets payments && \
    bench setup requirements && \
    bench build --production && \
    echo "{}" > sites/common_site_config.json && \
    find apps -mindepth 1 -path "*/.git" | xargs rm -fr

FROM ${FRAPPE_IMAGE_PREFIX}/base:${FRAPPE_BRANCH} AS backend

USER frappe

COPY --from=builder --chown=frappe:frappe /home/frappe/frappe-bench /home/frappe/frappe-bench

WORKDIR /home/frappe/frappe-bench

RUN cp -r /home/frappe/frappe-bench/sites/assets /home/frappe/frappe-bench/assets && \
    rm -rf /home/frappe/frappe-bench/sites/assets

VOLUME [ \
  "/home/frappe/frappe-bench/sites", \
  "/home/frappe/frappe-bench/logs" \
]

USER root
COPY docker/main-entrypoint.sh /usr/local/bin/entrypoint.sh
COPY docker/start.sh /usr/local/bin/start.sh
RUN chmod 755 /usr/local/bin/entrypoint.sh /usr/local/bin/start.sh

USER frappe
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["start.sh"]
