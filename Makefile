build:
	docker buildx bake

dev:
	cd public/ && symfony serve --no-tls
