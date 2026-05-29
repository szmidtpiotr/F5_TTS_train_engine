FROM nginx:alpine
RUN apk add --no-cache apache2-utils
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY www/ /usr/share/nginx/html/
