// Deploy-time configuration: which API this copy of the app talks to.
//
// Empty means "the origin serving this app", which is right wherever a proxy
// puts the API on that origin — see web/Dockerfile. A packaged Capacitor app
// has no such origin and gets this file rewritten during its build, by
// mobile/scripts/stamp-api-config.sh.
globalThis.__API_BASE_URL__ = "";
