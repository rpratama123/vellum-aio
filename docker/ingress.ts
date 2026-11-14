import { readFileSync, writeFileSync } from "node:fs";
import {
  buildIngressNginxConfig, buildRemoteWebIndexHtml, cloudWebHubUrl,
} from "../cli/src/lib/nginx-ingress";

const run = "/run/vellum";
const web = "/opt/vellum/clients/web/dist";
const entry = JSON.parse(readFileSync("/data/home/.vellum.lock.json", "utf8")).assistants[0];
const remote = {
  webDistDir: web,
  indexHtmlPath: `${run}/index.html`,
  assistantId: entry.assistantId,
  assistantName: entry.assistantName,
  hubUrl: cloudWebHubUrl(process.env.VELLUM_ENVIRONMENT),
};
writeFileSync(remote.indexHtmlPath, buildRemoteWebIndexHtml(
  readFileSync(`${web}/index.html`, "utf8"),
  {
    mode: "remote-gateway", apiBaseUrl: "/v1",
    platformDisabled: true, disablePlatform: true,
    assistantId: remote.assistantId, assistantName: remote.assistantName,
    hubUrl: remote.hubUrl,
  },
));
const config = buildIngressNginxConfig({
  gatewayPort: 7830, listenPort: 7840, remoteWebIngress: remote,
});
const listener = "listen 127.0.0.1:7840;";
if (config.split(listener).length !== 2) throw new Error("Unexpected upstream ingress listener.");
writeFileSync(`${run}/nginx.conf`, config.replace(listener, "listen 0.0.0.0:7840;").replace("http {", `http {
  client_body_temp_path ${run}/body;
  proxy_temp_path ${run}/proxy;
  fastcgi_temp_path ${run}/fastcgi;
  uwsgi_temp_path ${run}/uwsgi;
  scgi_temp_path ${run}/scgi;`));
