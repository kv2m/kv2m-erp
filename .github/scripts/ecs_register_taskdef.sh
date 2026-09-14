#!/usr/bin/env bash
#
# Registra uma nova revisão de task definition partindo da ÚLTIMA revisão
# ativa da família, trocando só a imagem dos containers Frappe.
#
# Aceita a imagem atual em dois formatos, para o primeiro deploy (Docker Hub
# → ECR) e os seguintes (ECR → ECR com tag nova):
#   - frappe/erpnext:<qualquer-tag>
#   - <repo_uri>:<qualquer-tag>
#
# Uso:
#   ecs_register_taskdef.sh <familia> <repo_uri>=<tag>
#
# Imprime no stdout o ARN da revisão registrada.
set -euo pipefail

FAMILY="${1:?familia da task definition obrigatoria}"
PAIR="${2:?par <repo_uri>=<tag> obrigatorio}"

repo="${PAIR%%=*}"
tag="${PAIR#*=}"
[ "$repo" != "$PAIR" ] || { echo "par invalido: $PAIR (esperado <repo_uri>=<tag>)" >&2; exit 1; }

current=$(aws ecs describe-task-definition --task-definition "$FAMILY" \
  --query taskDefinition --output json)

next=$(printf '%s' "$current" | jq '
  del(.taskDefinitionArn, .revision, .status, .requiresAttributes,
      .compatibilities, .registeredAt, .registeredBy, .deregisteredAt)')

before=$(printf '%s' "$next" | jq --arg repo "$repo" '
  [.containerDefinitions[]
    | select((.image | startswith("frappe/erpnext:"))
          or (.image | startswith($repo + ":")))]
  | length')
if [ "$before" -eq 0 ]; then
  echo "nenhum container Frappe (frappe/erpnext ou $repo) na familia $FAMILY" >&2
  exit 1
fi

next=$(printf '%s' "$next" | jq --arg repo "$repo" --arg tag "$tag" '
  .containerDefinitions |= map(
    if (.image | startswith("frappe/erpnext:"))
       or (.image | startswith($repo + ":"))
    then .image = $repo + ":" + $tag
    else .
    end
  )')

aws ecs register-task-definition --cli-input-json "$next" \
  --query 'taskDefinition.taskDefinitionArn' --output text
