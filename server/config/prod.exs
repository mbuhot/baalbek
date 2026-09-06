import Config

# No release/deployment story yet (out of scope for this stage — PLAN.md
# Stage 6 is HTTP surface + OpenAPI generation, not deployment). This file
# exists so `import_config "#{config_env()}.exs"` in config.exs has
# somewhere to land if MIX_ENV=prod is ever used.
