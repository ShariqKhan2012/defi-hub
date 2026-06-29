.PHONY: install install-frontend install-contracts build clean test dev

build:
	cd contracts && forge build

clean:
	cd contracts && forge clean

# Use as:
# make test ARGS=-vvv
# make test ARGS="--match-test testGTKDeployment -vvv"
test:
	cd contracts && forge test $(ARGS)

install: install-frontend install-contracts

install-frontend:
	cd frontend && npm install

install-contracts:
	cd contracts && \
		forge install foundry-rs/forge-std && \
		forge install OpenZeppelin/openzeppelin-foundry-upgrades && \
		forge install OpenZeppelin/openzeppelin-contracts-upgradeable

dev:
	cd frontend && npm run dev