#!/usr/bin/env bash
# greenguest.az üçün serveri bir dəfə hazırlayır. Təkrar işlədilə bilər: mövcud
# parollara, verilənlər bazasına, nginx konfiqurasiyasına və greenguest-api-yə toxunmur.
#
# İstifadə (root): bash server-setup.sh /root/websitedb.sql
set -euo pipefail

SQL_BACKUP="${1:?İstifadə: bash server-setup.sh /path/to/websitedb.sql}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

APP_DIR=/opt/app/greenguest-web
CONFIG_DIR=/etc/greenguest-web
APP_USER=greenguest-web
DEPLOY_USER=greenguest-deploy
DEPLOY_KEY=/root/greenguest-deploy-key
NGINX_SITE=/etc/nginx/sites-available/greenguest-web
APP_PORT=5080
DB_PORT=15432
DB_NAME=greenguest_web
DB_USER=greenguest_web
DB_CONTAINER=greenguest-postgres

fail() { echo "XƏTA: $*" >&2; exit 1; }

psql_db() {
	docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -q "$@"
}

# --- Yoxlamalar: serverdə heç nə dəyişməzdən əvvəl ---
[[ $EUID -eq 0 ]] || fail "Skripti root kimi işlədin."
[[ -f "$SQL_BACKUP" ]] || fail "Backup faylı tapılmadı: $SQL_BACKUP"
[[ "$(uname -m)" == "x86_64" ]] || fail "Deploy linux-x64 üçündür, bu server: $(uname -m)."

if [[ ! -f /etc/systemd/system/greenguest-web.service ]] && ss -ltn | grep -q ":$APP_PORT "; then
	fail "$APP_PORT portu artıq istifadə olunur. Bu portu deploy.yml, nginx və env-də dəyişin."
fi

if grep -rlE "server_name[^;]*[[:space:]](www\.)?greenguest\.az[;[:space:]]" \
	/etc/nginx/sites-enabled /etc/nginx/conf.d 2>/dev/null | grep -qv "greenguest-web"; then
	fail "Mövcud nginx konfiqurasiyası greenguest.az domenini istifadə edir. Əvvəlcə ona baxın: grep -r greenguest.az /etc/nginx"
fi

data_sql="$(mktemp)"
trap 'rm -f "$data_sql"' EXIT
python3 -I "$SCRIPT_DIR/backup-to-postgres.py" "$SQL_BACKUP" > "$data_sql"

# --- Paketlər ---
apt-get update -qq
apt-get install -y -qq rsync curl libicu74 certbot python3-certbot-nginx
command -v docker >/dev/null || apt-get install -y -qq docker.io
systemctl enable --now docker

# --- İstifadəçilər və qovluqlar ---
id "$APP_USER" >/dev/null 2>&1 || useradd --system --shell /usr/sbin/nologin "$APP_USER"
id "$DEPLOY_USER" >/dev/null 2>&1 || useradd --create-home --shell /bin/bash "$DEPLOY_USER"
install -d -o "$DEPLOY_USER" -g "$DEPLOY_USER" -m 755 "$APP_DIR"
install -d -o root -g "$APP_USER" -m 750 "$CONFIG_DIR"

if [[ ! -f "$DEPLOY_KEY" ]]; then
	ssh-keygen -q -t ed25519 -N "" -C "github-actions-greenguest-web" -f "$DEPLOY_KEY"
fi
install -d -o "$DEPLOY_USER" -g "$DEPLOY_USER" -m 700 "/home/$DEPLOY_USER/.ssh"
install -o "$DEPLOY_USER" -g "$DEPLOY_USER" -m 600 "$DEPLOY_KEY.pub" "/home/$DEPLOY_USER/.ssh/authorized_keys"

cat > /etc/sudoers.d/greenguest-web <<EOF
$DEPLOY_USER ALL=(root) NOPASSWD: /usr/bin/systemctl restart greenguest-web
EOF
chmod 440 /etc/sudoers.d/greenguest-web
visudo -cf /etc/sudoers.d/greenguest-web >/dev/null

# --- Parollar: yalnız ilk dəfə yaradılır ---
if [[ ! -f "$CONFIG_DIR/postgres.env" ]]; then
	( umask 077; cat > "$CONFIG_DIR/postgres.env" <<EOF
POSTGRES_USER=$DB_USER
POSTGRES_DB=$DB_NAME
POSTGRES_PASSWORD=$(openssl rand -hex 24)
EOF
	)
fi
DB_PASSWORD="$(sed -n 's/^POSTGRES_PASSWORD=//p' "$CONFIG_DIR/postgres.env")"

if [[ ! -f "$CONFIG_DIR/env" ]]; then
	ADMIN_PASSWORD="$(openssl rand -hex 12)"
	CONNECTION="Host=127.0.0.1;Port=$DB_PORT;Database=$DB_NAME;Username=$DB_USER;Password=$DB_PASSWORD"
	( umask 027; cat > "$CONFIG_DIR/env" <<EOF
ASPNETCORE_ENVIRONMENT=Production
ASPNETCORE_URLS=http://127.0.0.1:$APP_PORT
ConnectionStrings__DefaultConnection=$CONNECTION
ConnectionStrings__Default=$CONNECTION
AdminCredentials__Username=admin
AdminCredentials__Password=$ADMIN_PASSWORD
Jwt__Issuer=https://greenguest.az
Jwt__Audience=https://greenguest.az
Jwt__SecretKey=$(openssl rand -hex 32)
EOF
	)
	chgrp "$APP_USER" "$CONFIG_DIR/env"
fi

# --- PostgreSQL: yalnız localhost-a açıqdır ---
if ! docker inspect "$DB_CONTAINER" >/dev/null 2>&1; then
	docker run -d --name "$DB_CONTAINER" --restart unless-stopped \
		--env-file "$CONFIG_DIR/postgres.env" \
		-p "127.0.0.1:$DB_PORT:5432" \
		-v greenguest-postgres-data:/var/lib/postgresql/data \
		postgres:16 >/dev/null
fi

echo "PostgreSQL gözlənilir..."
for _ in $(seq 1 60); do
	psql_db -c "SELECT 1" >/dev/null 2>&1 && break
	sleep 2
done
psql_db -c "SELECT 1" >/dev/null || fail "PostgreSQL başlamadı: docker logs $DB_CONTAINER"

# --- Sxem və məlumatlar: mövcud baza üzərinə yazılmır ---
if [[ "$(psql_db -tAc "SELECT to_regclass('public.\"Sliders\"') IS NOT NULL")" == "f" ]]; then
	if ! { psql_db < "$SCRIPT_DIR/schema.sql" && psql_db < "$data_sql"; } > /root/greenguest-db-import.log 2>&1; then
		psql_db -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;" >/dev/null || true
		tail -n 20 /root/greenguest-db-import.log >&2
		fail "Bərpa alınmadı, yarımçıq sxem silindi. Tam log: /root/greenguest-db-import.log"
	fi
	echo "Baza bərpa olundu."
else
	echo "$DB_NAME artıq doludur, bərpa ötürüldü."
fi

# --- Servis ---
install -m 644 "$SCRIPT_DIR/greenguest-web.service" /etc/systemd/system/greenguest-web.service
systemctl daemon-reload
systemctl enable greenguest-web >/dev/null 2>&1

# --- nginx və sertifikat: certbot konfiqurasiyanı dəyişdiyi üçün yalnız ilk dəfə yazılır ---
if [[ ! -f "$NGINX_SITE" ]]; then
	install -m 644 "$SCRIPT_DIR/greenguest-web.nginx.conf" "$NGINX_SITE"
fi
ln -sf "$NGINX_SITE" /etc/nginx/sites-enabled/greenguest-web
nginx -t
systemctl reload nginx

cert_status="mövcuddur"
if [[ ! -d /etc/letsencrypt/live/greenguest.az ]]; then
	if ! certbot --nginx -d greenguest.az -d www.greenguest.az --non-interactive \
		--agree-tos --register-unsafely-without-email --redirect; then
		cert_status="ALINMADI: yuxarıdakı certbot xətasına baxın"
	else
		cert_status="alındı"
	fi
fi

server_ip="$(curl -4 -fsS -m 10 https://ifconfig.me || hostname -I | awk '{print $1}')"

cat <<EOF

================ Server hazırdır ================
SSL sertifikatı: $cert_status

GitHub Secrets (Settings > Secrets and variables > Actions):
  SSH_HOST:
    $server_ip
  SSH_KNOWN_HOSTS:
    $server_ip $(cut -d' ' -f1,2 /etc/ssh/ssh_host_ed25519_key.pub)
  SSH_PRIVATE_KEY (bu əmrin çıxışının hamısı):
    cat $DEPLOY_KEY

Admin paneli parolu:
  grep AdminCredentials__Password $CONFIG_DIR/env
=================================================
EOF
