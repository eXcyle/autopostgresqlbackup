IMAGE_NAME=autopostgresqlbackup
TAG=latest

DOCKER_REGISTRY=docker.io
DOCKER_USERNAME=jeroenkeizernl

GITHUB_REGISTRY=ghcr.io
GITHUB_USERNAME=jeroenkeizernl



.PHONY: pull test clean publish _build unittest shell

pull:
	@echo "📥 Pulling latest source..."
	git pull

_build: pull clean
	@echo "🐳 Building Docker image..."
	docker build -t $(IMAGE_NAME):$(TAG) .

test: _build
	@echo "🚀 Running container..."
	docker run -d --name $(IMAGE_NAME) \
		-e PG_DBHOST=myserver \
		-e PG_USERNAME=postgres \
		-e PG_PASSWORD=mypassword \
		-e PG_DB_NAME="all" \
		-e TZ="Europe/Amsterdam" \
		-e CRON_SCHEDULE="40 4 * * *" \
		$(IMAGE_NAME):$(TAG)

publish:
	@$(MAKE) unittest || { echo "❌ UnitTest failed. Aborting publish."; exit 1; }
	@echo "📦 Publishing image..."
	docker tag $(IMAGE_NAME):$(TAG) $(DOCKER_REGISTRY)/$(DOCKER_USERNAME)/$(IMAGE_NAME):$(TAG)
	docker tag $(IMAGE_NAME):$(TAG) $(GITHUB_REGISTRY)/$(GITHUB_USERNAME)/$(IMAGE_NAME):$(TAG)

	@echo "📤 Pushing to Docker Hub..."
	docker push $(DOCKER_REGISTRY)/$(DOCKER_USERNAME)/$(IMAGE_NAME):$(TAG)
	@echo "📤 Pushing to Github..."
	docker push $(GITHUB_REGISTRY)/$(GITHUB_USERNAME)/$(IMAGE_NAME):$(TAG)
	$(MAKE) clean

clean:
	@echo "🧹 Removing container and image..."
	-docker rm -f $(IMAGE_NAME) pgtest mysqltest || echo "Containers not found or already removed."
	-docker rmi -f \
		$(DOCKER_USERNAME)/$(IMAGE_NAME):latest \
		$(DOCKER_REGISTRY)/$(DOCKER_USERNAME)/$(IMAGE_NAME):latest \
		$(GITHUB_USERNAME)/$(IMAGE_NAME):latest \
		$(GITHUB_REGISTRY)/$(GITHUB_USERNAME)/$(IMAGE_NAME):latest \
		$(IMAGE_NAME):latest \
		postgres:15 \
		mariadb:11

	# Cleanup backup folder
	rm -rf BackupTest pgtest.sql mysqltest.sql

	# Cleanup images
	docker builder prune -f

	# Cleanup network
	docker network rm autopg-net || echo "Network not found or already removed."

	# Cleanup volumes
	docker volume prune -f

shell:
	@echo "🧑‍💻 Opening shell in container..."
	docker exec -it $(IMAGE_NAME) /bin/bash

unittest: pull clean _build
	@echo "🧪 Starting unit test..."

	# Create structured backup and data folders
	mkdir -p BackupTest/MySQLData
	mkdir -p BackupTest/PostgresqlData
	mkdir -p BackupTest/MySQLBackup
	mkdir -p BackupTest/PostgresqlBackup

	docker network inspect autopg-net >/dev/null 2>&1 || docker network create autopg-net

	# Start PostgreSQL
	docker run -d --name pgtest \
		--network autopg-net \
		-e POSTGRES_PASSWORD=mypassword \
		-e POSTGRES_DB=testdb \
		-e POSTGRES_USER=postgres \
		-v $$PWD/BackupTest/PostgresqlData:/var/lib/postgresql/data \
		postgres:15

	@echo "⏳ Waiting for PostgreSQL..."
	sleep 10

	# Inject test data into PostgreSQL
	docker exec -i pgtest psql -U postgres -d testdb -c "CREATE TABLE TestData (id SERIAL PRIMARY KEY, name TEXT);"
	docker exec -i pgtest psql -U postgres -d testdb -c "INSERT INTO TestData (name) VALUES ('Alice'), ('Bob');"

	# Start MariaDB
	docker run -d --name mysqltest \
		--network autopg-net \
		-e MYSQL_ROOT_PASSWORD=mypassword \
		-e MYSQL_DATABASE=testdb \
		-e MYSQL_USER=backup \
		-e MYSQL_PASSWORD=mypassword \
		-v $$PWD/BackupTest/MySQLData:/var/lib/mysql \
		mariadb:11

	@echo "⏳ Waiting for MariaDB..."
	sleep 15

	# Inject test data into MariaDB
	docker exec -i mysqltest mariadb -ubackup -pmypassword testdb -e "CREATE TABLE TestData (id INT PRIMARY KEY AUTO_INCREMENT, name VARCHAR(255));"
	docker exec -i mysqltest mariadb -ubackup -pmypassword testdb -e "INSERT INTO TestData (name) VALUES ('Charlie'), ('Dana');"

	# Run backup for PostgreSQL
	docker run --rm --name autopgbackup_pg \
		--network autopg-net \
		-e PG_DBENGINE=postgresql \
		-e PG_DBHOST=pgtest \
		-e PG_USERNAME=postgres \
		-e PG_PASSWORD=mypassword \
		-e PG_DB_NAME=testdb \
		-e PG_MIN_DUMP_SIZE=1 \
		-e PG_DOWEEKLY=0 \
		-e PG_DOMONTHLY=0 \
		-e TZ="Europe/Amsterdam" \
		-v /etc/localtime:/etc/localtime:ro \
		-v $$PWD/BackupTest/PostgresqlBackup:/backup \
		$(IMAGE_NAME):$(TAG) backup-now

	# Run backup for MariaDB
	docker run --rm --name autopgbackup_mysql \
		--network autopg-net \
		-e PG_DBENGINE=mysql \
		-e PG_DBHOST=mysqltest \
		-e PG_USERNAME=backup \
		-e PG_PASSWORD=mypassword \
		-e PG_DB_NAME=testdb \
		-e PG_MIN_DUMP_SIZE=1 \
		-e PG_DOWEEKLY=0 \
		-e PG_DOMONTHLY=0 \
		-e TZ="Europe/Amsterdam" \
		-v /etc/localtime:/etc/localtime:ro \
		-v $$PWD/BackupTest/MySQLBackup:/backup \
		$(IMAGE_NAME):$(TAG) backup-now

	# Extract and verify PostgreSQL backup
	@echo "🔍 Verifying PostgreSQL backup..."
	@gunzip -c $$PWD/BackupTest/PostgresqlBackup/daily/testdb/*.gz > $$PWD/BackupTest/pgtest.sql
	@grep -q "CREATE DATABASE testdb" $$PWD/BackupTest/pgtest.sql && grep -q "COPY public.testdata (id, name) FROM stdin;" $$PWD/BackupTest/pgtest.sql || { echo "❌ PostgreSQL backup invalid."; exit 1; }

	# Extract and verify MySQL backup
	@echo "🔍 Verifying MySQL backup..."
	@gunzip -c $$PWD/BackupTest/MySQLBackup/daily/testdb/*.gz > $$PWD/BackupTest/mysqltest.sql
	@grep -q "CREATE TABLE \`TestData\`" $$PWD/BackupTest/mysqltest.sql && grep -q "INSERT INTO \`TestData\` VALUES" $$PWD/BackupTest/mysqltest.sql || { echo "❌ MySQL backup invalid."; exit 1; }

	# Cleanup containers
	-docker rm -f $(IMAGE_NAME) pgtest mysqltest || echo "Containers not found or already removed."
	-docker rmi -f postgres:15 mariadb:11

	# Cleanup backup folder
	rm -rf BackupTest

	# Cleanup Network
	docker network rm autopg-net || echo "Network not found or already removed."


