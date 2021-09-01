FROM amazonlinux

RUN amazon-linux-extras enable nginx1
RUN yum -y update && yum -y install nginx

COPY ./nginx.conf /etc/nginx/nginx.conf

CMD ["nginx","-g","daemon off;"]

EXPOSE 81

#docker run -d -p 8787:80 -v /tmp/web:/web nginx7