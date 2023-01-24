swagger: '2.0'
info:
  version: 1.0.7
  title: ${title}
  description: ${description}
host: "${domain_name}"
x-google-endpoints:
  - name: "${domain_name}"
    target: "${ip_address}"

schemes:
  - "https"
  - "http"
paths:
  /info:
    get:
      description: "System information"
      operationId: "info"
      security: []
      responses:
        200:
          description: OK
