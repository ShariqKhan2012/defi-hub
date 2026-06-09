build:
	cd contracts && forge build

clean:
	cd contracts && forge clean

# Use as:
# make test ARGS=-vvv
# make test ARGS="--match-test testGTKDeployment -vvv"
test:
	cd contracts && forge test $(ARGS)

install:
	cd frontend && npm install

dev:
	cd frontend && npm run dev