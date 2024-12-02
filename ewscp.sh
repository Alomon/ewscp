#!/bin/bash

# Цвета для вывода в консоль
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color


# Проверяем, запущен ли скрипт от суперпользователя
if [ "$EUID" -ne 0 ]; then
  echo "Пожалуйста, запустите этот скрипт с правами суперпользователя."
  exit 1
fi


# Проверка переменных окружения, перед выполнением скрипта
if [[ -z "$ROOT_PASS" || -z "$USER_NAME" || -z "$USER_PASS" || -z "$DOMAIN_NAME" ]]; then
  echo -e "${RED}Ошибка: Переменные окружения ROOT_PASS, USER_NAME, USER_PASS и DOMAIN_NAME должны быть заданы.${NC}"
  exit 1
fi


# Функция для успешного вывода сообщений
function success_message() {
  echo -e "${GREEN}$1${NC}"
}


# Функция для вывода ошибок
function error_message() {
  echo -e "${RED}$1${NC}"
}


# Функция для экранирования специальных символов
escape_special_chars() {
  printf '%q' "$1"
}


# Экранирование паролей
ESCAPED_ROOT_PASS=$(escape_special_chars "$ROOT_PASS")
ESCAPED_USER_PASS=$(escape_special_chars "$USER_PASS")


# Установка временной зоны
success_message "Установка временной зоны на Томское время"
if sudo timedatectl set-timezone Asia/Tomsk; then
  success_message "Временная зона успешно установлена."
else
  error_message "Ошибка установки временной зоны."
fi


# Обновление системы
success_message "Обновление списка пакетов..."
if sudo apt-get update > /dev/null 2>&1; then
  success_message "Список пакетов обновлен."
else
  error_message "Ошибка обновления списка пакетов."
fi


# Дистрибутивное обновление
success_message "Запуск дистрибутивного обновления..."
if sudo apt-get dist-upgrade -y > /dev/null 2>&1; then
  success_message "Система успешно обновлена."
else
  error_message "Ошибка обновления системы."
fi

# Установка expect для автоматизации ввода пароля
success_message "Установка expect для автоматизации взаимодействия с программами, запрашивающими ввод"
if sudo apt install -y expect > /dev/null 2>&1; then
  success_message "Expect установлен."
else
  error_message "Ошибка установки expect."
fi


# Включение учетной записи root и установка пароля
success_message "Включение учетной записи root и установка пароля..."
if command -v expect > /dev/null; then
expect <<EOF > /dev/null 2>&1
spawn sudo passwd root
expect "New password:"
send "$ESCAPED_ROOT_PASS\r"
expect "Retype new password:"
send "$ESCAPED_ROOT_PASS\r"
expect eof
EOF
  success_message "Пароль root успешно установлен."
else
  error_message "Expect не установлен. Установите его командой 'sudo apt install expect'."
fi





# Установка Midnight Commander (mc)
success_message "Установка Midnight Commander..."
if sudo apt install -y mc > /dev/null 2>&1; then
  success_message "Midnight Commander установлен."
else
  error_message "Ошибка установки Midnight Commander."
fi


# Установка SAMBA
success_message "Установка SAMBA..."
if sudo apt install -y samba > /dev/null 2>&1; then
  success_message "Samba установлена."
else
  error_message "Ошибка установки Samba."
fi


# Настройка SAMBA конфигурации
success_message "Настройка SAMBA конфигурации..."
# Комментирование разделов [homes], [printers] и [print$]
sudo sed -i '/\[printers\]/,/^\[/ s/^/#/' /etc/samba/smb.conf
sudo sed -i '/\[print\$\]/,/^\[/ s/^/#/' /etc/samba/smb.conf
sudo sed -i '/\[homes\]/,/^\[/ s/^/#/' /etc/samba/smb.conf
# Добавление строки в раздел [global]
sudo sed -i '/^\[global\]/a \   socket options = TCP_NODELAY IPTOS_LOWDELAY' /etc/samba/smb.conf
# Закомментирование строки map to guest
sudo sed -i 's/^\(.*map to guest = bad user.*\)$/#\1/' /etc/samba/smb.conf
# Проверяем, есть ли секция [homes], если нет - добавляем её в конец файла
if ! grep -q "^\[homes\]" /etc/samba/smb.conf; then
  echo -e "[homes]\n   comment = Home Directories\n   browseable = no\n   writeable = yes\n   create mask = 0770\n   directory mask = 0770\n   valid users = %S\n   hide dot files = no" | sudo tee -a /etc/samba/smb.conf >/dev/null 2>&1 
fi
success_message "Настройка SAMBA завершена."


# Добавление пользователя root в Samba и установка пароля
success_message "Добавление пользователя root в Samba и установка пароля..."
if command -v expect > /dev/null; then
  expect <<EOF > /dev/null 2>&1
spawn sudo smbpasswd -a root
expect "New SMB password:"
send "$ESCAPED_ROOT_PASS\r"
expect "Retype new SMB password:"
send "$ESCAPED_ROOT_PASS\r"
expect eof
EOF

  success_message "Пользователь root успешно добавлен в Samba."
  
  # Активация пользователя root
  if sudo smbpasswd -e root >/dev/null 2>&1; then
    success_message "Пользователь root активирован в Samba."
  else
    error_message "Ошибка активации пользователя root в Samba."
    exit 1
  fi
else
  error_message "Утилита expect не установлена. Установите её командой 'sudo apt install expect'."
  exit 1
fi

# Добавление суперпользователя в Samba и установка пароля
success_message "Добавление суперпользователя $USER_NAME в Samba и установка пароля..."
if command -v expect > /dev/null; then
  expect <<EOF > /dev/null 2>&1
spawn sudo smbpasswd -a $USER_NAME
expect "New SMB password:"
send "$ESCAPED_USER_PASS\r"
expect "Retype new SMB password:"
send "$ESCAPED_USER_PASS\r"
expect eof
EOF

  success_message "Суперпользователь $USER_NAME успешно добавлен в Samba."
  
  # Активация суперпользователя
  if sudo smbpasswd -e "$USER_NAME" >/dev/null 2>&1; then
    success_message "Суперпользователь $USER_NAME активирован в Samba."
  else
    error_message "Ошибка активации суперпользователя $USER_NAME в Samba."
    exit 1
  fi
else
  error_message "Утилита expect не установлена. Установите её командой 'sudo apt install expect'."
  exit 1
fi

# Установка и настройка MySQL
success_message "Установка MySQL..."
if sudo apt install -y mysql-server >/dev/null 2>&1; then
  success_message "MySQL установлен."
else
  error_message "Ошибка установки MySQL."
  exit 1
fi

# Настройка пользователя root в MySQL
success_message "Настройка пользователя root в MySQL..."

if sudo mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH caching_sha2_password BY '$ESCAPED_ROOT_PASS'; FLUSH PRIVILEGES;" >/dev/null 2>&1; then
  success_message "Пароль пользователя root успешно изменен."
else
  error_message "Ошибка изменения пароля пользователя root."
  exit 1
fi

# Запуск скрипта mysql_secure_installation с автоматическими ответами
success_message "Запуск mysql_secure_installation..."

# Используем expect для автоматизации ответов на вопросы
if command -v expect > /dev/null; then
  expect <<EOF > /dev/null 2>&1
spawn sudo mysql_secure_installation
expect "Enter password for user root:"
send "$ESCAPED_ROOT_PASS\r"
expect "Switch to unix_socket authentication [Y/n]"
send "n\r"
expect "Change the root password? [Y/n]"
send "n\r"
expect "Remove anonymous users? [Y/n]"
send "Y\r"
expect "Disallow root login remotely? [Y/n]"
send "N\r"
expect "Remove test database and access to it? [Y/n]"
send "Y\r"
expect "Reload privilege tables now? [Y/n]"
send "Y\r"
expect eof
EOF
  success_message "MySQL успешно настроен."
else
  error_message "Утилита expect не установлена. Установите её командой 'sudo apt install expect'."
  exit 1
fi

# Установка и настройка PostgreSQL
success_message "Установка PostgreSQL..."
if sudo apt install -y postgresql postgresql-client >/dev/null 2>&1; then
  success_message "PostgreSQL установлен."
else
  error_message "Ошибка установки PostgreSQL."
  exit 1
fi

# Установка пароля для пользователя postgres
success_message "Установка пароля для пользователя postgres..."

# Установка пароля через переменную окружения PGPASSWORD
PGPASSWORD="$ROOT_PASS" sudo -u postgres psql -c "ALTER USER postgres WITH PASSWORD '$ROOT_PASS';" >/dev/null 2>&1

# Проверка успешности команды
if [ $? -eq 0 ]; then
  success_message "Пароль пользователя postgres успешно установлен."
else
  error_message "Ошибка установки пароля пользователя postgres."
  exit 1
fi


success_message "Настройка PostgreSQL завершена."

# Установка Apache и mpm-itk
success_message "Установка Apache и mpm-itk..."
if sudo apt-get install -y apache2 libapache2-mpm-itk >/dev/null 2>&1; then
  success_message "Apache и mpm-itk установлены."

  # Включение модуля rewrite
  success_message "Включение модуля rewrite..."
  if sudo a2enmod rewrite >/dev/null 2>&1; then
    success_message "Модуль rewrite включен."
  else
    error_message "Ошибка включения модуля rewrite."
    exit 1
  fi

  # Перезапуск Apache для применения изменений
  success_message "Перезапуск Apache..."
  if sudo systemctl restart apache2 >/dev/null 2>&1; then
    success_message "Apache перезапущен."
  else
    error_message "Ошибка перезапуска Apache."
    exit 1
  fi

else
  error_message "Ошибка установки Apache и mpm-itk."
  exit 1
fi

# Изменение приоритетов расширений Apache
APACHE_CONF="/etc/apache2/mods-enabled/dir.conf"
success_message "Изменение приоритетов расширений Apache..."

# Замена строки в конфигурационном файле
if sudo sed -i 's/DirectoryIndex .*/DirectoryIndex index.php index.cgi index.pl index.html index.xhtml index.htm/' "$APACHE_CONF"; then
  success_message "Приоритеты расширений Apache успешно изменены."
else
  error_message "Ошибка изменения приоритетов расширений Apache."
  exit 1
fi

# Перезапуск Apache для применения изменений
success_message "Перезапуск Apache для применения настроек..."
if sudo systemctl restart apache2; then
  success_message "Apache успешно перезапущен."
else
  error_message "Ошибка перезапуска Apache."
  exit 1
fi

# Путь к домашней директории суперпользователя
USER_HOME="/home/$USER_NAME"

# Создание необходимых директорий
success_message "Создание папок сайтов и логов..."

# Создание папок
sudo mkdir -p "$USER_HOME/.log"
sudo mkdir -p "$USER_HOME/$DOMAIN_NAME"
sudo mkdir -p "$USER_HOME/adminer.$DOMAIN_NAME"
sudo mkdir -p "$USER_HOME/phpmyadmin.$DOMAIN_NAME"
sudo mkdir -p "$USER_HOME/phppgadmin.$DOMAIN_NAME"
sudo chown -R $USER_NAME:$USER_NAME "$USER_HOME/.log"
sudo chown -R $USER_NAME:$USER_NAME "$USER_HOME/$DOMAIN_NAME"
sudo chown -R $USER_NAME:$USER_NAME "$USER_HOME/adminer.$DOMAIN_NAME"
sudo chown -R $USER_NAME:$USER_NAME "$USER_HOME/phpmyadmin.$DOMAIN_NAME"
sudo chown -R $USER_NAME:$USER_NAME "$USER_HOME/phppgadmin.$DOMAIN_NAME"
sudo chmod -R 770 "$USER_HOME/.log"
sudo chmod -R 770 "$USER_HOME/$DOMAIN_NAME"
sudo chmod -R 770 "$USER_HOME/adminer.$DOMAIN_NAME"
sudo chmod -R 770 "$USER_HOME/phpmyadmin.$DOMAIN_NAME"
sudo chmod -R 770 "$USER_HOME/phppgadmin.$DOMAIN_NAME"

success_message "Папки успешно созданы в домашней директории $USER_HOME."

# Путь к файлам конфигурации
APACHE_CONF_MAIN="/etc/apache2/sites-available/000-default.conf"

# Очистка файла и добавление нового содержимого для панели управления веб-сервером
success_message "Настройка VirtualHost для Apache..."
sudo tee "$APACHE_CONF_MAIN" > /dev/null <<EOL
<VirtualHost *:80>
        ServerName $DOMAIN_NAME
        ServerAdmin $USER_NAME@$DOMAIN_NAME
        DocumentRoot $USER_HOME/$DOMAIN_NAME
        AssignUserId $USER_NAME $USER_NAME
        ErrorLog $USER_HOME/.log/${DOMAIN_NAME}_error.log
        <Directory $USER_HOME/$DOMAIN_NAME>
                Options Indexes FollowSymLinks
                AllowOverride All
                Require all granted
        </Directory>
</VirtualHost>
EOL
success_message "Конфигурация VirtualHost успешно обновлена (панель управления веб-сервером)."

# Повторение для adminer, phpmyadmin, phppgadmin
for site in adminer phpmyadmin phppgadmin; do
  APACHE_CONF="/etc/apache2/sites-available/000-${site}.conf"
  
  sudo tee "$APACHE_CONF" > /dev/null <<EOL
<VirtualHost *:80>
        ServerName $site.$DOMAIN_NAME
        ServerAdmin $USER_NAME@$DOMAIN_NAME
        DocumentRoot $USER_HOME/$site.$DOMAIN_NAME
        AssignUserId $USER_NAME $USER_NAME
        ErrorLog $USER_HOME/.log/$site.${DOMAIN_NAME}_error.log
        <Directory $USER_HOME/$site.$DOMAIN_NAME>
                Options Indexes FollowSymLinks
                AllowOverride All
                Require all granted
        </Directory>
</VirtualHost>
EOL

  success_message "Конфигурация VirtualHost успешно обновлена ($site)."
done

# Включение сайтов без вывода сообщений
sudo a2ensite 000-default.conf > /dev/null 2>&1
sudo a2ensite 000-adminer.conf > /dev/null 2>&1
sudo a2ensite 000-phpmyadmin.conf > /dev/null 2>&1
sudo a2ensite 000-phppgadmin.conf > /dev/null 2>&1

# Настройка папок сервера
success_message "Изменение настроек папок сервера..."

# Добавление конфигурации для /srv/
sudo tee -a /etc/apache2/apache2.conf > /dev/null <<EOL
<Directory /srv/>
    Options Indexes FollowSymLinks
    AllowOverride All
    Require all granted
</Directory>
EOL

success_message "Настройки папок сервера успешно изменены."

# Изменение безопасности сервера
success_message "Изменение безопасности сервера..."

# Добавление конфигурации в security.conf
if ! grep -q "<IfModule mpm_itk_module>" /etc/apache2/conf-available/security.conf; then
  sudo sed -i '1i <IfModule mpm_itk_module>' /etc/apache2/conf-available/security.conf
  sudo sed -i '2i \    LimitUIDRange 0 4294967295' /etc/apache2/conf-available/security.conf
  sudo sed -i '3i \    LimitGIDRange 0 4294967295' /etc/apache2/conf-available/security.conf
  sudo sed -i '4i \</IfModule>' /etc/apache2/conf-available/security.conf
fi

success_message "Безопасность сервера успешно изменена."

# Перезагрузка Apache
sudo systemctl reload apache2 > /dev/null 2>&1

success_message "Apache перезагружен."

# Установка и настройка PHP
success_message "Установка PHP 8.3..."

# Добавление PPA репозитория для PHP
sudo add-apt-repository ppa:ondrej/php -y > /dev/null 2>&1

# Обновление списка пакетов
sudo apt-get update > /dev/null

# Установка PHP 8.3 и необходимых модулей
sudo apt-get install php8.3 php8.3-cli php8.3-dev php8.3-xml php8.3-bz2 php8.3-curl php8.3-gd php8.3-imagick php8.3-intl php8.3-mbstring php8.3-mysql php8.3-pgsql php8.3-mcrypt php8.3-zip php8.3-soap php8.3-ldap libapache2-mod-php8.3 -y --allow-unauthenticated > /dev/null 2>&1

# Проверка установки PHP
if php -v > /dev/null 2>&1; then
    success_message "PHP 8.3 успешно установлено."
else
    error_message "Ошибка при установке PHP 8.3."
fi

# Путь к файлу php.ini
PHP_INI="/etc/php/8.3/apache2/php.ini"

# Убедимся, что у нас есть доступ к файлу
if [ -f "$PHP_INI" ]; then
    # Изменение max_input_vars
    sudo sed -i 's/^;max_input_vars =.*/max_input_vars = 5000/' "$PHP_INI"
    
    # Изменение memory_limit, post_max_size, upload_max_filesize, max_file_uploads
    sudo sed -i 's/^memory_limit =.*/memory_limit = 2048M/' "$PHP_INI"
    sudo sed -i 's/^post_max_size =.*/post_max_size = 4096M/' "$PHP_INI"
    sudo sed -i 's/^upload_max_filesize =.*/upload_max_filesize = 4096M/' "$PHP_INI"
    sudo sed -i 's/^max_file_uploads =.*/max_file_uploads = 20/' "$PHP_INI"
    
    # Изменение date.timezone
    sudo sed -i 's|^;date.timezone =.*|date.timezone = "Asia/Tomsk"|' "$PHP_INI"

    success_message "Файл php.ini успешно обновлён."
else
    error_message "Файл php.ini не найден."
fi

# Перезагрузка Apache
sudo systemctl reload apache2 > /dev/null 2>&1

success_message "Apache перезагружен."

# Путь к файлу sudoers
SUDOERS_FILE="/etc/sudoers"

# Функция для добавления пользователя в sudoers
add_to_sudoers() {
    # Проверяем, что запись еще не существует
    if ! sudo grep -q "^$USER_NAME ALL=(ALL:ALL) NOPASSWD: ALL" "$SUDOERS_FILE"; then
        echo "$USER_NAME ALL=(ALL:ALL) NOPASSWD: ALL" | sudo tee -a "$SUDOERS_FILE" > /dev/null
    fi

    # Изменяем строку для группы sudo с учетом возможной табуляции
    sudo sed -i 's/^%sudo[[:space:]]\+ALL=(ALL:ALL)[[:space:]]\+ALL/%sudo ALL=(ALL:ALL) NOPASSWD: ALL/' "$SUDOERS_FILE"
}

# Вызываем функцию
add_to_sudoers

success_message "Права для sudo успешно обновлены."

# Установка Composer
success_message "Установка Composer..."

# Скачивание установочного файла Composer
curl -sS https://getcomposer.org/installer -o composer-setup.php

# Установка Composer в /usr/local/bin, без вывода сообщений
sudo php composer-setup.php --install-dir=/usr/local/bin --filename=composer > /dev/null 2>&1

# Проверка успешности установки
if [ $? -eq 0 ]; then
    success_message "Composer успешно установлен."
else
    error_message "Ошибка при установке Composer."
fi

# Удаление установочного файла
rm -f composer-setup.php





# Установка Docker
#success_message "Установка Docker..."
#sudo apt install docker.io -y > /dev/null 2>&1

# Загрузка образа Microsoft SQL Server
#success_message "Загрузка образа Microsoft SQL Server..."
#sudo docker pull mcr.microsoft.com/mssql/server:latest

# Создание каталога для данных SQL Server
#sudo mkdir -p /var/opt/mssql
#sudo chown -R 10001:10001 /var/opt/mssql
#sudo chmod -R 775 /var/opt/mssql

# Запуск контейнера Microsoft SQL Server
#success_message "Запуск контейнера Microsoft SQL Server..."
#sudo docker run -e "ACCEPT_EULA=Y" -e "SA_PASSWORD=$ROOT_PASS" -p 1433:1433 --name MSSQLSERVER -v /var/opt/mssql:/var/opt/mssql -d mcr.microsoft.com/mssql/server:latest > /dev/null 2>&1

# Настройка systemd для автоматического запуска контейнера
#success_message "Настройка автоматического запуска контейнера..."
#sudo tee /etc/systemd/system/docker-mssqlserver.service > /dev/null <<EOL
#[Unit]
#Description=Docker Container for SQL Server
#Requires=docker.service
#After=docker.service
#
#[Service]
#Restart=always
#ExecStart=/usr/bin/docker start MSSQLSERVER
#ExecStop=/usr/bin/docker stop MSSQLSERVER
#
#[Install]
#WantedBy=multi-user.target
#EOL
#
# Перезагрузка systemd и включение сервиса
#sudo systemctl daemon-reload > /dev/null 2>&1
#sudo systemctl enable docker-mssqlserver.service > /dev/null 2>&1
#
#success_message "Docker и Microsoft SQL Server успешно установлены и настроены."

# Установка Docker
#success_message "Установка Microsoft SQL Server..."





# Установка MSSQL Server
success_message "Установка Microsoft SQL Server..."

# Установка ключей Microsoft
curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --dearmor -o /usr/share/keyrings/microsoft-prod.gpg > /dev/null 2>&1
curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | sudo tee /etc/apt/trusted.gpg.d/microsoft.asc > /dev/null 2>&1
curl -fsSL https://packages.microsoft.com/config/ubuntu/22.04/mssql-server-2022.list | sudo tee /etc/apt/sources.list.d/mssql-server-2022.list > /dev/null 2>&1

# Обновление системы и установка зависимостей
curl -OL http://archive.ubuntu.com/ubuntu/pool/main/o/openldap/libldap-2.5-0_2.5.18+dfsg-0ubuntu0.22.04.2_amd64.deb > /dev/null 2>&1
sudo apt-get install -y ./libldap-2.5-0_2.5.18+dfsg-0ubuntu0.22.04.2_amd64.deb > /dev/null 2>&1
rm -f ./libldap-2.5-0_2.5.18+dfsg-0ubuntu0.22.04.2_amd64.deb > /dev/null 2>&1
sudo apt-get update > /dev/null 2>&1

# Установка MSSQL Server
sudo apt-get install -y mssql-server > /dev/null 2>&1

# Используем expect для автоматического ответа на вопросы конфигурации
sudo expect <<EOF > /dev/null 2>&1
spawn env ACCEPT_EULA=Y MSSQL_COLLATION=Cyrillic_General_CI_AS /opt/mssql/bin/mssql-conf setup
expect "Enter your edition(1-10):"
send "2\r"
expect "Enter the SQL Server system administrator password:"
send "$ESCAPED_ROOT_PASS\r"
expect "Confirm the SQL Server system administrator password:"
send "$ESCAPED_ROOT_PASS\r"
expect eof
EOF

# Изменение владельца и прав доступа для каталога данных MSSQL
sudo chown -R mssql:mssql /var/opt/mssql > /dev/null 2>&1
sudo chmod -R 775 /var/opt/mssql > /dev/null 2>&1
sudo chown -R mssql:mssql /var/opt/mssql/log > /dev/null 2>&1
sudo chmod -R 775 /var/opt/mssql/log > /dev/null 2>&1

# Перезапуск сервиса MSSQL Server
sudo systemctl restart mssql-server > /dev/null 2>&1

# Проверка успешности установки MSSQL Server
if systemctl is-active --quiet mssql-server; then
    success_message "MSSQL Server успешно установлен и запущен."
else
    error_message "Ошибка при установке MSSQL Server."
fi





# Установка Microsoft ODBC 17
success_message "Установка Microsoft ODBC 17..."

# Добавление ключа Microsoft и репозитория
curl -sS https://packages.microsoft.com/keys/microsoft.asc | sudo tee /etc/apt/trusted.gpg.d/microsoft.asc > /dev/null
curl -sS https://packages.microsoft.com/config/ubuntu/22.04/prod.list | sudo tee /etc/apt/sources.list.d/mssql-release.list > /dev/null

# Обновление списка пакетов
sudo apt-get update > /dev/null 2>&1

# Установка драйвера ODBC
sudo ACCEPT_EULA=Y apt-get install -y msodbcsql17 > /dev/null 2>&1

# Установка дополнительных утилит (по желанию)
success_message "Установка дополнительных утилит (bcp и sqlcmd)..."
sudo ACCEPT_EULA=Y apt-get install -y mssql-tools > /dev/null 2>&1
echo 'export PATH="$PATH:/opt/mssql-tools/bin"' >> ~/.bashrc
source ~/.bashrc

# Установка заголовков разработки unixODBC (по желанию)
success_message "Установка заголовков разработки unixODBC..."
sudo apt-get install -y unixodbc-dev > /dev/null 2>&1

# Установка драйверов PHP для Microsoft SQL Server
success_message "Установка драйверов PHP для Microsoft SQL Server..."
sudo pecl channel-update pecl.php.net > /dev/null 2>&1
sudo pecl install sqlsrv > /dev/null 2>&1
sudo pecl install pdo_sqlsrv > /dev/null 2>&1

# Конфигурация драйверов PHP
success_message "Конфигурация драйверов PHP..."
sudo bash -c 'printf "; priority=20\nextension=sqlsrv.so\n" > /etc/php/8.3/mods-available/sqlsrv.ini'
sudo bash -c 'printf "; priority=30\nextension=pdo_sqlsrv.so\n" > /etc/php/8.3/mods-available/pdo_sqlsrv.ini'

# Включение модулей
sudo phpenmod -v 8.3 sqlsrv pdo_sqlsrv > /dev/null 2>&1

success_message "Microsoft ODBC 17 и драйверы PHP для Microsoft SQL Server успешно установлены."

# Перезагрузка Apache
sudo systemctl reload apache2 > /dev/null 2>&1

success_message "Apache перезагружен."

# Создание структуры папок для работы системы
success_message "Создание структуры папок для работы системы..."

# Создание директорий
sudo mkdir -p /srv/users
mkdir -p "$USER_HOME/users"

# Монтирование директорий
sudo mount --bind /srv/users "$USER_HOME/users"

# Установка прав доступа для $USER_HOME/users
sudo chown -R "$USER_NAME:$USER_NAME" "$USER_HOME/users"
sudo chmod -R 775 "$USER_HOME/users"

# Проверка успешности монтирования
if [ $? -eq 0 ]; then
    success_message "Директории успешно смонтированы."
else
    error_message "Ошибка при монтировании директорий."
fi

# Прописать правила монтирования в /etc/fstab
success_message "Добавление правил монтирования в /etc/fstab..."
echo "/srv/users $USER_HOME/users none bind" | sudo tee -a /etc/fstab > /dev/null

success_message "Правила монтирования успешно добавлены в /etc/fstab."

# Установка Git
success_message "Установка Git..."

# Обновление списка пакетов
sudo apt update -y > /dev/null 2>&1

# Установка Git
sudo apt install -y git > /dev/null 2>&1

# Проверка успешности установки
if git --version > /dev/null 2>&1; then
    success_message "Git успешно установлен."
else
    error_message "Ошибка при установке Git."
fi

# Клонирование репозитория в временную директорию
TEMP_DIR=$(mktemp -d)

# Клонирование репозитория EWSCP
success_message "Клонирование репозитория EWSCP во временную директорию..."
sudo git clone https://github.com/Alomon/ewscp.git "$TEMP_DIR" >/dev/null 2>&1

# Проверка успешности клонирования
if [ $? -eq 0 ]; then
    success_message "Перемещение содержимого папки adminer в $USER_HOME/adminer.$DOMAIN_NAME..."
    sudo mv "$TEMP_DIR/adminer/"* "$USER_HOME/adminer.$DOMAIN_NAME/" >/dev/null 2>&1
else
    error_message "Ошибка при клонировании репозитория adminer."
    sudo rm -rf "$TEMP_DIR"
    exit 1
fi

# Проверка успешности клонирования
if [ $? -eq 0 ]; then
    success_message "Перемещение содержимого папки phpMyAdmin в $USER_HOME/phpmyadmin.$DOMAIN_NAME..."
    sudo mv "$TEMP_DIR/phpmyadmin/"* "$USER_HOME/phpmyadmin.$DOMAIN_NAME/" >/dev/null 2>&1
else
    error_message "Ошибка при клонировании репозитория phpMyAdmin."
    sudo rm -rf "$TEMP_DIR"
    exit 1
fi

# Проверка успешности клонирования
if [ $? -eq 0 ]; then
    success_message "Перемещение содержимого папки phpPgAdmin в $USER_HOME/phppgadmin.$DOMAIN_NAME..."
    sudo mv "$TEMP_DIR/phppgadmin/"* "$USER_HOME/phppgadmin.$DOMAIN_NAME/" >/dev/null 2>&1
else
    error_message "Ошибка при клонировании репозитория phpPgAdmin."
    sudo rm -rf "$TEMP_DIR"
    exit 1
fi

# Удаление временной директории
sudo rm -rf "$TEMP_DIR" >/dev/null 2>&1

success_message "Все репозитории успешно клонированы."

sudo chown -R $USER_NAME:$USER_NAME "$USER_HOME/.log"
sudo chown -R $USER_NAME:$USER_NAME "$USER_HOME/$DOMAIN_NAME"
sudo chown -R $USER_NAME:$USER_NAME "$USER_HOME/adminer.$DOMAIN_NAME"
sudo chown -R $USER_NAME:$USER_NAME "$USER_HOME/phpmyadmin.$DOMAIN_NAME"
sudo chown -R $USER_NAME:$USER_NAME "$USER_HOME/phppgadmin.$DOMAIN_NAME"
sudo chmod -R 770 "$USER_HOME/.log"
sudo chmod -R 770 "$USER_HOME/$DOMAIN_NAME"
sudo chmod -R 770 "$USER_HOME/adminer.$DOMAIN_NAME"
sudo chmod -R 770 "$USER_HOME/phpmyadmin.$DOMAIN_NAME"
sudo chmod -R 770 "$USER_HOME/phppgadmin.$DOMAIN_NAME"
