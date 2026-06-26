{
  "admin": {
    "listen": "unix//var/run/caddy/admin.sock"
  },
  "logging": {
    "logs": {
      "default": { "level": "INFO" },
      "access": {
        "include": ["http.log.access.proxy"],
        "output": "file://__LOG_DIR__/access.log",
        "encoder": { "format": "json_encode" }
      }
    }
  },
  "apps": {
    "http": {
      "servers": {
        "proxy": {
          "listen": [":__BIND_PORT__"],
          "logs": { "default_logger_name": "access" },
          "automatic_https": { "disable": true },
          "routes": [
            {
              "match": [{"path":["/*"]}],
              "handle": [
                __MASQUERADE_HANDLER__
              ],
              "terminal": true
            },
            {
              "match": [{"path":["/*"]}],
              "handle": [
                {
                  "handler": "forward_proxy",
                  "auth_credentials": __USER_CREDS__,
                  "hide_ip": true,
                  "hide_via": true,
                  "probe_resistance": { "hide_ip": true, "hide_via": true }
                }
              ],
              "terminal": true
            }
          ],
          "tls_connection_policies": [
            { "match": { "sni": ["__DOMAIN__"] } }
          ]
        }
      }
    },
    "tls": {
      "certificates": {
        "load_files": [
          {
            "certificate": "__CERT_FILE__",
            "key": "__KEY_FILE__"
          }
        ]
      }
    }
  }
}
