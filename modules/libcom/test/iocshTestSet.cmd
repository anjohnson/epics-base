# set should create a local macro, NOT an environment variable
set "LOCAL_ONLY" "my_value"
epicsEnvSet "captured_set" "$(LOCAL_ONLY)"
