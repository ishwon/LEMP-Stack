#!/bin/bash
# LEMP stack provisioning on Ubuntu Trusty
# Written by Ish Sookun <ish@hacklog.mu>
# http://hacklog.mu
# November 2015

if [ "$(id -u)" != "0" ]; then
    echo "This script requires root privileges."
    exit 1
fi

APT_DIR="/etc/apt/sources.list.d"

# Add Nginx & MariaDB repo
echo "deb http://nginx.org/packages/ubuntu/ trusty nginx" >> "${APT_DIR}/nginx.list"
echo "deb [arch=amd64,i386] http://lon1.mirrors.digitalocean.com/mariadb/repo/10.1/ubuntu trusty main" >> "${APT_DIR}/mariadb.list"

apt-key adv --keyserver keyserver.ubuntu.com --recv-keys ABF5BD827BD9BF62 # Nginx pub_key
apt-key adv --recv-keys --keyserver hkp://keyserver.ubuntu.com:80 0xcbcb082a1bb943db # MariaDB pub_key
apt-get -y update
apt-get -y upgrade

# Packages installation
apt-get -y install nginx redis-server php5-fpm php5-mysql php5-redis php5-gd php5-json php5-mcrypt atop htop

debconf-set-selections <<< 'mariadb-server-10.0 mysql-server/root_password password lempstack'
debconf-set-selections <<< 'mariadb-server-10.0 mysql-server/root_password_again password lempstack'
apt-get install -y mariadb-server

# Stop services
pidof -x nginx && service nginx stop
pidof -x php5-fpm && service php5-fpm stop
pidof -x redis-server && service redis-server stop
pidof -x mysqld && service mysql stop

# Nginx configuration
if [ ! -d "/etc/nginx/sites-enabled" ]; then
mkdir -p /etc/nginx/{sites-available,sites-enabled}
mkdir -p /var/www/default
ln -s /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default

cat << index_file > /var/www/default/index.php
<?php echo '<center><h1>LEMP running :)</h1></center>'; ?>
index_file

cat << nginx_conf > /etc/nginx/nginx.conf
user www-data;
worker_processes 1;
error_log   /var/log/nginx/error.log warn;
pid         /var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    log_format main '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                    '\$status \$body_bytes_sent "\$http_referer" '
                    '"\$http_user_agent" "\$http_x_forwarded_for"';
    
    access_log /var/log/nginx/access.log main;
    sendfile            on;
    tcp_nopush          on;
    tcp_nodelay         on;
    keepalive_timeout   60;
    gzip                on;

    include /etc/nginx/sites-enabled/*;

}
nginx_conf
fi

# Replace Nginx default virtual host
cat << nginx_vhost > /etc/nginx/sites-available/default
server {
    listen 80;
    server_name localhost;
    server_tokens off;
    root /var/www/default;
    index index.php index.html index.htm;

    access_log /var/log/nginx/default_access.log main;
    error_log /var/log/nginx/default_error.log;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        fastcgi_pass 127.0.0.1:9000;
        fastcgi_read_timeout 150;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ (^|/)\. {
        return 403;
    }
}
nginx_vhost

# PHP-FPM config
if [ -d "/etc/php5/fpm/pool.d" ]; then
cat << php_fpm > /etc/php5/fpm/pool.d/www.conf
[www]
user                    = www-data
group                   = www-data
listen                  = 127.0.0.1:9000
listen.owner            = www-data
listen.group            = www-data
pm                      = dynamic
pm.max_children         = 5
pm.start_servers        = 2
pm.min_spare_servers    = 1
pm.max_spare_servers    = 3
chdir                   = /
php_fpm

cat << php_ini > /etc/php5/fpm/php.ini
[PHP]
engine = On
short_open_tag = Off
asp_tags = Off
precision = 14
output_buffering = 4096
zlib.output_compression = Off
implicit_flush = Off
unserialize_callback_func =
serialize_precision = 17
disable_functions = pcntl_alarm,pcntl_fork,pcntl_waitpid,pcntl_wait,pcntl_wifexited,pcntl_wifstopped,pcntl_wifsignaled,pcntl_wexitstatus,pcntl_wtermsig,pcntl_wstopsig,pcntl_signal,pcntl_signal_dispatch,pcntl_get_last_error,pcntl_strerror,pcntl_sigprocmask,pcntl_sigwaitinfo,pcntl_sigtimedwait,pcntl_exec,pcntl_getpriority,pcntl_setpriority,
disable_classes =
zend.enable_gc = On
expose_php = On
max_execution_time = 30
max_input_time = 60
memory_limit = 128M
error_reporting = E_ALL & ~E_DEPRECATED & ~E_STRICT
display_errors = Off
display_startup_errors = Off
log_errors = On
log_errors_max_len = 1024
ignore_repeated_errors = Off
ignore_repeated_source = Off
report_memleaks = On
track_errors = Off
html_errors = On
variables_order = "GPCS"
request_order = "GP"
register_argc_argv = Off
auto_globals_jit = On
post_max_size = 100M
auto_prepend_file =
auto_append_file =
default_mimetype = "text/html"
doc_root =
user_dir =
enable_dl = Off
file_uploads = On
upload_max_filesize = 100M
max_file_uploads = 20
allow_url_fopen = On
allow_url_include = Off
default_socket_timeout = 60
[CLI Server]
cli_server.color = On
[Date]
[filter]
[iconv]
[intl]
[sqlite]
[sqlite3]
[Pcre]
[Pdo]
[Pdo_mysql]
pdo_mysql.cache_size = 2000
pdo_mysql.default_socket=
[Phar]
[mail function]
SMTP = localhost
smtp_port = 25
mail.add_x_header = On
[SQL]
sql.safe_mode = Off
[ODBC]
odbc.allow_persistent = On
odbc.check_persistent = On
odbc.max_persistent = -1
odbc.max_links = -1
odbc.defaultlrl = 4096
odbc.defaultbinmode = 1
[Interbase]
ibase.allow_persistent = 1
ibase.max_persistent = -1
ibase.max_links = -1
ibase.timestampformat = "%Y-%m-%d %H:%M:%S"
ibase.dateformat = "%Y-%m-%d"
ibase.timeformat = "%H:%M:%S"
[MySQL]
mysql.allow_local_infile = On
mysql.allow_persistent = On
mysql.cache_size = 2000
mysql.max_persistent = -1
mysql.max_links = -1
mysql.default_port =
mysql.default_socket =
mysql.default_host =
mysql.default_user =
mysql.default_password =
mysql.connect_timeout = 60
mysql.trace_mode = Off
[MySQLi]
mysqli.max_persistent = -1
mysqli.allow_persistent = On
mysqli.max_links = -1
mysqli.cache_size = 2000
mysqli.default_port = 3306
mysqli.default_socket =
mysqli.default_host =
mysqli.default_user =
mysqli.default_pw =
mysqli.reconnect = Off
[mysqlnd]
mysqlnd.collect_statistics = On
mysqlnd.collect_memory_statistics = Off
[OCI8]
[PostgreSQL]
pgsql.allow_persistent = On
pgsql.auto_reset_persistent = Off
pgsql.max_persistent = -1
pgsql.max_links = -1
pgsql.ignore_notice = 0
pgsql.log_notice = 0
[Sybase-CT]
sybct.allow_persistent = On
sybct.max_persistent = -1
sybct.max_links = -1
sybct.min_server_severity = 10
sybct.min_client_severity = 10
[bcmath]
bcmath.scale = 0
[browscap]
[Session]
session.save_handler = files
session.use_strict_mode = 0
session.use_cookies = 1
session.use_only_cookies = 1
session.name = PHPSESSID
session.auto_start = 0
session.cookie_lifetime = 0
session.cookie_path = /
session.cookie_domain =
session.cookie_httponly =
session.serialize_handler = php
session.gc_probability = 0
session.gc_divisor = 1000
session.gc_maxlifetime = 1440
session.bug_compat_42 = Off
session.bug_compat_warn = Off
session.referer_check =
session.cache_limiter = nocache
session.cache_expire = 180
session.use_trans_sid = 0
session.hash_function = 0
session.hash_bits_per_character = 5
url_rewriter.tags = "a=href,area=href,frame=src,input=src,form=fakeentry"
[MSSQL]
mssql.allow_persistent = On
mssql.max_persistent = -1
mssql.max_links = -1
mssql.min_error_severity = 10
mssql.min_message_severity = 10
mssql.compatibility_mode = Off
mssql.secure_connection = Off
[Assertion]
[COM]
[mbstring]
[gd]
[exif]
[Tidy]
tidy.clean_output = Off
[soap]
soap.wsdl_cache_enabled=1
soap.wsdl_cache_dir="/tmp"
soap.wsdl_cache_ttl=86400
soap.wsdl_cache_limit = 5
[sysvshm]
[ldap]
ldap.max_links = -1
[mcrypt]
[dba]
[opcache]
[curl]
php_ini
fi

# MySQL config
if [ -d "/etc/mysql" ]; then
cat << mysql_config > /etc/mysql/my.cnf
[client]
port        = 3306
socket      = /var/run/mysqld/mysqld.sock
user            = root
password        = lempstack


[mysqld_safe]
socket      = /var/run/mysqld/mysqld.sock
nice        = 0

[mysqld]
user        = mysql
pid-file    = /var/run/mysqld/mysqld.pid
socket      = /var/run/mysqld/mysqld.sock
port        = 3306
basedir     = /usr
datadir     = /var/lib/mysql
tmpdir      = /tmp
lc_messages_dir = /usr/share/mysql
lc_messages = en_US
skip-external-locking
bind-address        = 127.0.0.1
max_connections     = 100
connect_timeout     = 5
wait_timeout        = 600
max_allowed_packet  = 16M
thread_cache_size       = 128
sort_buffer_size    = 4M
bulk_insert_buffer_size = 16M
tmp_table_size      = 32M
max_heap_table_size = 32M
myisam_recover          = BACKUP
key_buffer_size     = 128M
table_open_cache    = 400
myisam_sort_buffer_size = 512M
concurrent_insert   = 2
read_buffer_size    = 2M
read_rnd_buffer_size    = 1M
query_cache_limit       = 128K
query_cache_size        = 64M
log_warnings        = 2
slow_query_log_file = /var/log/mysql/mariadb-slow.log
long_query_time = 10
log_slow_verbosity  = query_plan

default_storage_engine  = InnoDB
innodb_buffer_pool_size = 256M
innodb_log_buffer_size  = 8M
innodb_file_per_table   = 1
innodb_open_files       = 400
innodb_io_capacity      = 400
innodb_flush_method     = O_DIRECT

[galera]

[mysqldump]
quick
quote-names
max_allowed_packet      = 16M
user                    = root
password                = lempstack

[mysql]

[isamchk]
key_buffer              = 16M

!includedir /etc/mysql/conf.d/
mysql_config
fi

# Start services
pidof -x mysqld || service mysql start
pidof -x redis-server || service redis-server start
pidof -x php5-fpm || service php5-fpm start
pidof -x nginx || service nginx start
