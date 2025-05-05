build:
	docker buildx bake --progress plain

dev:
	cd public/ && symfony serve --no-tls
