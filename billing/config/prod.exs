import Config

# `billing` is a pure domain library: no release, no HTTP surface. This file
# exists only so config.exs's `import_config "#{config_env()}.exs"` has
# somewhere to land under MIX_ENV=prod.
