#!/usr/bin/env bash
# Forwarder a core/gestor_librerias.sh
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -f "${DIR}/core/gestor_librerias.sh" ]; then
    exec bash "${DIR}/core/gestor_librerias.sh" "$@"
fi
