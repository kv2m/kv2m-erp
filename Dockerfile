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

# Diretório precisa se chamar `erpnext`: hooks.py declara app_name = erpnext
# e o bench clona/copia usando o nome da pasta de origem.
COPY --chown=frappe:frappe . /tmp/erpnext

# CACHE_BUST invalida esta camada quando o commit muda (o COPY já faz isso
# para o fonte; o arg cobre rebuilds em que só o frappe/payments avançou).
RUN : "${CACHE_BUST}" && \
    bench init \
      --frappe-branch="${FRAPPE_BRANCH}" \
      --frappe-path="${FRAPPE_PATH}" \
      --no-procfile \
      --no-backups \
      --skip-redis-config-generation \
      --verbose \
      /home/frappe/frappe-bench && \
    cd /home/frappe/frappe-bench && \
    bench get-app --resolve-deps /tmp/erpnext && \
    echo "{}" > sites/common_site_config.json && \
    find apps -mindepth 1 -path "*/.git" | xargs rm -fr && \
    rm -rf /tmp/erpnext

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
