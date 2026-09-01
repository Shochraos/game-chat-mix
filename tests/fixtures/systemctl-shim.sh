#!/usr/bin/env bash
# systemctl test shim for tests/install.bats: logs every invocation to the
# file named by SHIM_LOG_FILE (absolute path) and succeeds.

printf '%s\n' "$*" >>"$SHIM_LOG_FILE"
exit 0
