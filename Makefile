
build:
	docker build -t javanile/samba-ad-dc .

push: build
	git add .
	git commit -am "Push to docker hub"
	git push
	docker push javanile/samba-ad-dc

test:
	docker-compose down -v
	docker-compose up --build dc
