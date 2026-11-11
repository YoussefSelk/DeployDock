FROM nginxinc/nginx-unprivileged:stable-alpine@sha256:f5116ed4606f3eb015dd4a8e28cb9b351476dc0ad4bc6e9f93b19cec130cdf03
COPY app/frontend/default.conf /etc/nginx/conf.d/default.conf
COPY app/frontend/index.html app/frontend/app.js app/frontend/style.css /usr/share/nginx/html/
COPY app/frontend/fonts/ /usr/share/nginx/html/fonts/
