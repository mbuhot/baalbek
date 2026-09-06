import Config

# `billing` is a pure domain/data library at this stage (PLAN.md Stage 3) —
# no release, no HTTP surface. This file exists only so `import_config
# "#{config_env()}.exs"` in config.exs has somewhere to land if MIX_ENV=prod
# is ever used before `server` (Stage 6) assembles a real release.
