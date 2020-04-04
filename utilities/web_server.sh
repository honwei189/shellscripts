# description: Description comes here....

# Source function library.
. /etc/init.d/functions

start() {
  #/bin/systemctl start httpd.service
  /bin/systemctl start nginx.service
  /bin/systemctl start php-fpm.service
  #/bin/systemctl start hhvm.service
  /bin/systemctl start mysqld.service
}

status() {
  #/bin/systemctl status httpd.service
  /bin/systemctl status nginx.service
  /bin/systemctl status php-fpm.service
  #/bin/systemctl status hhvm.service
  /bin/systemctl status mysqld.service
}

stop() {
  #/bin/systemctl stop httpd.service
  /bin/systemctl stop nginx.service
  /bin/systemctl stop php-fpm.service
  #/bin/systemctl stop hhvm.service
  /bin/systemctl stop mysqld.service
}

restart(){
  #/bin/systemctl restart httpd.service
  /bin/systemctl restart nginx.service
  /bin/systemctl restart php-fpm.service
  #/bin/systemctl restart hhvm.service
  /bin/systemctl restart mysqld.service
}

case "$1" in
    start)
       start
       ;;
    stop)
       stop
       ;;
    restart)
       restart
       ;;
    status)
       status
       ;;
    *)
       echo "Usage: $0 {start|stop|status|restart}"
esac

exit 0
