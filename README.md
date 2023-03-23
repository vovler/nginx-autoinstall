### API
For Ubuntu 22.04, it installs: 
- Nginx
- PHP 8 + PHP-FPM
- Workman
- Percona MySQL
- Xtrabackup
- Acme.sh for LetsEncrypt
- CSF
- Google TCP BBR 
- Other System Optimizations

### CDN
- Nginx
- PHP 8 + PHP-FPM
- Workman

### KMS
- Nginx
- PHP 8 + PHP-FPM
- Workman

### Static
- Nginx
- PHP 8

### Mail

### App

## Usage

Just download and execute the script :

```sh
rm autoinstall.sh; wget -qO autoinstall.sh https://raw.githubusercontent.com/vovler/nginx-php8-workman-percona_mysql-letsencrypt-csf-ubuntu22.04/master/autoinstall.sh && chmod +x autoinstall.sh && ./autoinstall.sh;
```
