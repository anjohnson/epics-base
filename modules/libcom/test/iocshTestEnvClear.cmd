# Set a local macro, then epicsEnvSet with same name.
# epicsEnvSet calls iocshEnvClear, removing the local macro,
# so the env var value is visible to subsequent macro expansions.
set "CLASH_VAR" "local_val"
epicsEnvSet "CLASH_VAR" "env_val"
epicsEnvSet "captured_clash" "$(CLASH_VAR)"
