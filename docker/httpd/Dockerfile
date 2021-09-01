FROM amazonlinux

RUN yum -y update && yum -y install httpd

COPY ./httpd.conf /etc/httpd/conf/httpd.conf

CMD ["/usr/sbin/httpd","-D","FOREGROUND"]

EXPOSE 82

#docker run -d -p 8787:80 -v /tmp/web:/web nginx7