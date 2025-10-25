export FULL_VERSION_RELEASE="$$(cat ./VERSION)"
export FULL_VERSION="$$(cat ./VERSION)-regen-dh"
export DOCKER_REPO="oriolegea/dockovpn"
export CBRANCH=$$(git rev-parse --abbrev-ref HEAD | tr / -)

.PHONY: build build-release build-local build-dev build-test build-branch install clean run

all: build

build:
	@echo "Making production version ${FULL_VERSION} of DockOvpn"
	docker build -t "${DOCKER_REPO}:${FULL_VERSION}" -t "${DOCKER_REPO}:latest" . --no-cache
	docker push "${DOCKER_REPO}:${FULL_VERSION}"
	docker push "${DOCKER_REPO}:latest"

build-release:
	@echo "Making manual release version ${FULL_VERSION_RELEASE} of DockOvpn"
	docker build -t "${DOCKER_REPO}:${FULL_VERSION_RELEASE}" -t ${FULL_VERSION} -t ${DOCKER_REPO}:latest . --no-cache
	docker push "${DOCKER_REPO}:${FULL_VERSION_RELEASE}"
	docker push "${DOCKER_REPO}:latest"
	# Note: This is by design that we don't push ${FULL_VERSION} to repo

build-local:
	@echo "Making version of DockOvpn for testing on local machine"
	docker build -t "${DOCKER_REPO}:local" . --no-cache

build-dev:
	@echo "Making development version of DockOvpn"
	docker build -t "${DOCKER_REPO}:dev" . --no-cache
	docker push "${DOCKER_REPO}:dev"

build-test:
	@echo "Making testing version of DockOvpn"
	docker build -t "${DOCKER_REPO}:test" . --no-cache
	docker push "${DOCKER_REPO}:test"

build-branch:
	@echo "Making build for branch: ${DOCKER_REPO}:${CBRANCH}"
	docker build -t "${DOCKER_REPO}:${CBRANCH}" --no-cache --progress plain .

publish-branch: build-branch
	docker push "${DOCKER_REPO}:${CBRANCH}"

install:
	@echo "Installing DockOvpn ${FULL_VERSION}"

clean:
	@echo "Remove shared volume with configs"
	docker volume rm Dockovpn_data

# Tests removed - original test container dependency eliminated

run:
	docker run --cap-add=NET_ADMIN \
	-v openvpn_conf:/opt/Dockovpn_data \
	-p 1194:1194/udp -p 80:8080/tcp \
	-e HOST_ADDR=localhost \
	--rm \
	${DOCKER_REPO}
