# ewscp
Educational web server control panel

Установка на чистый Ubuntu Server 24.04

## Вызов скрипта
Копируем файл скрипта
```sh
curl -O https://raw.githubusercontent.com/Alomon/ewscp/master/ewscp.sh
```
Делаем файл скрипта исполняемым
```sh
chmod +x ewscp.sh
```
Запускаем скрипт указав пароль root, логин и пароль суперпользователя, созданного при установке Ubuntu Server и ваше доменное имя
```sh
sudo env ROOT_PASS="your_root_password" USER_NAME="your_user" USER_PASS="your_user_password" DOMAIN_NAME="your_domain" bash ./ewscp.sh
```
